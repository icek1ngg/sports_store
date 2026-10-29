import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/operational_failure.dart';
import '../../domain/models/outbound_failure_command.dart';
import '../../domain/models/outbound_task_command.dart';
import '../../domain/repositories/outbound_failure_repository.dart';
import '../models/dto_readers.dart';
import '../models/outbound_failure_ack_dto.dart';
import 'operational_read_access.dart';

/// Production adapter for the atomic `fail_delivery_task` RPC.
final class SupabaseOutboundFailureRepository
    implements OutboundFailureRepository {
  const SupabaseOutboundFailureRepository({required this.access});

  final OperationalReadAccess access;

  @override
  Future<OutboundFailureAck> execute(OutboundFailureCommand command) async {
    try {
      _validateCommand(command);
    } on FormatException {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }

    final capturedSession = access.currentSession;
    var dispatched = false;
    final outcome = await access
        .run<_FailureOutcome>(
          roles: const {'shipper'},
          action: (identity) async {
            identity.ensureCurrent();
            dynamic raw;
            try {
              dispatched = true;
              raw = await access.client
                  .rpc(
                    'fail_delivery_task',
                    params: <String, dynamic>{
                      'p_task_id': command.taskId,
                      'p_request_id': command.requestId,
                      'p_reason_code': command.reason.value,
                      'p_description': command.trimmedDescription,
                    },
                  )
                  .retry(enabled: false)
                  .timeout(access.readTimeout);
            } on PostgrestException catch (error) {
              final mapped = _mapPostgrestError(error);
              if (mapped is OutboundBusinessFailure) {
                identity.ensureCurrent();
                return _FailureOutcome.failure(mapped);
              }
              // Authentication, permission, transport and missing-RPC errors
              // must go through OperationalReadAccess so its shared epoch
              // mapping remains authoritative.
              throw mapped;
            }
            identity.ensureCurrent();

            try {
              final ack = OutboundFailureAckDto.fromJson(
                _object(raw),
                command: command,
              );
              identity.ensureCurrent();
              return _FailureOutcome.success(ack);
            } on FormatException catch (_) {
              return _FailureOutcome.failure(
                const OutboundAcknowledgementFailure(),
              );
            } on TypeError catch (_) {
              return _FailureOutcome.failure(
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
            // The write may have committed before a same-user token refresh.
            // Preserve the envelope so the caller retries with the same key.
            throw const OutboundAcknowledgementFailure();
          }
          throw error;
        });

    final failure = outcome.failure;
    if (failure != null) throw failure;
    final ack = outcome.ack;
    if (ack == null) throw const OutboundAcknowledgementFailure();
    return ack.toDomain();
  }

  static void _validateCommand(OutboundFailureCommand command) {
    DeliveryDtoReaders.checkUuid(command.taskId, 'p_task_id');
    DeliveryDtoReaders.checkUuid(command.requestId, 'p_request_id');
    if (!command.hasValidAttempt || !command.hasValidDescription) {
      throw DeliveryDtoReaders.invalid(
        'command',
        'a valid attempt and reason description',
      );
    }
  }

  static Map<String, dynamic> _object(dynamic raw) {
    if (raw is! Map) {
      throw const FormatException('Expected failure receipt');
    }
    try {
      return Map<String, dynamic>.from(raw);
    } on TypeError {
      throw const FormatException('Expected a string-keyed failure receipt');
    }
  }
}

/// Keep business and acknowledgement failures typed while
/// [OperationalReadAccess.run] maps transport/auth failures centrally.
final class _FailureOutcome {
  const _FailureOutcome.success(OutboundFailureAckDto this.ack)
    : failure = null;

  const _FailureOutcome.failure(Object this.failure) : ack = null;

  final OutboundFailureAckDto? ack;
  final Object? failure;
}

Object _mapPostgrestError(PostgrestException error) {
  if (error.code == 'PT409' || error.code == 'P0001') {
    final marker = error.message.trim();
    final failureCode = switch (marker) {
      'STATE_CONFLICT' => OutboundBusinessFailureCode.stateConflict,
      'IDEMPOTENCY_CONFLICT' => OutboundBusinessFailureCode.idempotencyConflict,
      'CUSTODY_UNRESOLVED' => OutboundBusinessFailureCode.custodyUnresolved,
      'ITEMS_MISMATCH' => OutboundBusinessFailureCode.itemsMismatch,
      'STOCK_CONFLICT' => OutboundBusinessFailureCode.stockConflict,
      'COD_CONFLICT' => OutboundBusinessFailureCode.codConflict,
      // The failure RPC does not expose an amount-specific domain error.  A
      // COD mismatch is the existing safe business category for this marker.
      'AMOUNT_MISMATCH' => OutboundBusinessFailureCode.codConflict,
      'ATTEMPT_LIMIT' => OutboundBusinessFailureCode.attemptLimit,
      'DISPATCH_CONFLICT' => OutboundBusinessFailureCode.dispatchConflict,
      _ => null,
    };
    if (failureCode != null) return OutboundBusinessFailure(failureCode);
    return const OperationalFailure(OperationalFailureCode.unexpected);
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
