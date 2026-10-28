import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/operational_failure.dart';
import '../../domain/models/outbound_task_command.dart';
import '../../domain/models/redelivery_command.dart';
import '../../domain/repositories/redelivery_repository.dart';
import '../models/dto_readers.dart';
import '../models/redelivery_command_dto.dart';
import 'operational_read_access.dart';

/// Production adapter for the four shipper-owned redelivery RPCs.
///
/// No client-side fallback or optimistic state is used.  A successful RPC is
/// accepted only after the exact receipt has been decoded; the caller then
/// performs the authoritative MH11/MH10 reads.  SDK retries are disabled so a
/// timeout can only be retried by replaying the same command key.
final class SupabaseRedeliveryRepository implements RedeliveryRepository {
  const SupabaseRedeliveryRepository({required this.access});

  final OperationalReadAccess access;

  @override
  Future<RedeliveryAck> execute(RedeliveryCommand command) async {
    try {
      _validateCommand(command);
    } on FormatException {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }

    final capturedSession = access.currentSession;
    var dispatched = false;
    final outcome = await access
        .run<_RedeliveryOutcome>(
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
                return _RedeliveryOutcome.failure(mapped);
              }
              throw mapped;
            }
            identity.ensureCurrent();
            try {
              final dto = RedeliveryCommandAckDto.fromJson(
                _object(raw),
                command: command,
              );
              identity.ensureCurrent();
              return _RedeliveryOutcome.success(dto.toDomain());
            } on FormatException catch (_) {
              return _RedeliveryOutcome.failure(
                const OutboundAcknowledgementFailure(),
              );
            } on TypeError catch (_) {
              return _RedeliveryOutcome.failure(
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
            // A same-user token refresh may have happened after commit. Keep
            // the request envelope uncertain so the VM replays the same key.
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

  static Map<String, dynamic> _paramsFor(RedeliveryCommand command) {
    return switch (command.operation) {
      RedeliveryOperation.accept => <String, dynamic>{
        'p_task_id': command.taskId,
        'p_request_id': command.requestId,
        'p_items': command.items
            .map(
              (item) => <String, dynamic>{
                'return_item_id': item.itemId,
                'quantity': item.quantity,
              },
            )
            .toList(growable: false),
      },
      RedeliveryOperation.start => <String, dynamic>{
        'p_task_id': command.taskId,
        'p_request_id': command.requestId,
      },
      RedeliveryOperation.complete => <String, dynamic>{
        'p_task_id': command.taskId,
        'p_request_id': command.requestId,
        'p_received_all_items': command.receivedAllItems,
      },
      RedeliveryOperation.fail => <String, dynamic>{
        'p_task_id': command.taskId,
        'p_request_id': command.requestId,
        'p_reason_code': command.reason!.value,
        'p_description': command.trimmedDescription,
      },
    };
  }

  static void _validateCommand(RedeliveryCommand command) {
    DeliveryDtoReaders.checkUuid(command.taskId, 'p_task_id');
    DeliveryDtoReaders.checkUuid(command.requestId, 'p_request_id');
    DeliveryDtoReaders.checkUuid(command.returnRequestId, 'return_request_id');
    DeliveryDtoReaders.checkUuid(command.orderId, 'order_id');
    if (!command.isValid) {
      throw DeliveryDtoReaders.invalid('command', 'a valid redelivery command');
    }
    if (command.isAccept) {
      _validateItems(command.items);
    }
  }

  static void _validateItems(List<RedeliveryItem> items) {
    if (items.isEmpty) {
      throw DeliveryDtoReaders.invalid(
        'p_items',
        'a non-empty approved redelivery plan',
      );
    }
    String? previous;
    final seen = <String>{};
    for (final item in items) {
      DeliveryDtoReaders.checkUuid(item.itemId, 'return_item_id');
      if (!item.hasValidQuantity) {
        throw DeliveryDtoReaders.invalid(
          'quantity',
          'a positive 32-bit integer',
        );
      }
      final id = item.itemId.toLowerCase();
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
      throw const FormatException('Expected redelivery acknowledgement object');
    }
    try {
      return Map<String, dynamic>.from(raw);
    } on TypeError {
      throw const FormatException(
        'Expected a string-keyed redelivery acknowledgement object',
      );
    }
  }
}

final class _RedeliveryOutcome {
  const _RedeliveryOutcome.success(this.ack) : failure = null;
  const _RedeliveryOutcome.failure(this.failure) : ack = null;

  final RedeliveryAck? ack;
  final Object? failure;
}

Object _mapPostgrestError(PostgrestException error) {
  if (error.code == 'PT409' || error.code == 'P0001') {
    return switch (error.message.trim()) {
      'STATE_CONFLICT' => const OutboundBusinessFailure(
        OutboundBusinessFailureCode.stateConflict,
      ),
      'IDEMPOTENCY_CONFLICT' => const OutboundBusinessFailure(
        OutboundBusinessFailureCode.idempotencyConflict,
      ),
      'CUSTODY_UNRESOLVED' => const OutboundBusinessFailure(
        OutboundBusinessFailureCode.custodyUnresolved,
      ),
      'ITEMS_MISMATCH' => const OutboundBusinessFailure(
        OutboundBusinessFailureCode.itemsMismatch,
      ),
      'DEPENDENCY_NOT_READY' => const OperationalFailure(
        OperationalFailureCode.backendUnavailable,
      ),
      'STALE_ASSIGNMENT' => const OutboundCommandFailure(
        OutboundCommandFailureCode.staleAssignment,
      ),
      'NOT_FOUND_OR_FORBIDDEN' || 'INVALID_SHIPPER' => const OperationalFailure(
        OperationalFailureCode.permissionDenied,
      ),
      'INVALID_ARGUMENT' => const OperationalFailure(
        OperationalFailureCode.invalidData,
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
