import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../cart/domain/models/cart_failure.dart';
import '../../../cart/presentation/view_models/cart_providers.dart';
import '../../../deliveries/data/repositories/operational_providers.dart';
import '../../../deliveries/domain/models/operational_failure.dart';
import '../../data/repositories/pending_placement_store.dart';
import '../../data/repositories/supabase_checkout_repository.dart';
import '../../domain/models/checkout_failure.dart';
import '../../domain/models/placement_request.dart';
import '../../domain/models/placement_result.dart';
import '../../domain/repositories/checkout_repository.dart';
import 'checkout_state.dart';

final checkoutRepositoryProvider = Provider.autoDispose<CheckoutRepository>((
  ref,
) {
  return SupabaseCheckoutRepository(
    access: ref.watch(operationalReadAccessProvider),
  );
});

final pendingPlacementStoreProvider =
    Provider.autoDispose<PendingPlacementStore>((ref) {
      return SecurePendingPlacementStore();
    });

/// Production renders OSM tiles. Widget/Android tests may override this flag
/// to false so map interactions remain deterministic and offline.
final checkoutMapTilesEnabledProvider = Provider<bool>((ref) => true);

final checkoutProvider =
    AsyncNotifierProvider.autoDispose<CheckoutViewModel, CheckoutState>(
      CheckoutViewModel.new,
      retry: (count, error) => null,
    );

class CheckoutViewModel extends AsyncNotifier<CheckoutState> {
  int _epoch = 0;
  bool _running = false;
  String? _userId;
  PlacementRequest? _pending;

  @override
  Future<CheckoutState> build() async {
    final epoch = ++_epoch;
    _running = false;
    _pending = null;
    _userId = null;

    final session = await ref.watch(operationalSessionProvider.future);
    if (!_current(epoch)) throw const _SupersededCheckout();
    if (session.userId == null || session.failure != null) {
      throw _checkoutFromOperational(
        session.failure ??
            const OperationalFailure(OperationalFailureCode.sessionExpired),
      );
    }
    final userId = session.userId!;
    _userId = userId;

    final cart = await ref.watch(cartProvider.future);
    final items = cart.items;
    if (!_current(epoch)) throw const _SupersededCheckout();

    final store = ref.read(pendingPlacementStoreProvider);
    final pending = await store.read(userId);
    if (!_current(epoch)) throw const _SupersededCheckout();
    if (pending == null) {
      if (cart.isMutating || cart.hasPendingMutation) {
        throw const CheckoutFailure(
          CheckoutFailureCode.invalidArgument,
          message: 'Hãy quay lại giỏ hàng để xác minh thay đổi đang chờ trước khi đặt.',
        );
      }
      return CheckoutState(items: items, userId: userId);
    }

    _pending = pending.request;
    try {
      final lookup = await ref
          .read(checkoutRepositoryProvider)
          .lookupPlacementResult(pending.request.requestId);
      if (!_current(epoch)) throw const _SupersededCheckout();
      if (lookup.isCommitted) {
        final result = lookup.result;
        if (result == null) {
          throw const CheckoutFailure(CheckoutFailureCode.invalidData);
        }
        try {
          result.validateAgainst(pending.request, customerId: userId);
        } on FormatException {
          throw const CheckoutFailure(CheckoutFailureCode.invalidData);
        }
        _pending = null;
        await _clearPendingQuietly(userId, epoch);
        return CheckoutState(items: items, result: result, userId: userId);
      }
      return CheckoutState(
        items: items,
        pendingRequest: pending.request,
        recoveryNotFound: true,
        userId: userId,
      );
    } on _SupersededCheckout {
      rethrow;
    } on CheckoutFailure catch (failure) {
      if (!_current(epoch)) throw const _SupersededCheckout();
      return CheckoutState(
        items: items,
        pendingRequest: pending.request,
        isRecovering: true,
        failure: failure,
        userId: userId,
      );
    }
  }

  /// Submits the current cart snapshot. The request is persisted before any
  /// network call, then reused unchanged for retries and lookup.
  Future<bool> placeOrder({
    required String recipientName,
    required String recipientPhone,
    required String addressDetail,
    required double latitude,
    required double longitude,
  }) async {
    if (_running || !ref.mounted) return false;
    final current = state.asData?.value;
    final userId = _userId;
    if (current == null || userId == null || current.result != null) {
      return false;
    }
    if (_pending != null || current.pendingRequest != null) {
      return false;
    }
    if (current.items.isEmpty || current.hasUnavailableItems) {
      state = AsyncData(
        current.copyWith(
          failure: const CheckoutFailure(CheckoutFailureCode.invalidArgument),
        ),
      );
      return false;
    }

    final epoch = _epoch;
    _running = true;
    try {
      final request = PlacementRequest.fromCart(
        requestId: _newRequestId(),
        items: current.items,
        recipientName: recipientName,
        recipientPhone: recipientPhone,
        addressDetail: addressDetail,
        latitude: latitude,
        longitude: longitude,
      );
      final store = ref.read(pendingPlacementStoreProvider);
      // Durable write is intentionally before RPC. If it fails, no request is
      // sent because the app could not guarantee idempotent recovery.
      try {
        await store.write(userId, request);
      } catch (_) {
        throw CheckoutFailure(
          CheckoutFailureCode.invalidData,
          message: 'Không thể lưu yêu cầu đặt hàng để thử lại an toàn.',
          definitiveNoCommit: true,
        );
      }
      if (!_current(epoch)) return false;
      _pending = request;
      state = AsyncData(
        current.copyWith(
          pendingRequest: request,
          isSubmitting: true,
          isRecovering: false,
          recoveryNotFound: false,
          clearFailure: true,
        ),
      );
      final result = await ref
          .read(checkoutRepositoryProvider)
          .placeOrder(request);
      if (!_current(epoch)) return false;
      _verifyReceipt(result, request, userId);
      _pending = null;
      await _clearPendingQuietly(userId, epoch);
      if (!_current(epoch)) return false;
      state = AsyncData(
        current.copyWith(
          result: result,
          clearPendingRequest: true,
          isSubmitting: false,
          isRecovering: false,
          recoveryNotFound: false,
          clearFailure: true,
        ),
      );
      return true;
    } on _SupersededCheckout {
      return false;
    } on CheckoutFailure catch (failure, stack) {
      return _finishFailure(failure, stack, epoch, userId, current);
    } on FormatException catch (_, stack) {
      return _finishFailure(
        CheckoutFailure(
          CheckoutFailureCode.invalidArgument,
          definitiveNoCommit: true,
        ),
        stack,
        epoch,
        userId,
        current,
      );
    } on CartFailure catch (failure, stack) {
      return _finishFailure(
        _checkoutFromCart(failure),
        stack,
        epoch,
        userId,
        current,
      );
    } catch (error, stack) {
      return _finishFailure(
        const CheckoutFailure(CheckoutFailureCode.unexpected),
        stack,
        epoch,
        userId,
        current,
      );
    } finally {
      if (_current(epoch)) _running = false;
    }
  }

  /// Alias for integrations that call the action `submit`.
  Future<bool> submit({
    required String recipientName,
    required String recipientPhone,
    required String addressDetail,
    required double latitude,
    required double longitude,
  }) => placeOrder(
    recipientName: recipientName,
    recipientPhone: recipientPhone,
    addressDetail: addressDetail,
    latitude: latitude,
    longitude: longitude,
  );

  /// Looks up a pending request and, only when the server says not_found,
  /// retries the same exact payload. `not_found` never clears the store.
  Future<bool> retryPending() async {
    if (_running || !ref.mounted) return false;
    final current = state.asData?.value;
    final request = _pending ?? current?.pendingRequest;
    final userId = _userId;
    if (current == null || request == null || userId == null) return false;
    final epoch = _epoch;
    _running = true;
    _pending = request;
    state = AsyncData(
      current.copyWith(
        pendingRequest: request,
        isSubmitting: true,
        isRecovering: true,
        recoveryNotFound: false,
        clearFailure: true,
      ),
    );
    try {
      final lookup = await ref
          .read(checkoutRepositoryProvider)
          .lookupPlacementResult(request.requestId);
      if (!_current(epoch)) return false;
      if (lookup.isCommitted) {
        final result = lookup.result;
        if (result == null) {
          throw const CheckoutFailure(CheckoutFailureCode.invalidData);
        }
        try {
          result.validateAgainst(request, customerId: userId);
        } on FormatException {
          throw const CheckoutFailure(CheckoutFailureCode.invalidData);
        }
        _pending = null;
        await _clearPendingQuietly(userId, epoch);
        if (!_current(epoch)) return false;
        state = AsyncData(
          current.copyWith(
            result: result,
            clearPendingRequest: true,
            isSubmitting: false,
            isRecovering: false,
          ),
        );
        return true;
      }
      final result = await ref
          .read(checkoutRepositoryProvider)
          .placeOrder(request);
      if (!_current(epoch)) return false;
      _verifyReceipt(result, request, userId);
      _pending = null;
      await _clearPendingQuietly(userId, epoch);
      if (!_current(epoch)) return false;
      state = AsyncData(
        current.copyWith(
          result: result,
          clearPendingRequest: true,
          isSubmitting: false,
          isRecovering: false,
          recoveryNotFound: false,
        ),
      );
      return true;
    } on CheckoutFailure catch (failure, stack) {
      return _finishFailure(failure, stack, epoch, userId, current);
    } catch (error, stack) {
      return _finishFailure(
        const CheckoutFailure(CheckoutFailureCode.unexpected),
        stack,
        epoch,
        userId,
        current,
      );
    } finally {
      if (_current(epoch)) _running = false;
    }
  }

  Future<bool> recoverPending() => retryPending();

  Future<void> refresh() async {
    if (!ref.mounted || _running) return;
    ref.invalidateSelf();
    await future;
  }

  Future<void> _clearPendingQuietly(String userId, int epoch) async {
    try {
      await ref.read(pendingPlacementStoreProvider).clear(userId);
    } catch (_) {
      // A committed receipt is still shown. If persistence cleanup failed,
      // next app start will lookup the same request and replay the receipt.
    }
    if (!_current(epoch)) return;
  }

  Future<bool> _finishFailure(
    CheckoutFailure failure,
    StackTrace stack,
    int epoch,
    String userId,
    CheckoutState previous,
  ) async {
    if (!_current(epoch)) return false;
    final definitive = failure.canClearPending;
    if (definitive) {
      _pending = null;
      await _clearPendingQuietly(userId, epoch);
    }
    if (!_current(epoch)) return false;
    state = AsyncData(
      previous.copyWith(
        isSubmitting: false,
        isRecovering: !definitive,
        recoveryNotFound: false,
        failure: failure,
        pendingRequest: definitive ? null : _pending,
        clearPendingRequest: definitive,
      ),
    );
    return false;
  }

  bool _current(int epoch) => ref.mounted && epoch == _epoch;

  void _verifyReceipt(
    PlacementResult result,
    PlacementRequest request,
    String userId,
  ) {
    try {
      result.validateAgainst(request, customerId: userId);
    } on FormatException {
      throw const CheckoutFailure(CheckoutFailureCode.invalidData);
    }
  }

  static String _newRequestId() {
    return const Uuid().v4();
  }
}

CheckoutFailure _checkoutFromOperational(OperationalFailure failure) =>
    CheckoutFailure(switch (failure.code) {
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

CheckoutFailure _checkoutFromCart(
  CartFailure failure,
) => CheckoutFailure(switch (failure.code) {
  CartFailureCode.insufficientStock => CheckoutFailureCode.insufficientStock,
  CartFailureCode.permissionDenied => CheckoutFailureCode.permissionDenied,
  CartFailureCode.sessionExpired => CheckoutFailureCode.sessionExpired,
  CartFailureCode.network => CheckoutFailureCode.network,
  CartFailureCode.backendUnavailable => CheckoutFailureCode.backendUnavailable,
  CartFailureCode.invalidData => CheckoutFailureCode.invalidArgument,
  CartFailureCode.unavailable ||
  CartFailureCode.unexpected => CheckoutFailureCode.unexpected,
});

class _SupersededCheckout implements Exception {
  const _SupersededCheckout();
}
