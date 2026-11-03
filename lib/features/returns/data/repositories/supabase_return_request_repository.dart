import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../deliveries/data/repositories/operational_read_access.dart';
import '../../../deliveries/domain/models/operational_failure.dart';
import '../../domain/models/return_request_context.dart';
import '../../domain/models/return_request_failure.dart';
import '../../domain/models/return_request_submission.dart';
import '../../domain/repositories/return_request_repository.dart';
import '../models/return_request_dto.dart';

/// Supabase adapter for MH13. Authorization is enforced by the server
/// (`get_return_request_context`, `submit_return_request`, Storage policies);
/// the shared access epoch only rejects stale sessions/account changes.
final class SupabaseReturnRequestRepository implements ReturnRequestRepository {
  const SupabaseReturnRequestRepository({required this.access});

  static const bucket = 'return-videos';

  final OperationalReadAccess access;

  @override
  Future<ReturnRequestContext> loadContext(String orderId) {
    return _run((identity) async {
      final raw = await access.client
          .rpc('get_return_request_context', params: {'p_order_id': orderId})
          .retry(enabled: false);
      identity.ensureCurrent();
      if (raw is! Map) throw const FormatException('Invalid context');
      final context = returnRequestContextFromJson(
        Map<String, Object?>.from(raw),
      );
      if (context.orderId != orderId) {
        throw const FormatException('Context for another order');
      }
      return context;
    });
  }

  @override
  Future<String> uploadVideo({
    required String orderId,
    required String requestId,
    required ReturnVideoFile video,
  }) {
    return _run((identity) async {
      final path = '${identity.userId}/$orderId/$requestId.${video.extension}';
      try {
        await access.client.storage
            .from(bucket)
            .uploadBinary(
              path,
              video.bytes,
              fileOptions: FileOptions(
                contentType: video.mimeType,
                upsert: false,
              ),
            );
      } on StorageException catch (error) {
        // A retry of the same request id after an ambiguous upload finds the
        // object already present; the server re-validates it on submit.
        if (!_isDuplicate(error)) rethrow;
      }
      identity.ensureCurrent();
      return path;
    });
  }

  @override
  Future<ReturnRequestReceipt> submit(ReturnRequestCommand command) {
    return _run((identity) async {
      final raw = await access.client
          .rpc('submit_return_request', params: command.toRpcParams())
          .retry(enabled: false);
      identity.ensureCurrent();
      if (raw is! Map) throw const FormatException('Invalid receipt');
      return returnRequestReceiptFromJson(
        Map<String, Object?>.from(raw),
        command: command,
      );
    });
  }

  Future<T> _run<T>(Future<T> Function(ReadIdentity identity) action) =>
      runCustomerReturnCall(access, action);
}

/// Runs a customer-only returns call inside the shared access epoch and
/// rethrows a precise [ReturnRequestFailure] (MH13 and MH14).
Future<T> runCustomerReturnCall<T>(
  OperationalReadAccess access,
  Future<T> Function(ReadIdentity identity) action,
) => runReturnCall(access, const {'customer'}, action);

/// Same as [runCustomerReturnCall] for an explicit role set (manager screens).
Future<T> runReturnCall<T>(
  OperationalReadAccess access,
  Set<String> roles,
  Future<T> Function(ReadIdentity identity) action,
) async {
  try {
    return await access.run<T>(
      roles: roles,
      action: (identity) async {
        try {
          return await action(identity);
        } on OperationalFailure {
          rethrow;
        } catch (error) {
          // `run` normalizes unknown errors to OperationalFailure; carry the
          // precise returns failure through it.
          throw _ReturnFailureCarrier(mapReturnRequestError(error));
        }
      },
    );
  } on _ReturnFailureCarrier catch (carrier) {
    throw carrier.failure;
  } catch (error) {
    throw mapReturnRequestError(error);
  }
}

final class _ReturnFailureCarrier extends OperationalFailure {
  const _ReturnFailureCarrier(this.failure)
    : super(OperationalFailureCode.unexpected);

  final ReturnRequestFailure failure;
}

bool _isDuplicate(StorageException error) =>
    error.statusCode == '409' ||
    error.error == 'Duplicate' ||
    error.message.toLowerCase().contains('already exists');

/// Maps transport/server errors. Business markers are trusted only with the
/// exact error code + message documented in the migration.
ReturnRequestFailure mapReturnRequestError(Object error) {
  if (error is ReturnRequestFailure) return error;
  if (error is PostgrestException) {
    if (error.code == '42501' || error.code == '403') {
      return error.message.trim() == 'AUTH_REQUIRED'
          ? const ReturnRequestFailure(ReturnRequestFailureCode.sessionExpired)
          : const ReturnRequestFailure(
              ReturnRequestFailureCode.permissionDenied,
            );
    }
    final marker = error.message.trim();
    final code = switch ((error.code, marker)) {
      ('PT404', 'ORDER_NOT_FOUND') => ReturnRequestFailureCode.orderNotFound,
      ('PT404', 'RETURN_NOT_FOUND') => ReturnRequestFailureCode.returnNotFound,
      ('PT409', 'ORDER_NOT_DELIVERED') =>
        ReturnRequestFailureCode.orderNotDelivered,
      ('PT409', 'RETURN_WINDOW_EXPIRED') =>
        ReturnRequestFailureCode.returnWindowExpired,
      ('PT409', 'ACTIVE_RETURN_EXISTS') =>
        ReturnRequestFailureCode.activeReturnExists,
      ('PT409', 'VIDEO_ALREADY_USED') =>
        ReturnRequestFailureCode.videoAlreadyUsed,
      ('PT409', 'IDEMPOTENCY_CONFLICT') =>
        ReturnRequestFailureCode.idempotencyConflict,
      ('PT409', 'STATE_CONFLICT') => ReturnRequestFailureCode.stateConflict,
      ('PT409', 'ITEMS_MISMATCH') => ReturnRequestFailureCode.itemsMismatch,
      ('PT409', 'INVALID_SHIPPER') => ReturnRequestFailureCode.invalidShipper,
      ('PT409', 'AMOUNT_MISMATCH') => ReturnRequestFailureCode.amountMismatch,
      ('PT422', 'EVIDENCE_REQUIRED') =>
        ReturnRequestFailureCode.evidenceRequired,
      ('22023', 'INVALID_TRANSFER_TIME') =>
        ReturnRequestFailureCode.invalidTransferTime,
      ('PT422', 'VIDEO_REQUIRED') => ReturnRequestFailureCode.videoRequired,
      ('22023', _) || ('22P02', _) => ReturnRequestFailureCode.invalidInput,
      ('404', _) ||
      ('42883', _) ||
      ('PGRST202', _) ||
      ('PGRST205', _) => ReturnRequestFailureCode.backendUnavailable,
      _ => ReturnRequestFailureCode.unexpected,
    };
    return ReturnRequestFailure(code);
  }
  if (error is StorageException) {
    final status = error.statusCode;
    if (status == '401' || status == '403') {
      return const ReturnRequestFailure(
        ReturnRequestFailureCode.permissionDenied,
      );
    }
    if (status == '413') {
      return const ReturnRequestFailure(ReturnRequestFailureCode.invalidInput);
    }
    return const ReturnRequestFailure(ReturnRequestFailureCode.network);
  }
  if (error is TimeoutException ||
      error is http.ClientException ||
      error is AuthRetryableFetchException) {
    return const ReturnRequestFailure(ReturnRequestFailureCode.network);
  }
  if (error is OperationalFailure) {
    return ReturnRequestFailure(switch (error.code) {
      OperationalFailureCode.sessionExpired =>
        ReturnRequestFailureCode.sessionExpired,
      OperationalFailureCode.permissionDenied =>
        ReturnRequestFailureCode.permissionDenied,
      OperationalFailureCode.network => ReturnRequestFailureCode.network,
      OperationalFailureCode.backendUnavailable =>
        ReturnRequestFailureCode.backendUnavailable,
      _ => ReturnRequestFailureCode.unexpected,
    });
  }
  return const ReturnRequestFailure(ReturnRequestFailureCode.unexpected);
}
