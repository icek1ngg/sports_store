import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/router/app_router.dart';
import 'package:sports_store/app/sports_store_app.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';

import '../catalog/catalog_repository_test.dart'
    show productId, productRow, variantId, variantRow;
import '../support/operational_supabase_fixture.dart';

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 250; i++) {
    if (done()) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('Catalog/cart flow did not reach expected state');
}

void main() {
  testWidgets(
    'MH05 add -> MH06 edit/delete persists through real repository transport',
    (tester) async {
      var quantity = 0;
      final writes = <String>[];
      final client = (await tester.runAsync(
        () => fixtureClient((request) async {
          final path = request.url.path;
          if (request.method != 'GET') writes.add(path);
          if (path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'role': 'customer'},
            ]);
          }
          if (path.endsWith('/products')) {
            return jsonResponse(request, [productRow()]);
          }
          if (path.endsWith('/product_variants')) {
            final cursor = request.url.queryParameters['id'];
            return jsonResponse(
              request,
              cursor?.startsWith('gt.') == true
                  ? []
                  : [variantRow()..['products'] = productRow()],
            );
          }
          if (path.endsWith('/cart_items')) {
            if (request.method == 'DELETE') {
              quantity = 0;
              return jsonResponse(request, null);
            }
            if (request.method == 'POST' ||
                (request.method == 'PATCH' && quantity > 0)) {
              quantity =
                  (jsonDecode(request.body) as Map<String, dynamic>)['quantity']
                      as int;
            } else if (request.method == 'PATCH') {
              return jsonResponse(request, []);
            }
            final row = {
              'customer_id': shipperA,
              'variant_id': variantId,
              'quantity': quantity,
              'product_variants': variantRow()..['products'] = productRow(),
            };
            final after = request.url.queryParameters['variant_id'];
            return jsonResponse(
              request,
              quantity > 0 && after?.startsWith('gt.') != true ? [row] : [],
            );
          }
          return jsonResponse(request, []);
        }),
      ))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [supabaseClientProvider.overrideWithValue(client)],
          child: const SportsStoreApp(),
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(client.dispose);
      });
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SportsStoreApp)),
      );
      container.read(appRouterProvider).go('/customer/products/$productId');
      final add = find.byKey(const ValueKey('catalog-cart-action'));
      await _until(
        tester,
        () =>
            add.evaluate().isNotEmpty &&
            tester.widget<OutlinedButton>(add).onPressed != null,
      );
      await tester.ensureVisible(add);
      await tester.tap(add);
      await _until(
        tester,
        () => find.text('Đã thêm vào giỏ hàng.').evaluate().isNotEmpty,
      );
      expect(quantity, 1);
      await tester.tap(find.byKey(const ValueKey('catalog-open-cart')));
      await _until(
        tester,
        () => find
            .byKey(const ValueKey('cart-item-$variantId'))
            .evaluate()
            .isNotEmpty,
      );
      expect(find.text('690.000 đ'), findsWidgets);
      final increase = find.byKey(const ValueKey('cart-increase-$variantId'));
      await tester.ensureVisible(increase);
      await tester.tap(increase);
      await _until(
        tester,
        () => find.text('1.380.000 đ').evaluate().isNotEmpty,
      );
      expect(quantity, 2);
      await tester.tap(find.byKey(const ValueKey('cart-refresh')));
      await tester.pumpAndSettle();
      await _until(
        tester,
        () => find.text('1.380.000 đ').evaluate().isNotEmpty,
      );
      final remove = find.byKey(const ValueKey('cart-remove-$variantId'));
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await _until(
        tester,
        () => find.byKey(const ValueKey('cart-empty')).evaluate().isNotEmpty,
      );
      expect(quantity, 0);
      expect(writes, isNotEmpty);
      expect(writes.every((path) => path.endsWith('/cart_items')), isTrue);
    },
  );
}
