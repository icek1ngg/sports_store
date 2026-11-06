import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../deliveries/data/repositories/operational_read_access.dart';
import '../../../deliveries/domain/models/operational_failure.dart';
import '../../domain/models/cod_receipt.dart';
import '../../domain/repositories/cod_receipt_repository.dart';
import '../models/cod_receipt_dto.dart';

/// Supabase adapter for the manager-only P06.3 receipt transaction.
///
/// The operational access epoch verifies the server-managed manager role and
/// rejects an account change both before the RPC and after its response. The
/// RPC is called exactly once per repository invocation; retries are owned by
/// the caller with the same [CodReceiptCommand.requestId].
final class SupabaseCodReceiptRepository implements CodReceiptRepository {
  const SupabaseCodReceiptRepository({required this.access});

  final OperationalReadAccess access;

  @override
  Future<CodReceipt> confirmReceipt(CodReceiptCommand command) async {
    try {
      command.validate();
    } on FormatException {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }

    return access.run<CodReceipt>(
      roles: const {'manager'},
      action: (identity) async {
        identity.ensureCurrent();
        dynamic raw;
        try {
          raw = await access.client
              .rpc('confirm_cod_received', params: command.toRpcParams())
              .retry(enabled: false);
        } catch (error) {
          throw _mapReceiptError(error);
        }
        identity.ensureCurrent();
        try {
          if (raw is! Map) {
            throw const FormatException('Invalid COD receipt response');
          }
          final dto = CodReceiptDto.fromJson(
            Map<String, dynamic>.from(raw),
            command: command,
            managerId: identity.userId,
          );
          identity.ensureCurrent();
          return dto.toDomain();
        } on FormatException {
          throw const CodReceiptAcknowledgementFailure();
        } on TypeError {
          throw const CodReceiptAcknowledgementFailure();
        }
      },
    );
  }
}

OperationalFailure _mapReceiptError(Object error) {
  if (error is OperationalFailure) return error;
  if (error is PostgrestException) {
    // Authentication/authorization always wins over message text. A
    // server-generated denial must not become a business conflict merely
    // because its message happens to contain a known marker.
    if (error.code == '42501' || error.code == '403') {
      return const OperationalFailure(OperationalFailureCode.permissionDenied);
    }
    // Business markers are trusted only for the exact P06.3 conflict code
    // and exact documented message. This prevents arbitrary PostgREST text
    // (including a missing-RPC message) from being treated as a receipt
    // outcome.
    if (error.code == 'PT409') {
      return switch (error.message.trim()) {
        'AMOUNT_MISMATCH' => const CodReceiptFailure(
          CodReceiptFailureCode.amountMismatch,
        ),
        'IDEMPOTENCY_CONFLICT' => const CodReceiptFailure(
          CodReceiptFailureCode.idempotencyConflict,
        ),
        'CORRUPT_COD_STATE' => const CodReceiptFailure(
          CodReceiptFailureCode.corruptCodState,
        ),
        'STATE_CONFLICT' => const CodReceiptFailure(
          CodReceiptFailureCode.stateConflict,
        ),
        _ => const OperationalFailure(OperationalFailureCode.unexpected),
      };
    }
    if (error.code == '22023' || error.code == '22P02') {
      return const OperationalFailure(OperationalFailureCode.invalidData);
    }
    if (error.code == '404' ||
        error.code == '42883' ||
        error.code == 'PGRST202' ||
        error.code == 'PGRST205') {
      return const OperationalFailure(
        OperationalFailureCode.backendUnavailable,
      );
    }
  }
  return mapOperationalFailure(error);
}
