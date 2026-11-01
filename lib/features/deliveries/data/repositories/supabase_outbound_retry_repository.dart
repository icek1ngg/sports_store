import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/operational_failure.dart';
import '../../domain/models/outbound_retry_command.dart';
import '../../domain/models/outbound_task_command.dart';
import '../../domain/repositories/outbound_retry_repository.dart';
import '../models/dto_readers.dart';
import '../models/outbound_retry_ack_dto.dart';
import 'operational_read_access.dart';

/// Production adapter for the explicit shipper-owned second-attempt RPC.
final class SupabaseOutboundRetryRepository implements OutboundRetryRepository {
  const SupabaseOutboundRetryRepository({required this.access});

  final OperationalReadAccess access;

  @override
  Future<OutboundRetryAck> execute(OutboundRetryCommand command) async {
    try {
      DeliveryDtoReaders.checkUuid(command.taskId, 'p_task_id');
      DeliveryDtoReaders.checkUuid(command.requestId, 'p_request_id');
    } on FormatException {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }

    final capturedSession = access.currentSession;
    var dispatched = false;
    final outcome = await access
        .run<_RetryOutcome>(
          roles: const {'shipper'},
          action: (identity) async {
            identity.ensureCurrent();
            dynamic raw;
            try {
              dispatched = true;
              raw = await access.client
                  .rpc(
                    'retry_outbound_delivery_task',
                    params: <String, dynamic>{
                      'p_task_id': command.taskId,
                      'p_request_id': command.requestId,
                    },
                  )
                  .retry(enabled: false)
                  .timeout(access.readTimeout);
            } on PostgrestException catch (error) {
              final mapped = _mapRetryPostgrestError(error);
              if (mapped is OutboundBusinessFailure) {
                identity.ensureCurrent();
                return _RetryOutcome.failure(mapped);
              }
              throw mapped;
            }
            identity.ensureCurrent();

            try {
              final ack = OutboundRetryAckDto.fromJson(
                _object(raw),
                command: command,
              );
              identity.ensureCurrent();
              return _RetryOutcome.success(ack);
            } on FormatException catch (_) {
              return _RetryOutcome.failure(
                const OutboundAcknowledgementFailure(),
              );
            } on TypeError catch (_) {
              return _RetryOutcome.failure(
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
            throw const OutboundAcknowledgementFailure();
          }
          throw error;
        });

    if (outcome.failure != null) throw outcome.failure!;
    final ack = outcome.ack;
    if (ack == null) throw const OutboundAcknowledgementFailure();
    return ack.toDomain();
  }

  static Map<String, dynamic> _object(dynamic raw) {
    if (raw is! Map) throw const FormatException('Expected retry receipt');
    try {
      return Map<String, dynamic>.from(raw);
    } on TypeError {
      throw const FormatException('Expected a string-keyed retry receipt');
    }
  }
}

final class _RetryOutcome {
  const _RetryOutcome.success(this.ack) : failure = null;
  const _RetryOutcome.failure(this.failure) : ack = null;

  final OutboundRetryAckDto? ack;
  final Object? failure;
}

Object _mapRetryPostgrestError(PostgrestException error) {
  if (error.code == 'PT409' || error.code == 'P0001') {
    final failureCode = switch (error.message.trim()) {
      'STATE_CONFLICT' => OutboundBusinessFailureCode.stateConflict,
      'IDEMPOTENCY_CONFLICT' => OutboundBusinessFailureCode.idempotencyConflict,
      'CUSTODY_UNRESOLVED' => OutboundBusinessFailureCode.custodyUnresolved,
      'ATTEMPT_LIMIT' => OutboundBusinessFailureCode.attemptLimit,
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
