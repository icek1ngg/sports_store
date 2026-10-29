import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/cart/domain/models/cart_failure.dart';
import 'package:sports_store/features/cart/domain/models/cart_item.dart';
import 'package:sports_store/features/cart/domain/repositories/cart_repository.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';

const _variantId = '50000000-0000-4000-8000-000000000001';

class _Cart implements CartRepository {
  List<CartItem> items = [const CartItem(variantId: _variantId, quantity: 2)];
  final targets = <int>[];
  CartFailure? nextFailure;
  Completer<void>? hold;
  Completer<void>? started;

  @override
  Future<List<CartItem>> getItems() async => List.of(items);

  @override
  Future<void> setQuantity({
    required String variantId,
    required int quantity,
  }) async {
    targets.add(quantity);
    started?.complete();
    await hold?.future;
    final failure = nextFailure;
    nextFailure = null;
    // Simulates committed write + lost response for network uncertainty.
    if (failure?.code != CartFailureCode.insufficientStock) {
      items = [CartItem(variantId: variantId, quantity: quantity)];
    }
    if (failure != null) throw failure;
  }

  @override
  Future<void> removeItem(String variantId) async => items = [];
}

ProviderContainer _container(
  _Cart repository, {
  Stream<OperationalSession>? sessions,
}) {
  final container = ProviderContainer(
    overrides: [
      cartRepositoryProvider.overrideWithValue(repository),
      operationalSessionProvider.overrideWith(
        (ref) =>
            sessions ??
            Stream.value(
              const OperationalSession(userId: 'customer-A', generation: 1),
            ),
      ),
    ],
  );
  container.listen(cartProvider, (_, _) {});
  addTearDown(container.dispose);
  return container;
}

void main() {
  test(
    'malformed input never becomes pending or locks later valid actions',
    () async {
      final repository = _Cart();
      final container = _container(repository);
      await container.read(cartProvider.future);
      final vm = container.read(cartProvider.notifier);
      expect(await vm.setQuantity(variantId: 'invalid', quantity: 1), isFalse);
      expect(
        container.read(cartProvider).requireValue.hasPendingMutation,
        isFalse,
      );
      expect(repository.targets, isEmpty);
      expect(await vm.removeItem(_variantId), isTrue);
    },
  );

  test(
    'add merges current quantity; retry keeps target after a committed timeout',
    () async {
      final repository = _Cart();
      final container = _container(repository);
      await container.read(cartProvider.future);
      final vm = container.read(cartProvider.notifier);
      repository.nextFailure = const CartFailure(CartFailureCode.network);
      expect(await vm.addItem(variantId: _variantId, quantity: 3), isFalse);
      expect(
        container.read(cartProvider).requireValue.hasPendingMutation,
        isTrue,
      );
      expect(await vm.addItem(variantId: _variantId, quantity: 3), isFalse);
      await vm.refresh();
      expect(
        container.read(cartProvider).requireValue.items.single.quantity,
        5,
      );
      expect(
        container.read(cartProvider).requireValue.hasPendingMutation,
        isTrue,
      );
      expect(await vm.retryPendingMutation(), isTrue);
      expect(repository.targets, [5, 5]);
      expect(
        container.read(cartProvider).requireValue.items.single.quantity,
        5,
      );
    },
  );

  test('definite stock rejection leaves cart editable for removal', () async {
    final repository = _Cart();
    final container = _container(repository);
    await container.read(cartProvider.future);
    final vm = container.read(cartProvider.notifier);
    repository.nextFailure = const CartFailure(
      CartFailureCode.insufficientStock,
    );
    expect(await vm.setQuantity(variantId: _variantId, quantity: 99), isFalse);
    expect(
      container.read(cartProvider).requireValue.hasPendingMutation,
      isFalse,
    );
    expect(await vm.removeItem(_variantId), isTrue);
    expect(container.read(cartProvider).requireValue.items, isEmpty);
  });

  test('repeated tap while write in flight is ignored', () async {
    final repository = _Cart()
      ..hold = Completer<void>()
      ..started = Completer<void>();
    final container = _container(repository);
    await container.read(cartProvider.future);
    final vm = container.read(cartProvider.notifier);
    final pending = vm.addItem(variantId: _variantId, quantity: 1);
    await repository.started!.future;
    expect(await vm.addItem(variantId: _variantId, quantity: 1), isFalse);
    repository.hold!.complete();
    expect(await pending, isTrue);
    expect(repository.targets, [3]);
  });

  test(
    'account switch clears state and ignores a previous mutation result',
    () async {
      final sessions = StreamController<OperationalSession>();
      addTearDown(sessions.close);
      final repository = _Cart()
        ..hold = Completer<void>()
        ..started = Completer<void>();
      final container = _container(repository, sessions: sessions.stream);
      sessions.add(
        const OperationalSession(userId: 'customer-A', generation: 1),
      );
      await container.read(cartProvider.future);
      final pending = container
          .read(cartProvider.notifier)
          .setQuantity(variantId: _variantId, quantity: 3);
      await repository.started!.future;
      repository.items = [];
      sessions.add(
        const OperationalSession(userId: 'customer-B', generation: 2),
      );
      await Future<void>.delayed(Duration.zero);
      await container.read(cartProvider.future);
      expect(container.read(cartProvider).requireValue.items, isEmpty);
      repository.hold!.complete();
      expect(await pending, isFalse);
      expect(container.read(cartProvider).requireValue.items, isEmpty);
      expect(
        container.read(cartProvider).requireValue.hasPendingMutation,
        isFalse,
      );
    },
  );
}
