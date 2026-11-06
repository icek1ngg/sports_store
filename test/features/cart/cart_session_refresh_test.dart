import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/cart/domain/models/cart_failure.dart';
import 'package:sports_store/features/cart/domain/models/cart_item.dart';
import 'package:sports_store/features/cart/domain/repositories/cart_repository.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_providers.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_state.dart';
import 'package:sports_store/features/catalog/domain/models/product.dart';
import 'package:sports_store/features/catalog/domain/models/product_variant.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';

const _customerA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _customerB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _variantId = '50000000-0000-4000-8000-000000000001';
const _productId = '40000000-0000-4000-8000-000000000001';
const _variant = ProductVariant(
  id: _variantId,
  productId: _productId,
  sku: 'RUN-40',
  label: 'Đen / 40',
  attributes: {'size': '40'},
  priceVnd: 690000,
  availableQuantity: 20,
);

CartItem _item(String userId, int quantity) => CartItem(
  variantId: _variantId,
  quantity: quantity,
  variant: _variant,
  product: Product(
    id: _productId,
    categoryId: '30000000-0000-4000-8000-000000000001',
    categoryName: 'Giày',
    name: 'Giỏ riêng của $userId',
    description: null,
    imagePath: null,
    variants: [_variant],
  ),
);

class _Write {
  const _Write(this.userId, this.variantId, this.quantity);
  final String userId;
  final String variantId;
  final int? quantity;
}

class _WritePlan {
  _WritePlan({this.loseResponse = false, this.gate, this.failureAfterCommit});
  final bool loseResponse;
  final Completer<void>? gate;
  final CartFailure? failureAfterCommit;
  final started = Completer<void>();
}

/// Each repository instance is bound to a user, as a real request captures its
/// authenticated account before awaiting the transport. A late A write can
/// update only A's server cart, never B's data or the current UI account.
class _Backend {
  final items = <String, List<CartItem>>{
    _customerA: [_item(_customerA, 2)],
    _customerB: [_item(_customerB, 1)],
  };
  final writes = <_Write>[];
  _WritePlan? nextWrite;
  CartFailure? nextReadFailure;
  int activeWrites = 0;
  int maximumActiveWrites = 0;

  Future<List<CartItem>> read(String userId) async {
    final failure = nextReadFailure;
    nextReadFailure = null;
    if (failure != null) throw failure;
    return List.of(items[userId] ?? const []);
  }

  Future<void> write(String userId, String variantId, int? quantity) async {
    final plan = nextWrite;
    nextWrite = null;
    writes.add(_Write(userId, variantId, quantity));
    activeWrites++;
    if (activeWrites > maximumActiveWrites) {
      maximumActiveWrites = activeWrites;
    }
    plan?.started.complete();
    try {
      await plan?.gate?.future;
      items[userId] = quantity == null ? [] : [_item(userId, quantity)];
      final failure = plan?.failureAfterCommit;
      if (failure != null) throw failure;
      if (plan?.loseResponse == true) {
        throw const CartFailure(CartFailureCode.network);
      }
    } finally {
      activeWrites--;
    }
  }
}

class _BoundCart implements CartRepository {
  const _BoundCart(this.backend, this.userId);
  final _Backend backend;
  final String? userId;

  String get _owner {
    final owner = userId;
    if (owner == null) {
      throw const CartFailure(CartFailureCode.sessionExpired);
    }
    return owner;
  }

  @override
  Future<List<CartItem>> getItems() => backend.read(_owner);

  @override
  Future<void> setQuantity({
    required String variantId,
    required int quantity,
  }) => backend.write(_owner, variantId, quantity);

  @override
  Future<void> removeItem(String variantId) =>
      backend.write(_owner, variantId, null);
}

class _Harness {
  _Harness() {
    container = ProviderContainer(
      overrides: [
        operationalSessionProvider.overrideWith((ref) => sessions.stream),
        cartRepositoryProvider.overrideWith((ref) {
          final owner = ref.watch(
            operationalSessionProvider.select(
              (state) => state.asData?.value.userId,
            ),
          );
          return _BoundCart(backend, owner);
        }),
      ],
    );
    subscription = container.listen(cartProvider, (_, _) {});
  }

  final sessions = StreamController<OperationalSession>();
  final backend = _Backend();
  late final ProviderContainer container;
  late final ProviderSubscription<AsyncValue<CartState>> subscription;
  int _generation = 0;

  CartViewModel get vm => container.read(cartProvider.notifier);
  CartState get state => container.read(cartProvider).requireValue;

  Future<CartState> emit(String? userId) async {
    sessions.add(OperationalSession(userId: userId, generation: ++_generation));
    await Future<void>.delayed(Duration.zero);
    return container.read(cartProvider.future);
  }

  Future<void> dispose() async {
    subscription.close();
    container.dispose();
    await sessions.close();
  }
}

Future<_Harness> _harness() async {
  final harness = _Harness();
  addTearDown(harness.dispose);
  await harness.emit(_customerA);
  expect(harness.state.canCheckout, isTrue);
  return harness;
}

void main() {
  test(
    'repeated same-user refresh keeps the absolute target after lost response',
    () async {
      final harness = await _harness();
      harness.backend.nextWrite = _WritePlan(loseResponse: true);
      expect(
        await harness.vm.addItem(variantId: _variantId, quantity: 3),
        isFalse,
      );
      expect(harness.backend.items[_customerA]!.single.quantity, 5);

      for (var refresh = 0; refresh < 3; refresh++) {
        await harness.emit(_customerA);
        expect(harness.state.items.single.quantity, 5);
        expect(harness.state.hasPendingMutation, isTrue);
        expect(harness.state.canCheckout, isFalse);
        expect(
          await harness.vm.addItem(variantId: _variantId, quantity: 3),
          isFalse,
        );
        expect(
          await harness.vm.setQuantity(variantId: _variantId, quantity: 9),
          isFalse,
        );
        expect(await harness.vm.removeItem(_variantId), isFalse);
        expect(harness.backend.writes, hasLength(1));
      }

      expect(await harness.vm.retryPendingMutation(), isTrue);
      expect(harness.backend.writes.map((write) => write.quantity), [5, 5]);
      expect(harness.backend.items[_customerA]!.single.quantity, 5);
      expect(harness.state.hasPendingMutation, isFalse);
      expect(harness.state.canCheckout, isTrue);
    },
  );

  test('uncertain removal survives same-user refresh and retries the same deletion', () async {
    final harness = await _harness();
    harness.backend.nextWrite = _WritePlan(loseResponse: true);
    expect(await harness.vm.removeItem(_variantId), isFalse);
    expect(harness.backend.items[_customerA], isEmpty);
    await harness.emit(_customerA);
    expect(harness.state.items, isEmpty);
    expect(harness.state.hasPendingMutation, isTrue);
    expect(harness.state.canCheckout, isFalse);
    expect(
      await harness.vm.addItem(variantId: _variantId, quantity: 1),
      isFalse,
    );

    expect(await harness.vm.retryPendingMutation(), isTrue);
    expect(harness.backend.writes.map((write) => write.quantity), [null, null]);
    expect(harness.state.items, isEmpty);
    expect(harness.state.hasPendingMutation, isFalse);
  });

  test('refresh during a write blocks parallel actions and ignores its old snapshot', () async {
    final harness = await _harness();
    final gate = Completer<void>();
    final plan = _WritePlan(loseResponse: true, gate: gate);
    harness.backend.nextWrite = plan;
    final pending = harness.vm.addItem(variantId: _variantId, quantity: 3);
    await plan.started.future;
    // Another device changes the current read snapshot while our write waits.
    harness.backend.items[_customerA] = [_item(_customerA, 4)];
    await harness.emit(_customerA);
    expect(harness.state.items.single.quantity, 4);
    expect(harness.state.hasPendingMutation, isTrue);
    expect(harness.state.isMutating, isTrue);
    expect(harness.state.canCheckout, isFalse);
    expect(await harness.vm.retryPendingMutation(), isFalse);
    expect(
      await harness.vm.addItem(variantId: _variantId, quantity: 3),
      isFalse,
    );
    expect(await harness.vm.removeItem(_variantId), isFalse);
    expect(harness.backend.writes, hasLength(1));

    gate.complete();
    expect(await pending, isFalse);
    expect(harness.state.items.single.quantity, 4);
    expect(harness.state.hasPendingMutation, isTrue);
    expect(harness.state.isMutating, isFalse);
    expect(harness.state.canCheckout, isFalse);
    expect(await harness.vm.retryPendingMutation(), isTrue);
    expect(harness.backend.writes.map((write) => write.quantity), [5, 5]);
    expect(harness.backend.maximumActiveWrites, 1);
    expect(harness.state.items.single.quantity, 5);
    expect(harness.state.hasPendingMutation, isFalse);
  });

  test('a failed cart read after session refresh retains a safely retryable command', () async {
    final harness = await _harness();
    harness.backend.nextWrite = _WritePlan(loseResponse: true);
    expect(
      await harness.vm.addItem(variantId: _variantId, quantity: 3),
      isFalse,
    );
    harness.backend.nextReadFailure = const CartFailure(
      CartFailureCode.network,
    );
    await harness.emit(_customerA);
    expect(harness.state.hasPendingMutation, isTrue);
    expect(harness.state.canCheckout, isFalse);
    expect(harness.state.mutationError?.code, CartFailureCode.network);
    expect(
      await harness.vm.addItem(variantId: _variantId, quantity: 3),
      isFalse,
    );

    expect(await harness.vm.retryPendingMutation(), isTrue);
    expect(harness.backend.writes.map((write) => write.quantity), [5, 5]);
    expect(harness.state.items.single.quantity, 5);
    expect(harness.state.hasPendingMutation, isFalse);
  });

  for (final failureCode in [
    CartFailureCode.sessionExpired,
    CartFailureCode.permissionDenied,
  ]) {
    test(
      '${failureCode.name} after a committed write preserves its retry target',
      () async {
        final harness = await _harness();
        harness.backend.nextWrite = _WritePlan(
          failureAfterCommit: CartFailure(failureCode),
        );
        expect(
          await harness.vm.addItem(variantId: _variantId, quantity: 3),
          isFalse,
        );
        expect(harness.backend.items[_customerA]!.single.quantity, 5);
        expect(harness.state.hasPendingMutation, isTrue);
        expect(harness.state.canCheckout, isFalse);

        await harness.emit(_customerA);
        expect(harness.state.hasPendingMutation, isTrue);
        expect(
          await harness.vm.addItem(variantId: _variantId, quantity: 3),
          isFalse,
        );
        expect(await harness.vm.retryPendingMutation(), isTrue);
        expect(harness.backend.writes.map((write) => write.quantity), [5, 5]);
        expect(harness.state.items.single.quantity, 5);
        expect(harness.state.hasPendingMutation, isFalse);
      },
    );
  }

  test('returning to A through B keeps A write locked until its old request settles', () async {
    final harness = await _harness();
    final gate = Completer<void>();
    final plan = _WritePlan(loseResponse: true, gate: gate);
    harness.backend.nextWrite = plan;
    final pending = harness.vm.addItem(variantId: _variantId, quantity: 3);
    await plan.started.future;
    await harness.emit(_customerB);
    expect(harness.state.items.single.quantity, 1);
    expect(harness.state.isMutating, isFalse);
    expect(
      await harness.vm.addItem(variantId: _variantId, quantity: 1),
      isTrue,
    );
    expect(harness.backend.writes.last.userId, _customerB);

    await harness.emit(_customerA);
    expect(harness.state.items.single.quantity, 2);
    expect(harness.state.isMutating, isTrue);
    expect(harness.state.hasPendingMutation, isTrue);
    expect(harness.state.canCheckout, isFalse);
    expect(
      await harness.vm.addItem(variantId: _variantId, quantity: 3),
      isFalse,
    );
    expect(
      await harness.vm.setQuantity(variantId: _variantId, quantity: 8),
      isFalse,
    );
    expect(await harness.vm.removeItem(_variantId), isFalse);
    expect(await harness.vm.retryPendingMutation(), isFalse);
    expect(
      harness.backend.writes.where((write) => write.userId == _customerA),
      hasLength(1),
    );

    gate.complete();
    expect(await pending, isFalse);
    expect(harness.state.items.single.quantity, 2);
    expect(harness.state.isMutating, isFalse);
    expect(harness.state.hasPendingMutation, isTrue);
    expect(harness.state.canCheckout, isFalse);
    expect(await harness.vm.retryPendingMutation(), isTrue);
    expect(
      harness.backend.writes
          .where((write) => write.userId == _customerA)
          .map((write) => write.quantity),
      [5, 5],
    );
    expect(harness.state.items.single.quantity, 5);
    expect(harness.state.canCheckout, isTrue);
    expect(harness.backend.items[_customerB]!.single.quantity, 2);
  });

  for (final accountChange in ['switch', 'logout']) {
    test(
      '$accountChange clears the uncertain command before another user reads',
      () async {
        final harness = await _harness();
        harness.backend.nextWrite = _WritePlan(loseResponse: true);
        expect(
          await harness.vm.addItem(variantId: _variantId, quantity: 3),
          isFalse,
        );
        if (accountChange == 'logout') {
          await expectLater(harness.emit(null), throwsA(isA<CartFailure>()));
          expect(harness.container.read(cartProvider).asData, isNull);
        }
        await harness.emit(_customerB);
        expect(harness.state.hasPendingMutation, isFalse);
        expect(
          harness.state.items.single.product!.name,
          'Giỏ riêng của $_customerB',
        );
        expect(harness.state.items.single.quantity, 1);
        expect(await harness.vm.retryPendingMutation(), isFalse);
        expect(harness.backend.writes, hasLength(1));
        expect(
          await harness.vm.addItem(variantId: _variantId, quantity: 1),
          isTrue,
        );
        expect(harness.backend.writes.last.userId, _customerB);
        expect(harness.backend.writes.last.quantity, 2);
        expect(harness.backend.items[_customerA]!.single.quantity, 5);
      },
    );

    test(
      '$accountChange ignores a previous user write completing after the new cart',
      () async {
        final harness = await _harness();
        final gate = Completer<void>();
        final plan = _WritePlan(loseResponse: true, gate: gate);
        harness.backend.nextWrite = plan;
        final pending = harness.vm.addItem(variantId: _variantId, quantity: 3);
        await plan.started.future;
        if (accountChange == 'logout') {
          await expectLater(harness.emit(null), throwsA(isA<CartFailure>()));
          expect(harness.container.read(cartProvider).asData, isNull);
        }
        await harness.emit(_customerB);
        expect(harness.state.hasPendingMutation, isFalse);
        expect(harness.state.isMutating, isFalse);
        expect(
          harness.state.items.single.product!.name,
          'Giỏ riêng của $_customerB',
        );
        gate.complete();
        expect(await pending, isFalse);
        expect(harness.state.items.single.quantity, 1);
        expect(
          harness.state.items.single.product!.name,
          'Giỏ riêng của $_customerB',
        );
        expect(harness.state.hasPendingMutation, isFalse);
        expect(await harness.vm.retryPendingMutation(), isFalse);
        expect(harness.backend.writes, hasLength(1));
        expect(harness.backend.writes.single.userId, _customerA);
        expect(harness.backend.items[_customerA]!.single.quantity, 5);
        expect(harness.backend.items[_customerB]!.single.quantity, 1);
      },
    );
  }
}
