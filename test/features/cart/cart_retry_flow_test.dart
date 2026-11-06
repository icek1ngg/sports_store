import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/cart/domain/models/cart_failure.dart';
import 'package:sports_store/features/cart/domain/models/cart_item.dart';
import 'package:sports_store/features/cart/domain/repositories/cart_repository.dart';
import 'package:sports_store/features/cart/presentation/pages/cart_page.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_providers.dart';
import 'package:sports_store/features/catalog/domain/models/product.dart';
import 'package:sports_store/features/catalog/domain/models/product_variant.dart';
import 'package:sports_store/features/catalog/presentation/pages/product_details_page.dart';
import 'package:sports_store/features/catalog/presentation/view_models/catalog_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';

const _id = '50000000-0000-4000-8000-000000000001';
const _productId = '40000000-0000-4000-8000-000000000001';
const _variant = ProductVariant(
  id: _id,
  productId: _productId,
  sku: 'RUN-40',
  label: 'Đen / 40',
  attributes: {'size': '40'},
  priceVnd: 690000,
  availableQuantity: 20,
);
final _product = Product(
  id: _productId,
  categoryId: '30000000-0000-4000-8000-000000000001',
  categoryName: 'Giày',
  name: 'Giày chạy bộ',
  description: null,
  imagePath: null,
  variants: [_variant],
);

CartItem _availableItem(int quantity) => CartItem(
  variantId: _id,
  quantity: quantity,
  product: _product,
  variant: _variant,
);

class _LostResponseCart implements CartRepository {
  var items = <CartItem>[];
  var fail = true;
  var useAvailableItems = false;
  final targets = <int>[];
  Completer<void>? held;
  Completer<void>? started;

  @override
  Future<List<CartItem>> getItems() async => items;
  @override
  Future<void> setQuantity({
    required String variantId,
    required int quantity,
  }) async {
    targets.add(quantity);
    started?.complete();
    await held?.future;
    items = [
      useAvailableItems
          ? _availableItem(quantity)
          : CartItem(variantId: variantId, quantity: quantity),
    ];
    if (fail) {
      fail = false;
      throw const CartFailure(CartFailureCode.network);
    }
  }

  @override
  Future<void> removeItem(String variantId) async => items = [];
}

void main() {
  testWidgets(
    'same-user refresh keeps retry visible and blocks checkout and add',
    (tester) async {
      final sessions = StreamController<OperationalSession>();
      final repository = _LostResponseCart()
        ..useAvailableItems = true
        ..items = [_availableItem(2)];
      final container = ProviderContainer(
        overrides: [
          cartRepositoryProvider.overrideWithValue(repository),
          operationalSessionProvider.overrideWith((ref) => sessions.stream),
          productDetailsProvider(_productId)
              .overrideWith((ref) async => _product),
        ],
      );
      final listener = container.listen(cartProvider, (_, _) {});
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        listener.close();
        container.dispose();
        await sessions.close();
      });

      Future<void> showPage(Widget page) async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(key: ValueKey(page.runtimeType), home: page),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<Finder> showControl(String key) async {
        final finder = find.byKey(ValueKey(key));
        if (finder.evaluate().isEmpty) {
          final scrollable = find.byType(Scrollable).first;
          final state = tester.state<ScrollableState>(scrollable);
          state.position.jumpTo(state.position.minScrollExtent);
          await tester.pump();
          await tester.scrollUntilVisible(finder, 180, scrollable: scrollable);
        }
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        return finder;
      }

      sessions.add(
        const OperationalSession(userId: 'customer-A', generation: 1),
      );
      await showPage(const CartPage());
      final checkout = await showControl('cart-checkout');
      expect(tester.widget<FilledButton>(checkout).onPressed, isNotNull);
      final vm = container.read(cartProvider.notifier);
      expect(await vm.addItem(variantId: _id, quantity: 3), isFalse);
      expect(repository.items.single.quantity, 5);
      sessions.add(
        const OperationalSession(userId: 'customer-A', generation: 2),
      );
      await tester.pumpAndSettle();
      final retry = await showControl('cart-retry');
      expect(tester.widget<FilledButton>(retry).onPressed, isNotNull);
      await showControl('cart-checkout');
      expect(tester.widget<FilledButton>(checkout).onPressed, isNull);

      await showPage(const ProductDetailsPage(productId: _productId));
      final add = await showControl('catalog-cart-action');
      expect(tester.widget<OutlinedButton>(add).onPressed, isNull);
      expect(repository.targets, [5]);

      await showPage(const CartPage());
      final visibleRetry = await showControl('cart-retry');
      await tester.tap(visibleRetry);
      await tester.pumpAndSettle();
      expect(repository.targets, [5, 5]);
      expect(repository.items.single.quantity, 5);
      expect(
        container.read(cartProvider).requireValue.hasPendingMutation,
        isFalse,
      );
      await showControl('cart-checkout');
      expect(tester.widget<FilledButton>(checkout).onPressed, isNotNull);

      await showPage(const ProductDetailsPage(productId: _productId));
      await showControl('catalog-cart-action');
      expect(tester.widget<OutlinedButton>(add).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'real pending first-add retry stays visible and disabled until resolved',
    (tester) async {
      final repository = _LostResponseCart();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cartRepositoryProvider.overrideWithValue(repository),
            operationalSessionProvider.overrideWith(
              (ref) => Stream.value(
                const OperationalSession(userId: 'customer-A', generation: 1),
              ),
            ),
          ],
          child: const MaterialApp(home: CartPage()),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CartPage)),
      );
      final vm = container.read(cartProvider.notifier);
      expect(await vm.addItem(variantId: _id, quantity: 1), isFalse);
      await tester.pumpAndSettle();
      final retry = find.byKey(const ValueKey('cart-retry'));
      expect(retry, findsOneWidget);
      repository.held = Completer<void>();
      repository.started = Completer<void>();
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await repository.started!.future;
      await tester.pump();
      expect(
        container.read(cartProvider).requireValue.hasPendingMutation,
        isTrue,
      );
      expect(container.read(cartProvider).requireValue.isMutating, isTrue);
      expect(retry, findsOneWidget);
      expect(tester.widget<FilledButton>(retry).onPressed, isNull);
      repository.held!.complete();
      await tester.pumpAndSettle();
      expect(
        container.read(cartProvider).requireValue.hasPendingMutation,
        isFalse,
      );
      expect(
        container.read(cartProvider).requireValue.items.single.quantity,
        1,
      );
    },
  );
}
