import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:sports_store/app/router/app_router.dart';
import 'package:sports_store/app/sports_store_app.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/notifications/presentation/pages/notifications_page.dart';
import 'package:sports_store/features/orders/presentation/pages/customer_orders_page.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_order_details_page.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_orders_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/support/operational_supabase_fixture.dart';

const _orderId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 180; attempt++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('Four-screen route did not reach the expected state.');
}

Future<({GoRouter router, SupabaseClient client, ProviderContainer container})>
_pumpApp(
  WidgetTester tester, {
  required SessionScope scope,
  Future<http.Response> Function(http.Request request)? handler,
  ProviderListenable<SessionScope>? scopeListenable,
}) async {
  final client = await tester.runAsync(
    () => fixtureClient(
      handler ?? ((request) async => jsonResponse(request, const <Object>[])),
    ),
  );
  if (client == null) fail('Fixture client was not created.');

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        scopeListenable == null
            ? featureSessionScopeProvider.overrideWithValue(scope)
            : featureSessionScopeProvider.overrideWith(
                (ref) => ref.watch(scopeListenable),
              ),
      ],
      child: const SportsStoreApp(),
    ),
  );
  await tester.pump();
  final context = tester.element(find.byType(SportsStoreApp));
  final container = ProviderScope.containerOf(context);
  final router = container.read(appRouterProvider);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.runAsync(client.dispose);
  });
  return (router: router, client: client, container: container);
}

void main() {
  testWidgets('customer orders is role-scoped and mounts through the router', (
    tester,
  ) async {
    final app = await _pumpApp(
      tester,
      scope: const SessionScope(
        userId: shipperA,
        role: 'customer',
        generation: 1,
      ),
    );

    app.router.go('/customer/orders');
    await _until(
      tester,
      () => find.byType(CustomerOrdersPage).evaluate().isNotEmpty,
    );
    expect(app.router.state.uri.path, '/customer/orders');
  });

  testWidgets('manager orders is role-scoped and mounts through the router', (
    tester,
  ) async {
    final app = await _pumpApp(
      tester,
      scope: const SessionScope(
        userId: shipperA,
        role: 'manager',
        generation: 1,
      ),
    );

    app.router.go('/manager/orders');
    await _until(
      tester,
      () => find.byType(ManagerOrdersPage).evaluate().isNotEmpty,
    );
    expect(app.router.state.uri.path, '/manager/orders');
  });

  testWidgets('manager order list opens MH09 and back returns to MH08', (
    tester,
  ) async {
    final app = await _pumpApp(
      tester,
      scope: const SessionScope(
        userId: shipperA,
        role: 'manager',
        generation: 1,
      ),
    );

    app.router.go('/manager/orders');
    await _until(
      tester,
      () => find.byType(ManagerOrdersPage).evaluate().isNotEmpty,
    );
    final page = tester.widget<ManagerOrdersPage>(
      find.byType(ManagerOrdersPage),
    );
    page.onOpenOrder!(_orderId);
    await _until(
      tester,
      () => find.byType(ManagerOrderDetailsPage).evaluate().isNotEmpty,
    );
    expect(app.router.state.uri.path, '/manager/orders/$_orderId');

    app.router.pop();
    await _until(
      tester,
      () =>
          app.router.state.uri.path == '/manager/orders' &&
          find.byType(ManagerOrdersPage).evaluate().isNotEmpty,
    );
  });

  testWidgets('manager route rejects a malformed order UUID before the page', (
    tester,
  ) async {
    final app = await _pumpApp(
      tester,
      scope: const SessionScope(
        userId: shipperA,
        role: 'manager',
        generation: 1,
      ),
    );

    app.router.go('/manager/orders/not-a-uuid');
    await _until(
      tester,
      () => find
          .byKey(const ValueKey('navigation-invalid-id'))
          .evaluate()
          .isNotEmpty,
    );
    expect(find.byType(ManagerOrderDetailsPage), findsNothing);
  });

  testWidgets('manager order detail accepts only a strict UUID', (
    tester,
  ) async {
    final app = await _pumpApp(
      tester,
      scope: const SessionScope(
        userId: shipperA,
        role: 'manager',
        generation: 1,
      ),
    );

    app.router.go('/manager/orders/$_orderId');
    await _until(
      tester,
      () => find.byType(ManagerOrderDetailsPage).evaluate().isNotEmpty,
    );
    expect(app.router.state.uri.path, '/manager/orders/$_orderId');
  });

  testWidgets(
    'notifications defaults to the real MH17 page but remains overridable',
    (tester) async {
      final app = await _pumpApp(
        tester,
        scope: const SessionScope(
          userId: shipperA,
          role: 'shipper',
          generation: 1,
        ),
        handler: (request) async {
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'role': 'shipper'},
            ]);
          }
          return jsonResponse(request, const <Object>[]);
        },
      );

      app.router.go('/notifications');
      await _until(
        tester,
        () => find.byType(NotificationsPage).evaluate().isNotEmpty,
      );
      expect(app.router.state.uri.path, '/notifications');
    },
  );

  testWidgets('scope change dismisses a root dialog and removes old orders', (
    tester,
  ) async {
    final scopeState = StateProvider<SessionScope>(
      (ref) =>
          const SessionScope(userId: shipperA, role: 'customer', generation: 1),
    );
    final app = await _pumpApp(
      tester,
      scope: const SessionScope.unresolved(),
      scopeListenable: scopeState,
    );

    app.router.go('/customer/orders');
    await _until(
      tester,
      () => find.byType(CustomerOrdersPage).evaluate().isNotEmpty,
    );
    final dialogClosed = showDialog<void>(
      context: tester.element(find.byType(CustomerOrdersPage)),
      builder: (_) => const AlertDialog(content: Text('old scope dialog')),
    );
    await tester.pump();
    expect(find.text('old scope dialog'), findsOneWidget);

    app.container.read(scopeState.notifier).state =
        const SessionScope.unresolved();
    await _until(
      tester,
      () =>
          find.text('old scope dialog').evaluate().isEmpty &&
          find.byType(CustomerOrdersPage).evaluate().isEmpty,
    );
    await dialogClosed;
    expect(app.router.state.uri.path, '/customer/orders');
  });
}
