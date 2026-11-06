import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../deliveries/data/repositories/operational_read_access.dart';
import '../../domain/models/manager_return.dart';
import '../../domain/repositories/manager_return_repository.dart';
import '../models/manager_return_dto.dart';
import 'supabase_return_request_repository.dart';

/// Supabase adapter for return management. Every RPC re-checks the manager
/// role server-side; the role set here only fails fast on the client.
final class SupabaseManagerReturnRepository implements ManagerReturnRepository {
  const SupabaseManagerReturnRepository({required this.access});

  final OperationalReadAccess access;

  static const _roles = {'manager'};
  static const _videoBucket = 'return-videos';
  static const _videoUrlSeconds = 600;

  Future<T> _run<T>(Future<T> Function(ReadIdentity identity) action) =>
      runReturnCall(access, _roles, action);

  Map<String, Object?> _map(Object? raw) {
    if (raw is! Map) throw const FormatException('Invalid response');
    return Map<String, Object?>.from(raw);
  }

  @override
  Future<ManagerReturnList> list({
    ReturnRequestStatus? status,
    String? query,
  }) => _run((identity) async {
    final trimmed = query?.trim();
    final raw = await access.client
        .rpc(
          'list_manager_return_requests',
          params: {
            'p_status': status?.wireValue,
            'p_query': (trimmed == null || trimmed.isEmpty) ? null : trimmed,
          },
        )
        .retry(enabled: false);
    identity.ensureCurrent();
    return managerReturnListFromJson(_map(raw));
  });

  @override
  Future<ManagerReturnDetail> load(String returnId) => _run((identity) async {
    final raw = await access.client
        .rpc(
          'get_manager_return_request',
          params: {'p_return_request_id': returnId},
        )
        .retry(enabled: false);
    identity.ensureCurrent();
    final detail = managerReturnDetailFromJson(_map(raw));
    if (detail.returnId != returnId) {
      throw const FormatException('Detail for another return');
    }
    return detail;
  });

  @override
  Future<Uri> videoUrl(String objectPath) => _run((identity) async {
    final url = await access.client.storage
        .from(_videoBucket)
        .createSignedUrl(objectPath, _videoUrlSeconds);
    identity.ensureCurrent();
    return Uri.parse(url);
  });

  @override
  Future<void> approveCollection({
    required String returnId,
    required String requestId,
    required List<ManagerCollectionLine> lines,
    required String shipperId,
  }) => _run((identity) async {
    final raw = await access.client
        .rpc(
          'approve_return_collection',
          params: {
            'p_return_request_id': returnId,
            'p_request_id': requestId,
            'p_items': [
              for (final line in lines)
                {'order_item_id': line.orderItemId, 'quantity': line.quantity},
            ],
            'p_shipper_id': shipperId,
          },
        )
        .retry(enabled: false);
    identity.ensureCurrent();
    requireReturnAck(
      raw,
      operation: 'approve_return_collection',
      returnId: returnId,
      requestId: requestId,
      status: 'awaiting_return_pickup',
    );
  });

  @override
  Future<void> reject({
    required String returnId,
    required String requestId,
    required String reason,
  }) => _run((identity) async {
    final raw = await access.client
        .rpc(
          'reject_return_request',
          params: {
            'p_return_request_id': returnId,
            'p_request_id': requestId,
            'p_reason': reason,
          },
        )
        .retry(enabled: false);
    identity.ensureCurrent();
    requireReturnAck(
      raw,
      operation: 'reject_return_request',
      returnId: returnId,
      requestId: requestId,
      status: 'initially_rejected',
    );
  });

  static String _bucket(ManagerEvidenceKind kind) => switch (kind) {
    ManagerEvidenceKind.inspection => 'inspection-evidence',
    ManagerEvidenceKind.refund => 'refund-evidence',
  };

  @override
  Future<Uri> evidenceUrl(ManagerEvidenceKind kind, String objectPath) =>
      _run((identity) async {
        final url = await access.client.storage
            .from(_bucket(kind))
            .createSignedUrl(objectPath, _videoUrlSeconds);
        identity.ensureCurrent();
        return Uri.parse(url);
      });

  @override
  Future<String> uploadEvidence({
    required String returnId,
    required ManagerEvidenceKind kind,
    required String objectName,
    required ManagerEvidenceFile file,
  }) => _run((identity) async {
    // Storage policy: first folder must be the return request id.
    final path = '$returnId/$objectName';
    try {
      await access.client.storage
          .from(_bucket(kind))
          .uploadBinary(
            path,
            Uint8List.fromList(file.bytes),
            fileOptions: FileOptions(contentType: file.mimeType),
          );
    } on StorageException catch (error) {
      // A retried command reuses its object name; an existing object is ours.
      final duplicate =
          error.statusCode == '409' ||
          error.message.toLowerCase().contains('already exists');
      if (!duplicate) rethrow;
    }
    identity.ensureCurrent();
    return path;
  });

  Future<void> _command(
    String rpc,
    Map<String, Object?> params, {
    required String returnId,
    required String requestId,
    required String status,
  }) => _run((identity) async {
    final raw = await access.client
        .rpc(rpc, params: params)
        .retry(enabled: false);
    identity.ensureCurrent();
    requireReturnAck(
      raw,
      operation: rpc,
      returnId: returnId,
      requestId: requestId,
      status: status,
    );
  });

  @override
  Future<void> requestInfo({
    required String returnId,
    required String requestId,
    required String message,
  }) => _run((identity) async {
    final raw = await access.client
        .rpc(
          'request_return_info',
          params: {
            'p_return_request_id': returnId,
            'p_request_id': requestId,
            'p_message': message,
          },
        )
        .retry(enabled: false);
    identity.ensureCurrent();
    // The status is unchanged by an information request.
    final ack = Map<String, Object?>.from(raw as Map);
    if (ack['operation'] != 'request_return_info' ||
        ack['return_request_id'] != returnId ||
        ack['request_id'] != requestId) {
      throw const FormatException('Unexpected request_return_info ACK');
    }
  });

  @override
  Future<void> receive({
    required String returnId,
    required String taskId,
    required String requestId,
    required List<ManagerReturnItem> items,
  }) {
    final sorted = [...items]
      ..sort((a, b) => a.returnItemId.compareTo(b.returnItemId));
    return _command(
      'receive_customer_return',
      {
        'p_task_id': taskId,
        'p_request_id': requestId,
        'p_items': [
          for (final i in sorted)
            {'return_item_id': i.returnItemId, 'quantity': i.quantityCollected},
        ],
      },
      returnId: returnId,
      requestId: requestId,
      status: 'under_inspection',
    );
  }

  @override
  Future<void> acceptInspection({
    required String returnId,
    required String requestId,
    required List<ManagerInspectionLine> lines,
    required List<String> evidencePaths,
  }) => _command(
    'accept_inspected_return',
    {
      'p_return_request_id': returnId,
      'p_request_id': requestId,
      'p_items': [
        for (final l in lines)
          {
            'return_item_id': l.returnItemId,
            'sellable_quantity': l.sellableQuantity,
            'damaged_quantity': l.damagedQuantity,
          },
      ],
      'p_evidence_paths': evidencePaths,
    },
    returnId: returnId,
    requestId: requestId,
    status: 'awaiting_refund',
  );

  @override
  Future<void> rejectInspection({
    required String returnId,
    required String requestId,
    required String reason,
    required List<String> evidencePaths,
  }) => _command(
    'reject_inspected_return',
    {
      'p_return_request_id': returnId,
      'p_request_id': requestId,
      'p_reason': reason,
      'p_evidence_paths': evidencePaths,
    },
    returnId: returnId,
    requestId: requestId,
    status: 'awaiting_redelivery',
  );

  @override
  Future<void> recordRefund({
    required String returnId,
    required String requestId,
    required int amountVnd,
    required DateTime transferredAt,
    required String evidencePath,
  }) => _command(
    'record_return_refund',
    {
      'p_return_request_id': returnId,
      'p_request_id': requestId,
      'p_amount_vnd': amountVnd,
      'p_transferred_at': transferredAt.toUtc().toIso8601String(),
      'p_evidence_path': evidencePath,
    },
    returnId: returnId,
    requestId: requestId,
    status: 'refunded',
  );

  @override
  Future<void> assignRedelivery({
    required String returnId,
    required String requestId,
    required String shipperId,
  }) => _command(
    'assign_redelivery_task',
    {
      'p_return_request_id': returnId,
      'p_shipper_id': shipperId,
      'p_request_id': requestId,
    },
    returnId: returnId,
    requestId: requestId,
    status: 'awaiting_redelivery',
  );
}
