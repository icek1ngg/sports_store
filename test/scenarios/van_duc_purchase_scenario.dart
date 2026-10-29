import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/router/app_router.dart';
import 'package:sports_store/app/sports_store_app.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/checkout/data/repositories/pending_placement_store.dart';
import 'package:sports_store/features/checkout/presentation/view_models/checkout_providers.dart';

import '../features/catalog/catalog_repository_test.dart'
    show categoryId, productId, productRow, variantId, variantRow;
import '../features/support/operational_supabase_fixture.dart';

// Runs the actual router, pages, ViewModels and Supabase repositories against
// an explicitly isolated HTTP fixture. This does not claim cloud acceptance.
void runVanDucPurchaseScenario() {
  testWidgets('MH04 → MH05 → MH06 → MH16 tạo đúng một đơn COD', (tester) async {
    var quantity = 0;
    var placements = 0;
    Map<String, Object?>? receipt;
    final client = (await tester.runAsync(
      () => fixtureClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'customer'},
          ]);
        }
        if (path.endsWith('/categories')) {
          final offset =
              int.tryParse(request.url.queryParameters['offset'] ?? '0') ?? 0;
          return jsonResponse(
            request,
            offset == 0
                ? [
                    {
                      'id': categoryId,
                      'code': 'shoes',
                      'name': 'Giày',
                      'is_active': true,
                    },
                  ]
                : [],
          );
        }
        if (path.endsWith('/products')) {
          return jsonResponse(request, [productRow()]);
        }
        if (path.endsWith('/product_variants')) {
          return jsonResponse(
            request,
            request.url.queryParameters['id']?.startsWith('gt.') == true
                ? []
                : [variantRow()..['products'] = productRow()],
          );
        }
        if (path.endsWith('/cart_items')) {
          if (request.method == 'DELETE') {
            quantity = 0;
            return jsonResponse(request, null);
          }
          if (request.method == 'PATCH' && quantity == 0) {
            return jsonResponse(request, []);
          }
          if (request.method == 'POST' || request.method == 'PATCH') {
            quantity = (jsonDecode(request.body) as Map)['quantity'] as int;
          }
          final after = request.url.queryParameters['variant_id'];
          return jsonResponse(
            request,
            quantity > 0 && after?.startsWith('gt.') != true
                ? [
                    {
                      'customer_id': shipperA,
                      'variant_id': variantId,
                      'quantity': quantity,
                      'product_variants': variantRow()
                        ..['products'] = productRow(),
                    },
                  ]
                : [],
          );
        }
        if (path.endsWith('/rpc/place_order')) {
          placements++;
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['p_items'], [
            {'variant_id': variantId, 'quantity': 2},
          ]);
          expect(payload.containsKey('p_customer_id'), isFalse);
          expect(payload.containsKey('p_total_vnd'), isFalse);
          expect(payload['p_latitude'], closeTo(21.0285, .000001));
          const orderId = '60000000-0000-4000-8000-000000000001';
          const stamp = '2026-10-26T10:00:00Z';
          receipt = {
            'order': {
              'id': orderId,
              'customer_id': shipperA,
              'request_id': payload['p_request_id'],
              'status': 'pending_confirmation',
              'recipient_name': payload['p_recipient_name'],
              'recipient_phone': payload['p_recipient_phone'],
              'address_detail': payload['p_address_detail'],
              'latitude': payload['p_latitude'],
              'longitude': payload['p_longitude'],
              'subtotal_vnd': 1380000,
              'delivery_fee_vnd': 30000,
              'total_cod_vnd': 1410000,
              'delivery_attempt_count': 0,
              'placed_at': stamp,
              'confirmed_at': null,
              'source': null,
              'confirmed_by': null,
              'delivered_at': null,
              'cancel_reason': null,
              'created_at': stamp,
              'updated_at': stamp,
            },
            'items': [
              {
                'id': '70000000-0000-4000-8000-000000000001',
                'order_id': orderId,
                'product_id': productId,
                'variant_id': variantId,
                'product_name': 'Giày chạy bộ',
                'variant_label': 'Đen / 40',
                'attributes': {'size': '40'},
                'unit_price_vnd': 690000,
                'quantity': 2,
                'line_total_vnd': 1380000,
                'created_at': stamp,
              },
            ],
            'event_id': '80000000-0000-4000-8000-000000000001',
            'replayed': false,
          };
          return jsonResponse(request, {
            'ok': true,
            'data': receipt,
            'error': null,
          });
        }
        if (path.endsWith('/rpc/get_placement_result')) {
          return jsonResponse(request, {
            'ok': true,
            'error': null,
            'data': receipt == null
                ? {
                    'state': 'not_found',
                    'order': null,
                    'items': [],
                    'event_id': null,
                    'replayed': false,
                  }
                : {...receipt!, 'state': 'committed', 'replayed': true},
          });
        }
        throw StateError('Unexpected fixture endpoint: $path');
      }),
    ))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          pendingPlacementStoreProvider.overrideWithValue(
            InMemoryPendingPlacementStore(),
          ),
          checkoutMapTilesEnabledProvider.overrideWithValue(false),
        ],
        child: const SportsStoreApp(),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SportsStoreApp)),
    );
    final router = container.read(appRouterProvider);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    });

    router.go('/customer/products');
    final product = find.byKey(const ValueKey('catalog-product-$productId'));
    await _until(tester, () => product.evaluate().isNotEmpty);
    await _tap(tester, product);
    final add = find.byKey(const ValueKey('catalog-cart-action'));
    await _until(
      tester,
      () =>
          add.evaluate().isNotEmpty &&
          tester.widget<OutlinedButton>(add).onPressed != null,
    );
    await _tap(tester, add);
    await _until(tester, () => quantity == 1);
    await _tap(tester, find.byKey(const ValueKey('catalog-open-cart')));
    final increase = find.byKey(const ValueKey('cart-increase-$variantId'));
    await _until(tester, () => increase.evaluate().isNotEmpty);
    await _tap(tester, increase);
    await _until(tester, () => find.text('1.380.000 đ').evaluate().isNotEmpty);
    await _tap(tester, find.byKey(const ValueKey('cart-checkout')));
    await _until(
      tester,
      () => find.byKey(const ValueKey('checkout-name')).evaluate().isNotEmpty,
    );
    await _enter(tester, 'checkout-name', '[THỬ NGHIỆM] Văn Đức');
    await _enter(tester, 'checkout-phone', '0901234567');
    await _enter(
      tester,
      'checkout-address',
      'Số 1 phố Tràng Tiền, Hoàn Kiếm, Hà Nội',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _tap(tester, find.byKey(const ValueKey('checkout-location')));
    await _until(
      tester,
      () => find
          .byKey(const ValueKey('checkout-location-confirm'))
          .evaluate()
          .isNotEmpty,
    );
    await _tap(tester, find.byKey(const ValueKey('checkout-location-confirm')));
    final submit = find.byKey(const ValueKey('checkout-submit'));
    await _tap(tester, submit);
    await _until(
      tester,
      () =>
          find.byKey(const ValueKey('checkout-success')).evaluate().isNotEmpty,
    );
    expect(placements, 1);
    expect(find.textContaining('1.410.000'), findsWidgets);
    expect(receipt, isNotNull);
    expect(
      quantity,
      2,
      reason: 'Checkout không xóa thay đổi giỏ trên thiết bị khác.',
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 300; i++) {
    if (done()) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('Luồng mua hàng chưa đến trạng thái mong đợi.');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      220,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
}
