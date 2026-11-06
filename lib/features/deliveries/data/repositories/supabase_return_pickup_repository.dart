import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/operational_failure.dart';
import '../../domain/models/outbound_task_command.dart';
import '../../domain/models/return_pickup_command.dart';
import '../../domain/repositories/return_pickup_repository.dart';
import '../models/dto_readers.dart';
import '../models/return_pickup_handover_dto.dart';
import '../models/return_pickup_command_dto.dart';
import 'operational_read_access.dart';

/// Production adapter for shipper-owned return-pickup writes and the narrow
/// handover marker read. Handover uses its own RPC; it never calls the
/// outbound `report_store_handover` operation.
final class SupabaseReturnPickupRepository
    implements ReturnPickupRepository, ReturnPickupHandoverReader {
  const SupabaseReturnPickupRepository({required this.access});

  final OperationalReadAccess access;

  @override
  Future<ReturnPickupAck> execute(ReturnPickupCommand command) async {
    try {
      _validateCommand(command);
    } on FormatException {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }

    final capturedSession = access.currentSession;
    var dispatched = false;
    final outcome = await access
        .run<_PickupOutcome>(
          roles: const {'shipper'},
          action: (identity) async {
            identity.ensureCurrent();
            dynamic raw;
            try {
              dispatched = true;
              raw = await access.client
                  .rpc(command.operation.rpcName, params: _paramsFor(command))
                  .retry(enabled: false)
                  .timeout(access.readTimeout);
            } on PostgrestException catch (error) {
              final mapped = _mapPostgrestError(error);
              if (mapped is OutboundBusinessFailure ||
                  mapped is OutboundCommandFailure) {
                identity.ensureCurrent();
                return _PickupOutcome.failure(mapped);
              }
              // Auth, permission, transport and missing-RPC failures remain
              // under OperationalReadAccess so account epochs are authoritative.
              throw mapped;
            }
            identity.ensureCurrent();

            try {
              final dto = ReturnPickupCommandAckDto.fromJson(
                _object(raw),
                command: command,
              );
              identity.ensureCurrent();
              return _PickupOutcome.success(dto.toDomain());
            } on FormatException catch (_) {
              // A malformed response after dispatch is not proof of a
              // rollback.  The caller must retain and retry the same key.
              return _PickupOutcome.failure(
                const OutboundAcknowledgementFailure(),
              );
            } on TypeError catch (_) {
              return _PickupOutcome.failure(
                const OutboundAcknowledgementFailure(),
              );
            }
          },
        )
        .catchError((Object error) {
          final current = access.currentSession;
          if (dispatched &&
              error is OperationalFailure &&
              error.code == OperationalFailureCode.sessionExpired &&
              !identical(capturedSession, current) &&
              current.userId != null &&
              current.userId == capturedSession.userId &&
              current.failure == null) {
            // A same-user token refresh may have happened after commit.  Keep
            // the command envelope uncertain instead of changing requestId.
            throw const OutboundAcknowledgementFailure();
          }
          throw error;
        });

    final failure = outcome.failure;
    if (failure != null) throw failure;
    final ack = outcome.ack;
    if (ack == null || !ack.matches(command)) {
      throw const OutboundAcknowledgementFailure();
    }
    return ack;
  }

  @override
  Future<ReturnPickupHandoverStatus> getHandoverStatus(String taskId) async {
    try {
      DeliveryDtoReaders.checkUuid(taskId, 'p_task_id');
    } on FormatException {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }

    final outcome = await access.run<ReturnPickupHandoverStatus>(
      roles: const {'shipper'},
      action: (identity) async {
        identity.ensureCurrent();
        dynamic raw;
        try {
          raw = await access.client
              .rpc(
                'get_my_return_pickup_handover',
                params: <String, dynamic>{'p_task_id': taskId},
              )
              .retry(enabled: false)
              .timeout(access.readTimeout);
        } on PostgrestException catch (error) {
          throw _mapPostgrestError(error);
        }
        identity.ensureCurrent();
        final dto = ReturnPickupHandoverStatusDto.fromJson(
          _object(raw),
          taskId: taskId,
        );
        identity.ensureCurrent();
        return dto.toDomain();
      },
    );
    if (!outcome.isValid || !outcome.matchesTask(taskId)) {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }
    return outcome;
  }

  static Map<String, dynamic> _paramsFor(ReturnPickupCommand command) {
    switch (command.operation) {
      case ReturnPickupOperation.collect:
      case ReturnPickupOperation.handover:
        return <String, dynamic>{
          'p_task_id': command.taskId,
          'p_request_id': command.requestId,
          'p_items': command.items
              .map((item) => item.toJson())
              .toList(growable: false),
        };
      case ReturnPickupOperation.fail:
        return <String, dynamic>{
          'p_task_id': command.taskId,
          'p_request_id': command.requestId,
          'p_reason_code': command.reason!.value,
          'p_description': command.trimmedDescription,
        };
    }
  }

  static void _validateCommand(ReturnPickupCommand command) {
    DeliveryDtoReaders.checkUuid(command.taskId, 'p_task_id');
    DeliveryDtoReaders.checkUuid(command.requestId, 'p_request_id');
    DeliveryDtoReaders.checkUuid(command.returnRequestId, 'return_request_id');
    DeliveryDtoReaders.checkUuid(command.orderId, 'order_id');
    if (!command.isValid) {
      throw DeliveryDtoReaders.invalid('command', 'a valid pickup command');
    }
    if (command.isCollect || command.isHandover) {
      _validateItems(command.items);
    } else if (command.reason == null) {
      throw DeliveryDtoReaders.invalid('reason', 'a pickup failure reason');
    }
  }

  static void _validateItems(List<ReturnPickupItem> items) {
    if (items.isEmpty) {
      throw DeliveryDtoReaders.invalid(
        'p_items',
        'a non-empty approved return-item list',
      );
    }
    String? previous;
    final seen = <String>{};
    for (final item in items) {
      DeliveryDtoReaders.checkUuid(item.returnItemId, 'return_item_id');
      if (!item.hasValidQuantity) {
        throw DeliveryDtoReaders.invalid(
          'quantity',
          'a positive 32-bit integer',
        );
      }
      final id = item.returnItemId.toLowerCase();
      if (!seen.add(id)) {
        throw DeliveryDtoReaders.invalid(
          'p_items',
          'unique return-item UUIDs in ascending order',
        );
      }
      if (previous != null && id.compareTo(previous) < 0) {
        throw DeliveryDtoReaders.invalid(
          'p_items',
          'return-item UUIDs in ascending order',
        );
      }
      previous = id;
    }
  }

  static Map<String, dynamic> _object(dynamic raw) {
    if (raw is! Map) {
      throw const FormatException('Expected pickup acknowledgement object');
    }
    try {
      return Map<String, dynamic>.from(raw);
    } on TypeError {
      throw const FormatException(
        'Expected a string-keyed pickup acknowledgement object',
      );
    }
  }
}

final class _PickupOutcome {
  const _PickupOutcome.success(this.ack) : failure = null;
  const _PickupOutcome.failure(this.failure) : ack = null;

  final ReturnPickupAck? ack;
  final Object? failure;
}

/// Map only documented P08.1 markers.  Raw PostgREST text never crosses the
/// repository boundary.
Object _mapPostgrestError(PostgrestException error) {
  if (error.code == 'PT409' || error.code == 'P0001') {
    return switch (error.message.trim()) {
      'STATE_CONFLICT' ||
      'APPROVAL_UNRESOLVED' ||
      'TASK_CONFLICT' => const OutboundBusinessFailure(
        OutboundBusinessFailureCode.stateConflict,
      ),
      'STALE_ASSIGNMENT' => const OutboundCommandFailure(
        OutboundCommandFailureCode.staleAssignment,
      ),
      'ITEMS_MISMATCH' => const OutboundBusinessFailure(
        OutboundBusinessFailureCode.itemsMismatch,
      ),
      'CUSTODY_UNRESOLVED' => const OutboundBusinessFailure(
        OutboundBusinessFailureCode.custodyUnresolved,
      ),
      'IDEMPOTENCY_CONFLICT' => const OutboundBusinessFailure(
        OutboundBusinessFailureCode.idempotencyConflict,
      ),
      'INVALID_SHIPPER' => const OutboundCommandFailure(
        OutboundCommandFailureCode.permissionDenied,
      ),
      'INVALID_ARGUMENT' => const OperationalFailure(
        OperationalFailureCode.invalidData,
      ),
      'NOT_FOUND_OR_FORBIDDEN' => const OperationalFailure(
        OperationalFailureCode.permissionDenied,
      ),
      _ => const OperationalFailure(OperationalFailureCode.unexpected),
    };
  }
  if (error.code == '42501' || error.code == '403') {
    return const OperationalFailure(OperationalFailureCode.permissionDenied);
  }
  if (error.code == '22023' || error.code == '22P02') {
    return const OperationalFailure(OperationalFailureCode.invalidData);
  }
  if (error.code == '404' ||
      error.code == '42883' ||
      error.code == '42P01' ||
      error.code == 'PGRST202' ||
      error.code == 'PGRST205' ||
      error.code == '500' ||
      error.code == '502' ||
      error.code == '503' ||
      error.code == '504') {
    return const OperationalFailure(OperationalFailureCode.backendUnavailable);
  }
  return mapOperationalFailure(error);
}
