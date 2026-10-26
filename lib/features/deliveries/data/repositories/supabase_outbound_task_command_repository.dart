import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/operational_failure.dart';
import '../../domain/models/outbound_task_command.dart';
import '../../domain/repositories/outbound_task_command_repository.dart';
import '../models/dto_readers.dart';
import '../models/outbound_task_command_ack_dto.dart';
import 'operational_read_access.dart';

/// Production adapter for the P04.1 accept/start command RPCs.
///
/// The command has no client-owned state or stock fields. The server owns the
/// transition, and this adapter returns only after a strict command receipt
/// has been checked. The caller must refetch the authoritative task details.
final class SupabaseOutboundTaskCommandRepository
    implements OutboundTaskCommandRepository {
  const SupabaseOutboundTaskCommandRepository({required this.access});

  final OperationalReadAccess access;

  @override
  Future<void> execute(OutboundTaskCommand command) async {
    try {
      _validateCommand(command);
    } on FormatException {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }

    final capturedSession = access.currentSession;
    var dispatched = false;
    final outcome = await access
        .run<_CommandOutcome>(
          roles: const {'shipper'},
          action: (identity) async {
            identity.ensureCurrent();
            dynamic raw;
            try {
              dispatched = true;
              raw = await access.client
                  .rpc(
                    _rpcName(command.action),
                    params: <String, dynamic>{
                      'p_task_id': command.taskId,
                      'p_request_id': command.requestId,
                    },
                  )
                  .retry(enabled: false)
                  .timeout(access.readTimeout);
            } on PostgrestException catch (error) {
              final mapped = _mapPostgrestError(error);
              if (mapped is OutboundBusinessFailure) {
                identity.ensureCurrent();
                return _CommandOutcome.failure(mapped);
              }
              // Auth, permission, transport and missing-RPC errors must go
              // through OperationalReadAccess so the shared epoch mapping wins.
              throw mapped;
            }
            identity.ensureCurrent();

            OutboundTaskCommandAckDto ack;
            try {
              ack = OutboundTaskCommandAckDto.fromJson(
                _object(raw),
                command: command,
              );
            } on FormatException catch (_) {
              return _CommandOutcome.failure(
                const OutboundAcknowledgementFailure(),
              );
            } on TypeError catch (_) {
              return _CommandOutcome.failure(
                const OutboundAcknowledgementFailure(),
              );
            }
            // Do not retain an acknowledgement from an account epoch that ended
            // while the response was being decoded.
            identity.ensureCurrent();
            return _CommandOutcome.success(ack);
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
            // Preserve the envelope; a new epoch must recheck role on retry.
            throw const OutboundAcknowledgementFailure();
          }
          throw error;
        });

    final failure = outcome.failure;
    if (failure != null) throw failure;
    // The DTO is deliberately discarded. execute() acknowledges only the
    // committed command; the ViewModel performs the authoritative refetch.
  }

  static void _validateCommand(OutboundTaskCommand command) {
    DeliveryDtoReaders.checkUuid(command.taskId, 'p_task_id');
    DeliveryDtoReaders.checkUuid(command.requestId, 'p_request_id');
  }

  static String _rpcName(OutboundTaskAction action) => switch (action) {
    OutboundTaskAction.acceptGoods => 'accept_delivery_task',
    OutboundTaskAction.startDelivery => 'start_delivery_task',
  };

  static Map<String, dynamic> _object(dynamic raw) {
    if (raw is! Map) throw const FormatException('Expected command receipt');
    try {
      return Map<String, dynamic>.from(raw);
    } on TypeError {
      throw const FormatException('Expected a string-keyed command receipt');
    }
  }
}

/// A narrow internal result lets typed business/acknowledgement failures
/// escape after [OperationalReadAccess.run] has completed its session checks.
/// Throwing those failures inside `run` would cause its generic mapper to
/// erase their outbound-specific type.
final class _CommandOutcome {
  const _CommandOutcome.success(OutboundTaskCommandAckDto this.ack)
    : failure = null;

  const _CommandOutcome.failure(Object this.failure) : ack = null;

  final OutboundTaskCommandAckDto? ack;
  final Object? failure;
}

Object _mapPostgrestError(PostgrestException error) {
  if (error.code == 'PT409') {
    final marker = error.message.trim();
    final failureCode = switch (marker) {
      'STATE_CONFLICT' => OutboundBusinessFailureCode.stateConflict,
      'IDEMPOTENCY_CONFLICT' => OutboundBusinessFailureCode.idempotencyConflict,
      'CUSTODY_UNRESOLVED' => OutboundBusinessFailureCode.custodyUnresolved,
      'ITEMS_MISMATCH' => OutboundBusinessFailureCode.itemsMismatch,
      'STOCK_CONFLICT' => OutboundBusinessFailureCode.stockConflict,
      'COD_CONFLICT' => OutboundBusinessFailureCode.codConflict,
      'ATTEMPT_LIMIT' => OutboundBusinessFailureCode.attemptLimit,
      'DISPATCH_CONFLICT' => OutboundBusinessFailureCode.dispatchConflict,
      _ => null,
    };
    if (failureCode != null) {
      return OutboundBusinessFailure(failureCode);
    }
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
  // Preserve the shared transport/auth mapper for everything else. This
  // deliberately avoids exposing PostgREST message text to the UI.
  return mapOperationalFailure(error);
}
