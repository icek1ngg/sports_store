import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sports_store/app/router/app_router.dart';
import 'package:sports_store/app/sports_store_app.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/support/operational_supabase_fixture.dart';

const _productId = '40000000-0000-4000-8000-000000000001';

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 180; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('Navigation did not reach the expected protected state.');
}

Future<GoRouter> _app(WidgetTester tester, SupabaseClient client) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [supabaseClientProvider.overrideWithValue(client)],
      child: const SportsStoreApp(),
    ),
  );
  await tester.pump();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(SportsStoreApp)),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.runAsync(client.dispose);
  });
  return container.read(appRouterProvider);
}

void main() {
  for (final role in ['shipper', 'manager']) {
    testWidgets('$role cannot read customer catalog routes', (tester) async {
      var productReads = 0;
      final client = (await tester.runAsync(
        () => fixtureClient((request) async {
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'role': role},
            ]);
          }
          if (request.url.path.endsWith('/products')) productReads++;
          return jsonResponse(request, []);
        }),
      ))!;
      final router = await _app(tester, client);
      router.go('/customer/products/$_productId');
      await _until(
        tester,
        () => router.routeInformationProvider.value.uri.path == '/',
      );
      expect(
        find.byKey(const ValueKey('catalog-product-details')),
        findsNothing,
      );
      expect(productReads, 0);
    });
  }

  testWidgets('signed out cannot reach catalog data', (tester) async {
    var reads = 0;
    final client = (await tester.runAsync(
      () => fixtureClient((request) async {
        reads++;
        return jsonResponse(request, []);
      }, userId: null),
    ))!;
    final router = await _app(tester, client);
    router.go('/customer/products');
    await _until(
      tester,
      () => router.routeInformationProvider.value.uri.path == '/',
    );
    expect(find.byKey(const ValueKey('catalog-product-list')), findsNothing);
    expect(reads, 0);
  });

  testWidgets('customer reads catalog and missing product safely', (
    tester,
  ) async {
    var productReads = 0;
    final client = (await tester.runAsync(
      () => fixtureClient((request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'customer'},
          ]);
        }
        if (request.url.path.endsWith('/products')) productReads++;
        return jsonResponse(request, []);
      }),
    ))!;
    final router = await _app(tester, client);
    router.go('/customer/products');
    await _until(
      tester,
      () => find
          .byKey(const ValueKey('catalog-products-empty-scroll'))
          .evaluate()
          .isNotEmpty,
    );
    expect(productReads, greaterThan(0));
    router.go('/customer/products/$_productId');
    await _until(
      tester,
      () => find
          .byKey(const ValueKey('catalog-product-unavailable'))
          .evaluate()
          .isNotEmpty,
    );
    expect(find.text('Sản phẩm không còn khả dụng'), findsOneWidget);
  });

  testWidgets('invalid product UUID makes no product request', (tester) async {
    var productReads = 0;
    final client = (await tester.runAsync(
      () => fixtureClient((request) async {
        if (request.url.path.endsWith('/products')) productReads++;
        return jsonResponse(request, [
          {'role': 'customer'},
        ]);
      }),
    ))!;
    final router = await _app(tester, client);
    router.go('/customer/products/not-a-uuid');
    await _until(
      tester,
      () => find
          .byKey(const ValueKey('navigation-invalid-id'))
          .evaluate()
          .isNotEmpty,
    );
    expect(productReads, 0);
  });

  testWidgets('account switch tears down visible customer catalog', (
    tester,
  ) async {
    var role = 'customer';
    final client = (await tester.runAsync(
      () => fixtureClient((request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': role},
          ]);
        }
        return jsonResponse(request, []);
      }),
    ))!;
    final router = await _app(tester, client);
    router.go('/customer/products');
    await _until(
      tester,
      () => find
          .byKey(const ValueKey('catalog-products-empty-scroll'))
          .evaluate()
          .isNotEmpty,
    );
    role = 'shipper';
    await tester.runAsync(() => recoverFixtureSession(client, shipperB));
    await _until(
      tester,
      () => router.routeInformationProvider.value.uri.path == '/',
    );
    expect(find.byKey(const ValueKey('catalog-product-list')), findsNothing);
  });
}
