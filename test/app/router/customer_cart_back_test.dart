import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sports_store/app/integration/production_feature_composition.dart';
import 'package:sports_store/app/router/app_router.dart';
import 'package:sports_store/app/sports_store_app.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_providers.dart';

import '../../features/catalog/catalog_repository_test.dart'
    show productId, productRow, variantId, variantRow;
import '../../features/support/operational_supabase_fixture.dart';

// These tests exercise the real Auth bridge, router and repositories using
// isolated HTTP responses. No cloud account, cart or stock is changed.
class _StoreUnderTest {
  const _StoreUnderTest(this.container);
  final ProviderContainer container;
  // Auth/account changes retire the previous router along with its branch
  // navigators. Read the current provider instead of retaining that instance.
  GoRouter get router => container.read(appRouterProvider);
}

Future<_StoreUnderTest> _openStore(
  WidgetTester tester, {
  bool invalidWriteReceipt = false,
  bool failFirstCartRead = false,
}) async {
  var quantity = 1;
  final client = (await tester.runAsync(
    () => fixtureClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/logout')) return jsonResponse(request, null);
      if (path.endsWith('/profiles')) {
        return jsonResponse(request, [
          {
            'id': shipperA,
            'role': 'customer',
            'full_name': '[TEST] Khách hàng',
            'phone': null,
          },
        ]);
      }
      if (path.endsWith('/categories')) {
        return jsonResponse(
          request,
          (request.url.queryParameters['offset'] ?? '0') == '0'
              ? [productRow()['categories']]
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
        if (request.method == 'GET' && failFirstCartRead) {
          failFirstCartRead = false;
          return jsonResponse(request, [
            {'customer_id': shipperA, 'variant_id': variantId, 'quantity': 0},
          ]);
        }
        if (request.method == 'PATCH') {
          quantity = (jsonDecode(request.body) as Map)['quantity'] as int;
          return jsonResponse(request, [
            {
              'customer_id': shipperA,
              'variant_id': variantId,
              'quantity': invalidWriteReceipt ? quantity + 1 : quantity,
            },
          ]);
        }
        return jsonResponse(
          request,
          request.url.queryParameters['variant_id']?.startsWith('gt.') == true
              ? []
              : [
                  {
                    'customer_id': shipperA,
                    'variant_id': variantId,
                    'quantity': quantity,
                    'product_variants': variantRow()
                      ..['products'] = productRow(),
                  },
                ],
        );
      }
      throw StateError('Unexpected fixture endpoint: $path');
    }),
  ))!;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...productionFeatureOverrides,
        supabaseClientProvider.overrideWithValue(client),
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
  // Customer now lands on Home; choose the catalog explicitly before testing
  // the catalog/cart stack. Both remain under the canonical customer shell.
  router.go('/customer/products');
  await _until(tester, 'catalog-product-$productId');
  return _StoreUnderTest(container);
}

Future<void> _until(WidgetTester tester, String key) async {
  for (var i = 0; i < 350; i++) {
    if (find.byKey(ValueKey(key)).evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 20));
  }
  final texts = tester.allWidgets.whereType<Text>().map((text) => text.data);
  fail('Không mở được $key; giao diện: ${texts.take(25).toList()}');
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('customer can sign out through the shared account menu', (
    tester,
  ) async {
    final app = await _openStore(tester);
    await tester.tap(find.widgetWithText(NavigationDestination, 'Tài khoản'));
    await _until(tester, 'account-logout');
    await tester.tap(find.byKey(const ValueKey('account-logout')));
    await tester.pumpAndSettle();
    expect(
      app.container.read(supabaseClientProvider).auth.currentSession,
      isNull,
    );
    expect(find.text('Đăng nhập'), findsWidgets);
    expect(find.byKey(const ValueKey('catalog-product-list')), findsNothing);
  });

  testWidgets('direct cart entry has a back button that opens the catalog', (
    tester,
  ) async {
    final app = await _openStore(tester);
    app.router.go('/customer/cart');
    await _until(tester, 'cart-checkout');
    expect(app.router.canPop(), isFalse);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await _until(tester, 'catalog-product-$productId');
    expect(app.router.state.uri.path, '/customer/products');
  });

  testWidgets('details back stays on catalog while initial cart load failed', (
    tester,
  ) async {
    final app = await _openStore(tester, failFirstCartRead: true);
    await _tap(tester, 'catalog-product-$productId');
    expect(find.text('Tải lại giỏ hàng'), findsOneWidget);
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    await _until(tester, 'catalog-product-$productId');
    expect(app.router.state.uri.path, '/customer/products');
    expect(find.byKey(const ValueKey('catalog-product-details')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('details can retry a failed cart read and return to catalog', (
    tester,
  ) async {
    final app = await _openStore(tester, failFirstCartRead: true);
    await _tap(tester, 'catalog-product-$productId');
    expect(find.text('Dữ liệu giỏ hàng không hợp lệ.'), findsOneWidget);
    final retry = find.text('Tải lại giỏ hàng');
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(app.container.read(cartProvider).requireValue.totalQuantity, 1);
    expect(retry, findsNothing);
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    await _until(tester, 'catalog-product-$productId');
    expect(app.router.state.uri.path, '/customer/products');
  });

  testWidgets('AppBar back from cart restores details then catalog', (
    tester,
  ) async {
    final app = await _openStore(tester);
    await _tap(tester, 'catalog-product-$productId');
    await _until(tester, 'catalog-product-details');
    await _tap(tester, 'catalog-open-cart');
    await _until(tester, 'cart-checkout');
    await _tap(tester, 'cart-increase-$variantId');
    expect(app.container.read(cartProvider).requireValue.totalQuantity, 2);
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    await _until(tester, 'catalog-product-details');
    expect(app.router.state.uri.path, '/customer/products/$productId');
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    await _until(tester, 'catalog-product-$productId');
    expect(app.router.state.uri.path, '/customer/products');
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed cart write keeps retry usable and permits AppBar back', (
    tester,
  ) async {
    final app = await _openStore(tester, invalidWriteReceipt: true);
    await _tap(tester, 'catalog-open-cart');
    await _until(tester, 'cart-checkout');
    await _tap(tester, 'cart-increase-$variantId');
    expect(find.text('Dữ liệu giỏ hàng không hợp lệ.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('cart-retry')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    await _until(tester, 'catalog-product-$productId');
    expect(app.router.state.uri.path, '/customer/products');
    expect(tester.takeException(), isNull);
  });

  testWidgets('browser history restoration opens catalog after cart error', (
    tester,
  ) async {
    final app = await _openStore(tester, invalidWriteReceipt: true);
    final previous = app.router.routeInformationParser.restoreRouteInformation(
      app.router.routerDelegate.currentConfiguration,
    )!;
    await _tap(tester, 'catalog-open-cart');
    await _until(tester, 'cart-checkout');
    await _tap(tester, 'cart-increase-$variantId');
    expect(find.text('Dữ liệu giỏ hàng không hợp lệ.'), findsOneWidget);
    await app.router.routeInformationProvider.didPushRouteInformation(previous);
    await tester.pumpAndSettle();
    await _until(tester, 'catalog-product-$productId');
    expect(app.router.state.uri.path, '/customer/products');
    expect(tester.takeException(), isNull);
  });
}
