import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sports_store/features/cart/domain/models/cart_item.dart';
import 'package:sports_store/features/cart/presentation/pages/cart_page.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_providers.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_selection_view_model.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_state.dart';
import 'package:sports_store/features/catalog/domain/models/product.dart';
import 'package:sports_store/features/catalog/domain/models/product_variant.dart';

const firstId = '50000000-0000-4000-8000-000000000001';
const secondId = '50000000-0000-4000-8000-000000000002';
CartItem item(String id, {bool available = true}) {
  final variant = ProductVariant(
    id: id,
    productId: 'product',
    sku: id,
    label: 'Đen / M',
    attributes: const {'color': 'Đen', 'size': 'M'},
    priceVnd: 100000,
    availableQuantity: 4,
  );
  return CartItem(
    variantId: id,
    quantity: 1,
    variant: available ? variant : null,
    product: available
        ? Product(
            id: 'product',
            categoryId: 'apparel',
            categoryName: 'Quần áo',
            name: 'Áo thể thao',
            description: '',
            imagePath: null,
            variants: [variant],
          )
        : null,
  );
}

class _Cart extends CartViewModel {
  _Cart(this.initial);
  final CartState initial;
  @override
  Future<CartState> build() async => initial;
  void publish(CartState next) => state = AsyncData(next);
  void loading() => state = const AsyncLoading();
  CartState get snapshot => state.requireValue;
}

void main() {
  test(
    'selection persists refresh, prunes removed rows and resets by owner',
    () async {
      final cart = _Cart(
        CartState(userId: 'a', items: [item(firstId), item(secondId)]),
      );
      final container = ProviderContainer(
        overrides: [cartProvider.overrideWith(() => cart)],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(cartSelectionProvider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(cartProvider.future);
      var selected = container.read(cartSelectionProvider.notifier);
      selected.setSelected(secondId, false);
      expect(
        container
            .read(cartSelectionProvider)
            .selectedItems(cart.initial.items)
            .map((i) => i.variantId),
        [firstId],
      );
      cart.loading();
      expect(
        container.read(cartSelectionProvider).isSelected(secondId),
        isFalse,
      );
      cart.publish(cart.initial);
      expect(
        container.read(cartSelectionProvider).isSelected(secondId),
        isFalse,
      );
      cart.publish(CartState(userId: 'a', items: [item(firstId)]));
      expect(container.read(cartSelectionProvider).excludedVariantIds, isEmpty);
      cart.publish(CartState(userId: 'a', items: cart.initial.items));
      selected = container.read(cartSelectionProvider.notifier);
      selected.setSelected(secondId, false);
      expect(
        container.read(cartSelectionProvider).isSelected(secondId),
        isFalse,
      );
      cart.publish(CartState(userId: 'b', items: cart.initial.items));
      expect(container.read(cartSelectionProvider).excludedVariantIds, isEmpty);
    },
  );

  test(
    'pending mutation locks selection; select all can explicitly select none',
    () async {
      final initial = CartState(
        userId: 'a',
        items: [item(firstId), item(secondId)],
      );
      final cart = _Cart(initial);
      final container = ProviderContainer(
        overrides: [cartProvider.overrideWith(() => cart)],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(cartSelectionProvider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(cartProvider.future);
      final notifier = container.read(cartSelectionProvider.notifier);
      notifier.setAllSelected(false);
      expect(
        container.read(cartSelectionProvider).selectedItems(initial.items),
        isEmpty,
      );
      cart.publish(
        CartState(userId: 'a', items: initial.items, hasPendingMutation: true),
      );
      notifier.setAllSelected(true);
      notifier.setSelected(firstId, true);
      expect(
        container.read(cartSelectionProvider).selectedItems(initial.items),
        isEmpty,
      );
      cart.publish(initial);
      notifier.setAllSelected(true);
      expect(
        container.read(cartSelectionProvider).selectedItems(initial.items),
        hasLength(2),
      );
    },
  );

  testWidgets(
    'excluded unavailable row enables checkout and only selected UUID is passed',
    (tester) async {
      final cart = _Cart(
        CartState(
          userId: 'a',
          items: [item(firstId), item(secondId, available: false)],
        ),
      );
      List<String>? ids;
      final router = GoRouter(
        initialLocation: '/customer/cart',
        routes: [
          GoRoute(
            path: '/customer/cart',
            builder: (context, state) => const CartPage(),
          ),
          GoRoute(
            path: '/customer/checkout',
            builder: (context, state) {
              ids = state.uri.queryParametersAll['variant'];
              return const Scaffold(body: Text('CHECKOUT'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [cartProvider.overrideWith(() => cart)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      final action = find.byKey(const ValueKey('cart-checkout'));
      expect(tester.widget<FilledButton>(action).onPressed, isNull);
      final checkbox = find.byKey(const ValueKey('cart-select-$secondId'));
      await tester.ensureVisible(checkbox);
      await tester.pumpAndSettle();
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(find.text('100.000 đ'), findsWidgets);
      expect(tester.widget<FilledButton>(action).onPressed, isNotNull);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(ids, [firstId]);
      expect(cart.snapshot.items, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );
}
