import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../deliveries/data/repositories/operational_providers.dart';
import '../../data/repositories/supabase_cart_repository.dart';
import '../../domain/models/cart_failure.dart';
import '../../domain/repositories/cart_repository.dart';
import 'cart_state.dart';

final cartRepositoryProvider = Provider<CartRepository>((ref) {
  return SupabaseCartRepository(
    access: ref.watch(operationalReadAccessProvider),
  );
});

// Keep uncertain absolute targets across navigation and same-account token
// refreshes. Logout/account changes discard the visible user-scoped state.
final cartProvider = AsyncNotifierProvider<CartViewModel, CartState>(
  CartViewModel.new,
  retry: (count, error) => null,
);

class CartViewModel extends AsyncNotifier<CartState> {
  int _epoch = 0;
  String? _userId;
  // A request may outlive an auth epoch. Retain its lock until it settles,
  // including when the customer switches away and back before completion.
  final Map<String, _CartOperation> _operations = {};
  _CartMutation? _pending;
  CartState? _lastSnapshot;

  bool get _running => _operations.containsKey(_userId);

  @override
  Future<CartState> build() async {
    final epoch = ++_epoch;
    // Riverpod may already have replaced state with AsyncLoading when a
    // dependency rebuild starts. Keep the last known snapshot by owner.
    final previous = _lastSnapshot;
    final previousUserId = _userId;
    state = const AsyncLoading();
    final repository = ref.watch(cartRepositoryProvider);
    final sessionState = ref.watch(operationalSessionProvider);
    final session = sessionState.isLoading
        ? await ref.watch(operationalSessionProvider.future)
        : sessionState.requireValue;
    if (!_current(epoch)) throw const _SupersededCart();
    if (_userId != session.userId) {
      _userId = session.userId;
      _lastSnapshot = null;
      // Only restore a returning customer's still-running command. Never
      // transfer another account's intent or completed request into this UI.
      _pending = _operations[_userId]?.command;
    }
    if (session.userId == null || session.failure != null) {
      throw const CartFailure(CartFailureCode.sessionExpired);
    }
    try {
      final items = await repository.getItems();
      if (!_current(epoch)) throw const _SupersededCart();
      final snapshot = CartState(
        items: items,
        isMutating: _running,
        hasPendingMutation: _pending != null,
      );
      _lastSnapshot = snapshot;
      return snapshot;
    } catch (error) {
      if (!_current(epoch)) throw const _SupersededCart();
      final failure = mapCartFailure(error);
      if (previous != null &&
          previousUserId == _userId &&
          _pending != null &&
          (failure.code == CartFailureCode.network ||
              failure.code == CartFailureCode.backendUnavailable)) {
        // The known snapshot is visibly uncertain and checkout remains
        // blocked. Authorization/invalid-data errors never use this fallback.
        return CartState(
          items: previous.items,
          isMutating: _running,
          hasPendingMutation: true,
          mutationError: failure,
        );
      }
      throw failure;
    }
  }

  Future<void> refresh() async {
    final userId = _userId;
    if (!ref.mounted || _running || state.isLoading || userId == null) return;
    final epoch = _epoch;
    final operation = _CartOperation();
    _operations[userId] = operation;
    final previous = state.asData?.value;
    state = const AsyncLoading();
    try {
      final items = await ref.read(cartRepositoryProvider).getItems();
      if (!_current(epoch)) return;
      final snapshot = CartState(
        items: items,
        hasPendingMutation: _pending != null,
        mutationError: _pending != null ? previous?.mutationError : null,
      );
      _lastSnapshot = snapshot;
      state = AsyncData(snapshot);
    } catch (error, stack) {
      if (!_current(epoch)) return;
      if (previous != null && _pending != null) {
        state = AsyncData(
          CartState(
            items: previous.items,
            hasPendingMutation: true,
            mutationError: mapCartFailure(error),
          ),
        );
      } else {
        state = AsyncError(mapCartFailure(error), stack);
      }
    } finally {
      _finishOperation(userId, operation);
    }
  }

  Future<bool> addItem({required String variantId, required int quantity}) {
    return _mutate((repository) async {
      if (quantity < 1) throw const CartFailure(CartFailureCode.invalidData);
      // Read fresh quantities instead of adding to a stale MH05 snapshot.
      final items = await repository.getItems();
      final existing = items.where(
        (item) => item.variantId.toLowerCase() == variantId.toLowerCase(),
      );
      final currentQuantity = existing.isEmpty ? 0 : existing.single.quantity;
      final target = BigInt.from(currentQuantity) + BigInt.from(quantity);
      if (target > BigInt.parse('9007199254740991')) {
        throw const CartFailure(CartFailureCode.invalidData);
      }
      return _CartMutation(variantId, target.toInt());
    });
  }

  Future<bool> setQuantity({required String variantId, required int quantity}) {
    return _mutate((repository) async {
      if (quantity < 1) throw const CartFailure(CartFailureCode.invalidData);
      return _CartMutation(variantId, quantity);
    });
  }

  Future<bool> removeItem(String variantId) =>
      _mutate((repository) async => _CartMutation(variantId, null));

  Future<bool> retryPendingMutation() {
    final pending = _pending;
    if (pending == null) return Future.value(false);
    return _mutate((repository) async => pending, retry: true);
  }

  Future<bool> _mutate(
    Future<_CartMutation> Function(CartRepository repository) prepare, {
    bool retry = false,
  }) async {
    final userId = _userId;
    if (!ref.mounted ||
        _running ||
        (!retry && _pending != null) ||
        state.isLoading ||
        state.hasError ||
        userId == null) {
      return false;
    }
    final previous = state.asData?.value;
    if (previous == null) return false;
    final epoch = _epoch;
    final operation = _CartOperation();
    _operations[userId] = operation;
    try {
      state = AsyncData(
        CartState(
          items: previous.items,
          isMutating: true,
          hasPendingMutation: _pending != null,
          mutationError: retry ? previous.mutationError : null,
        ),
      );
      final repository = ref.read(cartRepositoryProvider);
      final command = await prepare(repository);
      if (!_current(epoch)) return false;
      operation.command = command;
      _pending = command;
      if (command.quantity == null) {
        await repository.removeItem(command.variantId);
      } else {
        await repository.setQuantity(
          variantId: command.variantId,
          quantity: command.quantity!,
        );
      }
      if (!_current(epoch)) return false;
      final items = await repository.getItems();
      if (!_current(epoch)) return false;
      _pending = null;
      final snapshot = CartState(items: items);
      _lastSnapshot = snapshot;
      state = AsyncData(snapshot);
      return true;
    } catch (error) {
      if (!_current(epoch)) return false;
      final failure = mapCartFailure(error);
      // These responses reject the action before a write. Other failures can
      // have an unknown result; retain the absolute target for explicit retry.
      // Session/permission errors may be raised by the access helper AFTER
      // the server writes. They must retain the same target for later retry.
      if (failure.code == CartFailureCode.insufficientStock ||
          failure.code == CartFailureCode.unavailable) {
        _pending = null;
      }
      state = AsyncData(
        CartState(
          items: previous.items,
          mutationError: failure,
          hasPendingMutation: _pending != null,
        ),
      );
      return false;
    } finally {
      _finishOperation(userId, operation);
    }
  }

  void _finishOperation(String userId, _CartOperation operation) {
    if (!identical(_operations[userId], operation)) return;
    _operations.remove(userId);
    if (!ref.mounted ||
        _userId != userId ||
        state.isLoading ||
        state.hasError) {
      return;
    }
    final current = state.asData?.value;
    if (current == null || !current.isMutating) return;
    // A same-user build can have published a fresh snapshot while the old
    // write was still running. Release only the busy flag, not that snapshot
    // or its uncertain absolute target; the customer can now retry explicitly.
    state = AsyncData(
      CartState(
        items: current.items,
        mutationError: current.mutationError,
        hasPendingMutation: _pending != null,
      ),
    );
  }

  bool _current(int epoch) => ref.mounted && epoch == _epoch;
}

class _SupersededCart implements Exception {
  const _SupersededCart();
}

class _CartOperation {
  _CartMutation? command;
}

class _CartMutation {
  _CartMutation(this.variantId, this.quantity) {
    if (!RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
          r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(variantId) ||
        (quantity != null &&
            (quantity! < 1 ||
                BigInt.from(quantity!) > BigInt.parse('9007199254740991')))) {
      throw const CartFailure(CartFailureCode.invalidData);
    }
  }
  final String variantId;
  final int? quantity;
}
