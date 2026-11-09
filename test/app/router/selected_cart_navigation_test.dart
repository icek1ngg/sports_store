import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sports_store/app/router/app_router.dart';
import 'package:sports_store/app/sports_store_app.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/cart/domain/models/cart_item.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_providers.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_state.dart';
import 'package:sports_store/features/catalog/domain/models/product.dart';
import 'package:sports_store/features/catalog/domain/models/product_variant.dart';

import '../../support/fixtures/in_memory_pending_placement_store.dart';

import 'package:sports_store/features/checkout/presentation/pages/checkout_page.dart';
import 'package:sports_store/features/checkout/presentation/view_models/checkout_providers.dart';

import '../../features/support/operational_supabase_fixture.dart';

const _variantA = '50000000-0000-4000-8000-000000000001';
const _variantB = '50000000-0000-4000-8000-000000000002';
const _productId = '40000000-0000-4000-8000-000000000001';

final _product = Product(
  id: _productId,
  categoryId: '30000000-0000-4000-8000-000000000001',
  categoryName: 'Giày',
  name: 'Giày thể thao',
  description: null,
  imagePath: null,
  variants: [
    for (final id in [_variantA, _variantB])
      ProductVariant(
        id: id,
        productId: _productId,
        sku: id,
        label: id == _variantA ? 'Đen / 40' : 'Trắng / 41',
        attributes: const {},
        priceVnd: 500000,
        availableQuantity: 10,
      ),
  ],
);

class _Cart extends CartViewModel {
  @override
  Future<CartState> build() async => CartState(
    items: [
      for (final variant in _product.variants)
        CartItem(
          variantId: variant.id,
          quantity: variant.id == _variantA ? 2 : 1,
          product: _product,
          variant: variant,
        ),
    ],
  );
}

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 250; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('Expected checkout route state: $finder');
}

Future<({GoRouter router, ProviderContainer root})> _open(
  WidgetTester tester,
  String location,
) async {
  final client = (await tester.runAsync(
    () => fixtureClient((request) async {
      if (request.url.path.endsWith('/profiles')) {
        return jsonResponse(request, [
          {
            'id': shipperA,
            'role': 'customer',
            'full_name': 'Khách hàng kiểm thử',
            'phone': null,
          },
        ]);
      }
      return jsonResponse(request, []);
    }),
  ))!;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        cartProvider.overrideWith(_Cart.new),
        pendingPlacementStoreProvider.overrideWithValue(
          InMemoryPendingPlacementStore(),
        ),
        checkoutMapTilesEnabledProvider.overrideWithValue(false),
      ],
      child: const SportsStoreApp(),
    ),
  );
  final root = ProviderScope.containerOf(
    tester.element(find.byType(SportsStoreApp)),
  );
  final router = root.read(appRouterProvider);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(client.dispose);
  });
  router.go(location);
  await _until(tester, find.byType(CheckoutPage));
  return (router: router, root: root);
}

ProviderContainer _checkoutScope(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(CheckoutPage)));

void main() {
  testWidgets(
    'repeated variant query IDs scope only this checkout and do not mutate global selection',
    (tester) async {
      final app = await _open(
        tester,
        '/customer/checkout?variant=$_variantA&variant=$_variantA&variant=$_variantB',
      );
      await _until(tester, find.byKey(const ValueKey('checkout-form')));
      final scope = _checkoutScope(tester);
      expect(scope.read(selectedCheckoutVariantIdsProvider), {
        _variantA,
        _variantB,
      });
      expect(
        scope.read(checkoutProvider).requireValue.items.map((i) => i.variantId),
        [_variantA, _variantB],
      );
      expect(app.root.read(selectedCheckoutVariantIdsProvider), isNull);
      expect(
        () => scope.read(selectedCheckoutVariantIdsProvider)!.add('another'),
        throwsUnsupportedError,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'checkout without variant parameter retains the existing all-cart behavior',
    (tester) async {
      final app = await _open(tester, '/customer/checkout');
      await _until(tester, find.byKey(const ValueKey('checkout-form')));
      final scope = _checkoutScope(tester);
      expect(scope, same(app.root));
      expect(scope.read(selectedCheckoutVariantIdsProvider), isNull);
      expect(scope.read(checkoutProvider).requireValue.items, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  for (final query in [
    'variant=',
    'variant=unknown',
    'variant=$_variantA&variant=unknown',
  ]) {
    testWidgets(
      'explicit stale selection $query cannot fall back to all items',
      (tester) async {
        await _open(tester, '/customer/checkout?$query');
        await _until(tester, find.byKey(const ValueKey('checkout-error')));
        expect(find.textContaining('quay lại giỏ hàng'), findsOneWidget);
        expect(find.byKey(const ValueKey('checkout-form')), findsNothing);
        expect(_checkoutScope(tester).read(checkoutProvider).hasError, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a later route selection gets a fresh scope rather than the previous selected snapshot',
    (tester) async {
      final app = await _open(tester, '/customer/checkout?variant=$_variantA');
      await _until(tester, find.byKey(const ValueKey('checkout-form')));
      expect(
        _checkoutScope(tester)
            .read(checkoutProvider)
            .requireValue
            .items
            .single
            .variantId,
        _variantA,
      );
      app.router.go('/customer/checkout?variant=$_variantB');
      await tester.pump();
      await _until(tester, find.byKey(const ValueKey('checkout-form')));
      expect(_checkoutScope(tester).read(selectedCheckoutVariantIdsProvider), {
        _variantB,
      });
      expect(
        _checkoutScope(tester)
            .read(checkoutProvider)
            .requireValue
            .items
            .single
            .variantId,
        _variantB,
      );
      expect(app.root.read(selectedCheckoutVariantIdsProvider), isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
