import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/delivery_task.dart';
import '../../domain/models/delivery_task_details.dart';
import '../../domain/models/delivery_task_query.dart';
import '../../domain/models/operational_failure.dart';
import '../../domain/repositories/delivery_repository.dart';
import '../models/delivery_task_dto.dart';
import '../models/delivery_task_details_dto.dart';
import '../models/delivery_task_page_dto.dart';
import 'operational_read_access.dart';

/// Real P01.1 read RPC adapter. It has no demo fallback or business writes.
class SupabaseDeliveryRepository
    implements DeliveryRepository, DeliveryMapReader {
  SupabaseDeliveryRepository({required this.access});

  final OperationalReadAccess access;
  static const _pageSize = 200;
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  void _validateId(String id) {
    if (!_uuid.hasMatch(id)) {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }
  }

  List<Map<String, dynamic>> _rows(dynamic response) {
    if (response is! List) throw const FormatException('Expected row list');
    return response.map((row) {
      if (row is! Map<String, dynamic>) {
        throw const FormatException('Expected row');
      }
      return row;
    }).toList();
  }

  @override
  Future<List<DeliveryTaskSnapshot>> listTasks() => access.run(
    roles: const {'shipper'},
    action: (identity) async {
      final tasks = <DeliveryTaskSnapshot>[];
      final ids = <String>{};
      String? afterId;
      while (true) {
        identity.ensureCurrent();
        var query = access.client.rpc('read_my_delivery_tasks');
        if (afterId != null) query = query.gt('task_id', afterId);
        final response = await query
            .order('task_id')
            .limit(_pageSize)
            .retry(enabled: false);
        identity.ensureCurrent();
        final rows = _rows(response);
        for (final row in rows) {
          final task = DeliveryTaskDto.fromJson(row).toDomain();
          if (!ids.add(task.taskId.toLowerCase())) {
            throw const FormatException('Duplicate task');
          }
          tasks.add(task);
        }
        if (rows.length < _pageSize) break;
        afterId = tasks.last.taskId;
      }
      return List.unmodifiable(tasks);
    },
  );

  @override
  Future<DeliveryTaskPage> queryTasks(DeliveryTaskQuery query) {
    // DeliveryTaskQuery normalizes and validates all user-controlled filters
    // before this method can reach the network.
    return access.run(
      roles: const {'shipper'},
      action: (identity) async {
        identity.ensureCurrent();
        final response = await access.client
            .rpc('list_my_delivery_tasks', params: query.toRpcParams())
            .retry(enabled: false);
        identity.ensureCurrent();
        final payload = _object(response);
        return DeliveryTaskPageDto.fromJson(payload, query: query).toDomain();
      },
    );
  }

  Future<DeliveryTaskSnapshot> _readTask(
    String taskId,
    ReadIdentity identity,
  ) async {
    identity.ensureCurrent();
    final response = await access.client
        .rpc('read_my_delivery_tasks', params: {'p_task_id': taskId})
        .retry(enabled: false);
    identity.ensureCurrent();
    final rows = _rows(response);
    if (rows.isEmpty) {
      throw const OperationalFailure(OperationalFailureCode.staleAssignment);
    }
    if (rows.length != 1) throw const FormatException('Expected one task');
    final task = DeliveryTaskDto.fromJson(rows.single).toDomain();
    if (task.taskId.toLowerCase() != taskId.toLowerCase()) {
      throw const FormatException('Wrong task');
    }
    return task;
  }

  @override
  Future<DeliveryTaskSnapshot> getTask(String taskId) async {
    _validateId(taskId);
    return access.run(
      roles: const {'shipper'},
      action: (identity) => _readTask(taskId, identity),
    );
  }

  Future<DeliveryTaskDetails> _readTaskDetails(
    String taskId,
    ReadIdentity identity, {
    required bool allowMissingDestinationCoordinates,
  }) async {
    identity.ensureCurrent();
    dynamic response;
    try {
      response = await access.client
          .rpc('get_my_delivery_task', params: {'p_task_id': taskId})
          .retry(enabled: false);
    } on PostgrestException catch (error) {
      // The detail RPC uses NOT_FOUND_OR_FORBIDDEN (P0002) for a task
      // that is no longer assigned or is outside the permitted history.
      // Keep this mapping local: P0002 has no meaning for other reads.
      if (error.code == 'P0002') {
        throw const OperationalFailure(OperationalFailureCode.staleAssignment);
      }
      rethrow;
    }
    identity.ensureCurrent();
    return DeliveryTaskDetailsDto.fromJson(
      _object(response),
      requestedTaskId: taskId,
      allowMissingDestinationCoordinates: allowMissingDestinationCoordinates,
    ).toDomain();
  }

  @override
  Future<DeliveryTaskDetails> getTaskDetails(String taskId) async {
    _validateId(taskId);
    return access.run(
      roles: const {'shipper'},
      action: (identity) => _readTaskDetails(
        taskId,
        identity,
        allowMissingDestinationCoordinates: false,
      ),
    );
  }

  @override
  Future<DeliveryTaskDetails> getMapTaskDetails(String taskId) async {
    _validateId(taskId);
    return access.run(
      roles: const {'shipper'},
      action: (identity) => _readTaskDetails(
        taskId,
        identity,
        allowMissingDestinationCoordinates: true,
      ),
    );
  }

  Map<String, dynamic> _object(dynamic response) {
    if (response is! Map) {
      throw const FormatException('Expected page object');
    }
    try {
      return Map<String, dynamic>.from(response);
    } on TypeError {
      throw const FormatException('Expected string-keyed page object');
    }
  }
}
