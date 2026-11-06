import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/router/app_router.dart';
import 'package:sports_store/app/sports_store_app.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';

import '../../features/support/operational_supabase_fixture.dart';

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 180; i++) {
    if (done()) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('Cart route did not reach expected state');
}

void main() {
  for (final role in ['manager', 'shipper', 'signed-out']) {
    testWidgets('$role cannot open customer cart or read cart rows', (
      tester,
    ) async {
      var cartReads = 0;
      final client = (await tester.runAsync(
        () => fixtureClient((request) async {
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'role': role},
            ]);
          }
          if (request.url.path.endsWith('/cart_items')) cartReads++;
          return jsonResponse(request, []);
        }, userId: role == 'signed-out' ? null : shipperA),
      ))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [supabaseClientProvider.overrideWithValue(client)],
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
      router.go('/customer/cart');
      await _until(
        tester,
        () => router.routeInformationProvider.value.uri.path == '/',
      );
      expect(find.byKey(const ValueKey('cart-page')), findsNothing);
      expect(cartReads, 0);
    });
  }

  testWidgets('customer opens cart then account change tears it down', (
    tester,
  ) async {
    final client = (await tester.runAsync(
      () => fixtureClient((request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'customer'},
          ]);
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
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SportsStoreApp)),
    );
    final router = container.read(appRouterProvider);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    });
    router.go('/customer/cart');
    await _until(
      tester,
      () => find.byKey(const ValueKey('cart-empty')).evaluate().isNotEmpty,
    );
    await tester.runAsync(() => recoverFixtureSession(client, shipperB));
    await _until(
      tester,
      () => router.routeInformationProvider.value.uri.path == '/',
    );
    expect(find.byKey(const ValueKey('cart-page')), findsNothing);
  });
}
