import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/operational_failure.dart';
import '../../domain/models/outbound_completion_failure.dart';
import '../../domain/models/outbound_completion_command.dart';
import '../../domain/models/outbound_task_command.dart';
import '../../domain/repositories/outbound_completion_repository.dart';
import '../models/dto_readers.dart';
import '../models/outbound_completion_ack_dto.dart';
import 'operational_read_access.dart';

/// Production adapter for P05.1's atomic completion RPC.
final class SupabaseOutboundCompletionRepository
    implements OutboundCompletionRepository {
  const SupabaseOutboundCompletionRepository({required this.access});

  final OperationalReadAccess access;

  @override
  Future<void> execute(OutboundCompletionCommand command) async {
    _validate(command);
    final captured = access.currentSession;
    var dispatched = false;
    final outcome = await access
        .run<_CompletionOutcome>(
          roles: const {'shipper'},
          action: (identity) async {
            identity.ensureCurrent();
            dynamic raw;
            try {
              dispatched = true;
              raw = await access.client
                  .rpc(
                    'complete_outbound_delivery',
                    params: <String, dynamic>{
                      'p_task_id': command.taskId,
                      'p_request_id': command.requestId,
                      'p_received_all_items': command.receivedAllItems,
                      'p_collected_amount_vnd':
                          command.reportedCollectedAmountVnd,
                    },
                  )
                  .retry(enabled: false)
                  .timeout(access.readTimeout);
            } on PostgrestException catch (error) {
              final mapped = _mapError(error);
              if (mapped is OutboundCompletionBusinessFailure) {
                identity.ensureCurrent();
                return _CompletionOutcome.failure(mapped);
              }
              throw mapped;
            }
            identity.ensureCurrent();
            try {
              final ack = OutboundCompletionAckDto.fromJson(
                _object(raw),
                command: command,
              );
              identity.ensureCurrent();
              return _CompletionOutcome.success(ack);
            } on FormatException catch (_) {
              return _CompletionOutcome.failure(
                const OutboundAcknowledgementFailure(),
              );
            } on TypeError catch (_) {
              return _CompletionOutcome.failure(
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
              !identical(captured, current) &&
              current.userId != null &&
              current.userId == captured.userId &&
              current.failure == null) {
            throw const OutboundAcknowledgementFailure();
          }
          throw error;
        });
    if (outcome.failure != null) throw outcome.failure!;
  }

  static void _validate(OutboundCompletionCommand command) {
    DeliveryDtoReaders.checkUuid(command.taskId, 'p_task_id');
    DeliveryDtoReaders.checkUuid(command.requestId, 'p_request_id');
    if (!command.receivedAllItems || !command.hasSafePositiveAmount) {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }
  }

  static Map<String, dynamic> _object(dynamic raw) {
    if (raw is! Map) throw const FormatException('Expected completion receipt');
    try {
      return Map<String, dynamic>.from(raw);
    } on TypeError {
      throw const FormatException('Expected string-keyed completion receipt');
    }
  }
}

final class _CompletionOutcome {
  const _CompletionOutcome.success(OutboundCompletionAckDto this.ack)
    : failure = null;
  const _CompletionOutcome.failure(Object this.failure) : ack = null;

  final OutboundCompletionAckDto? ack;
  final Object? failure;
}

Object _mapError(PostgrestException error) {
  if (error.code == 'PT409' || error.code == 'P0001') {
    return switch (error.message.trim()) {
      'ITEMS_MISMATCH' => const OutboundCompletionBusinessFailure(
        OutboundCompletionBusinessFailureCode.itemsMismatch,
      ),
      'AMOUNT_MISMATCH' => const OutboundCompletionBusinessFailure(
        OutboundCompletionBusinessFailureCode.amountMismatch,
      ),
      'IDEMPOTENCY_CONFLICT' => const OutboundCompletionBusinessFailure(
        OutboundCompletionBusinessFailureCode.idempotencyConflict,
      ),
      'CUSTODY_UNRESOLVED' => const OutboundCompletionBusinessFailure(
        OutboundCompletionBusinessFailureCode.custodyUnresolved,
      ),
      'DEPENDENCY_NOT_READY' => const OutboundCompletionBusinessFailure(
        OutboundCompletionBusinessFailureCode.dependencyNotReady,
      ),
      _ => const OutboundCompletionBusinessFailure(
        OutboundCompletionBusinessFailureCode.stateConflict,
      ),
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
