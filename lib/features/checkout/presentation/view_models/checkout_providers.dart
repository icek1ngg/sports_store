import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../cart/domain/models/cart_failure.dart';
import '../../../cart/domain/models/cart_item.dart';
import '../../../cart/presentation/view_models/cart_providers.dart';
import '../../../cart/presentation/view_models/cart_state.dart';
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

/// A route-owned snapshot of checked cart variants. Null preserves the legacy
/// all-cart route; an explicitly empty set must never expand to the whole cart.
final selectedCheckoutVariantIdsProvider = Provider<Set<String>?>(
  (ref) => null,
  dependencies: const [],
);

final checkoutProvider =
    AsyncNotifierProvider.autoDispose<CheckoutViewModel, CheckoutState>(
      CheckoutViewModel.new,
      retry: (count, error) => null,
      dependencies: [selectedCheckoutVariantIdsProvider],
    );

class CheckoutViewModel extends AsyncNotifier<CheckoutState> {
  int _epoch = 0;
  bool _running = false;
  String? _userId;
  PlacementRequest? _pending;
  Set<String>? _selection;
  List<CartItem> _cartItems = const [];
  ProviderSubscription<Future<CartState>>? _cartChanges;

  @override
  Future<CheckoutState> build() async {
    final epoch = ++_epoch;
    _running = false;
    _pending = null;
    _userId = null;
    final selectedIds = ref.watch(selectedCheckoutVariantIdsProvider);
    final selection = selectedIds == null
        ? null
        : Set<String>.unmodifiable(
            selectedIds.map((id) => id.trim().toLowerCase()),
          );
    _selection = selection;
    _cartItems = const [];

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

    _cartChanges = ref.listen(
      cartProvider.future,
      (_, _) => ref.invalidateSelf(),
    );
    final cart = await ref.read(cartProvider.future);
    if (!_current(epoch)) throw const _SupersededCheckout();
    _cartItems = cart.items;

    final store = ref.read(pendingPlacementStoreProvider);
    final pending = await store.read(userId);
    if (!_current(epoch)) throw const _SupersededCheckout();
    if (pending == null) {
      final items = _selectedCartItems(cart.items, selection);
      if (cart.isMutating || cart.hasPendingMutation) {
        throw const CheckoutFailure(
          CheckoutFailureCode.invalidArgument,
          message: 'Hãy quay lại giỏ hàng để xác minh thay đổi đang chờ trước khi đặt.',
        );
      }
      return CheckoutState(items: items, userId: userId);
    }

    // Recovery belongs to the persisted request, even when its rows have been
    // consumed or this route now contains a different/stale selection.
    final items = _pendingCartItems(cart.items, pending.request);
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
        return await _completePlacement(
          items,
          result,
          pending.request,
          userId,
          epoch,
        );
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
    final submission = ref.keepAlive();
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
      } on CheckoutFailure {
        rethrow;
      } catch (_) {
        throw CheckoutFailure(
          CheckoutFailureCode.localStorageUnavailable,
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
      final completed = await _completePlacement(
        current.items,
        result,
        request,
        userId,
        epoch,
      );
      if (!_current(epoch)) return false;
      state = AsyncData(completed);
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
      submission.close();
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
    final submission = ref.keepAlive();
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
      final result = lookup.isCommitted
          ? lookup.result
          : await ref.read(checkoutRepositoryProvider).placeOrder(request);
      if (!_current(epoch)) return false;
      if (result == null) {
        throw const CheckoutFailure(CheckoutFailureCode.invalidData);
      }
      final completed = await _completePlacement(
        current.items,
        result,
        request,
        userId,
        epoch,
      );
      if (!_current(epoch)) return false;
      state = AsyncData(completed);
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
      submission.close();
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
    var next = previous;
    if (definitive) {
      final hadSubmittedRequest = _pending != null;
      _pending = null;
      // Local persistence/validation can fail before this notifier ever sends
      // a request. Do not delete an unreadable or another route's journal.
      if (hadSubmittedRequest) await _clearPendingQuietly(userId, epoch);
      if (!_current(epoch)) return false;
      // A retry may have recovered a request from a different selection.
      // Once rejected definitively, a NEW request belongs to this route again.
      try {
        next = previous.copyWith(
          items: _selectedCartItems(_cartItems, _selection),
        );
      } on CheckoutFailure catch (selectionFailure) {
        state = AsyncError(selectionFailure, stack);
        return false;
      }
    }
    if (!_current(epoch)) return false;
    state = AsyncData(
      next.copyWith(
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

  Future<CheckoutState> _completePlacement(
    List<CartItem> items,
    PlacementResult result,
    PlacementRequest request,
    String userId,
    int epoch,
  ) async {
    try {
      result.validateAgainst(request, customerId: userId);
    } on FormatException {
      throw const CheckoutFailure(CheckoutFailureCode.invalidData);
    }
    // The receipt must stay visible when the cart refreshes after commit.
    _cartChanges?.close();
    ref.invalidate(cartProvider);
    _pending = null;
    await _clearPendingQuietly(userId, epoch);
    if (!_current(epoch)) throw const _SupersededCheckout();
    return CheckoutState(items: items, result: result, userId: userId);
  }

  static String _newRequestId() {
    return const Uuid().v4();
  }
}

List<CartItem> _selectedCartItems(
  List<CartItem> items,
  Set<String>? selection,
) {
  if (selection == null) return items;
  final selected = items
      .where((item) => selection.contains(item.variantId.trim().toLowerCase()))
      .toList(growable: false);
  if (selection.isEmpty || selected.length != selection.length) {
    throw const CheckoutFailure(
      CheckoutFailureCode.invalidArgument,
      message: 'Lựa chọn sản phẩm đã thay đổi hoặc không còn trong giỏ. Hãy quay lại giỏ hàng để chọn lại.',
    );
  }
  return selected;
}

List<CartItem> _pendingCartItems(
  List<CartItem> cartItems,
  PlacementRequest request,
) {
  final byId = {
    for (final item in cartItems) item.variantId.trim().toLowerCase(): item,
  };
  return [
    for (final item in request.items)
      CartItem(
        variantId: item.variantId,
        quantity: item.quantity,
        product: byId[item.variantId]?.product,
        variant: byId[item.variantId]?.variant,
      ),
  ];
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
