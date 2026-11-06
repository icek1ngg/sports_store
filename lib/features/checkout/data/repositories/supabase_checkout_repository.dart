import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../deliveries/data/repositories/operational_read_access.dart';
import '../../../deliveries/domain/models/operational_failure.dart';
import '../../domain/models/checkout_failure.dart';
import '../../domain/models/placement_request.dart';
import '../../domain/models/placement_result.dart';
import '../../domain/repositories/checkout_repository.dart';
import '../models/checkout_envelope_dto.dart';

/// Supabase adapter for the two checkout RPCs. The access helper is reused for
/// current-session/role checks; business error envelopes are decoded inside
/// its action so PostgREST cannot mask their lowercase error codes.
class SupabaseCheckoutRepository implements CheckoutRepository {
  SupabaseCheckoutRepository({required this.access});

  final OperationalReadAccess access;

  @override
  Future<PlacementResult> placeOrder(PlacementRequest request) =>
      _run((identity) async {
        identity.ensureCurrent();
        final raw = await access.client
            .rpc(
              'place_order',
              params: Map<String, dynamic>.from(request.toRpcParams()),
            )
            .retry(enabled: false);
        identity.ensureCurrent();
        final result = CheckoutEnvelopeDto.decodePlacement(raw);
        try {
          result.validateAgainst(request, customerId: identity.userId);
        } on FormatException {
          throw const CheckoutFailure(CheckoutFailureCode.invalidData);
        }
        return result;
      });

  @override
  Future<PlacementLookupResult> lookupPlacementResult(String requestId) {
    final normalized = requestId.trim().toLowerCase();
    if (!_isUuid(normalized)) {
      return Future.error(
        const CheckoutFailure(CheckoutFailureCode.invalidArgument),
      );
    }
    return _run((identity) async {
      identity.ensureCurrent();
      final raw = await access.client
          .rpc(
            'get_placement_result',
            params: <String, dynamic>{'p_request_id': normalized},
          )
          .retry(enabled: false);
      identity.ensureCurrent();
      final lookup = CheckoutEnvelopeDto.decodeLookup(raw);
      final order = lookup.result?.order;
      if (order != null &&
          (order.customerId != identity.userId.toLowerCase() ||
              order.requestId != normalized)) {
        throw const CheckoutFailure(CheckoutFailureCode.invalidData);
      }
      return lookup;
    });
  }

  Future<T> _run<T>(Future<T> Function(ReadIdentity identity) action) async {
    try {
      final result = await access.run<_CheckoutExecution<T>>(
        roles: const {'customer'},
        action: (identity) async {
          try {
            return _CheckoutExecution.value(await action(identity));
          } on CheckoutFailure catch (failure) {
            return _CheckoutExecution.failure(failure);
          } on PostgrestException catch (error) {
            // Keep transport-specific mapping within access.action. If this
            // escaped, OperationalReadAccess would map the business code to a
            // generic backend error before checkout could render it.
            return _CheckoutExecution.failure(_mapPostgrest(error));
          } on FormatException {
            return const _CheckoutExecution.failure(
              CheckoutFailure(CheckoutFailureCode.invalidData),
            );
          } on TypeError {
            return const _CheckoutExecution.failure(
              CheckoutFailure(CheckoutFailureCode.invalidData),
            );
          }
        },
      );
      if (result.failure != null) throw result.failure!;
      return result.value as T;
    } on CheckoutFailure {
      rethrow;
    } catch (error) {
      throw _mapOperational(error);
    }
  }

  static CheckoutFailure _mapPostgrest(PostgrestException error) {
    final code = error.code?.trim().toUpperCase();
    final failureCode = switch (code) {
      '401' ||
      'PGRST301' ||
      'PGRST302' ||
      'PGRST303' => CheckoutFailureCode.sessionExpired,
      '403' || '42501' => CheckoutFailureCode.permissionDenied,
      '22P02' || '22023' || '23514' => CheckoutFailureCode.invalidArgument,
      '23505' => CheckoutFailureCode.idempotencyConflict,
      _ => CheckoutFailureCode.externalDependencyUnavailable,
    };
    return CheckoutFailure(failureCode);
  }

  static CheckoutFailure _mapOperational(Object error) {
    if (error is CheckoutFailure) return error;
    final failure = mapOperationalFailure(error);
    return CheckoutFailure(switch (failure.code) {
      OperationalFailureCode.sessionExpired =>
        CheckoutFailureCode.sessionExpired,
      OperationalFailureCode.permissionDenied =>
        CheckoutFailureCode.permissionDenied,
      OperationalFailureCode.network => CheckoutFailureCode.network,
      OperationalFailureCode.backendUnavailable =>
        CheckoutFailureCode.backendUnavailable,
      OperationalFailureCode.invalidData => CheckoutFailureCode.invalidData,
      OperationalFailureCode.staleAssignment ||
      OperationalFailureCode.unexpected => CheckoutFailureCode.unexpected,
    });
  }

  static bool _isUuid(String value) =>
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
          .hasMatch(value);
}

class _CheckoutExecution<T> {
  const _CheckoutExecution.value(this.value) : failure = null;
  const _CheckoutExecution.failure(this.failure) : value = null;

  final T? value;
  final CheckoutFailure? failure;
}
