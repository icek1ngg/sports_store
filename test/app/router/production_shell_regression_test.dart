import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:sports_store/app/integration/production_feature_composition.dart';
import 'package:sports_store/app/router/app_router.dart';
import 'package:sports_store/app/router/operational_route_guard.dart';
import 'package:sports_store/app/shells/sports_store_shell.dart';
import 'package:sports_store/app/sports_store_app.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/catalog/presentation/pages/product_list_page.dart';
import 'package:sports_store/features/orders/presentation/pages/customer_orders_page.dart';
import 'package:sports_store/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:sports_store/features/notifications/domain/models/notification_target.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/support/operational_supabase_fixture.dart';

const _customerId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const _otherCustomerId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _orderId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 220 && !ready(); i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(ready(), isTrue);
}

class _Transport {
  final requests = <http.Request>[];
  String profileUserId = _customerId;
  String role = 'customer';

  Future<http.Response> respond(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    if (path.endsWith('/profiles')) {
      return jsonResponse(request, [
        {
          'id': profileUserId,
          'role': role,
          'full_name': 'Customer profile from isolated transport',
          'phone': null,
        },
      ]);
    }
    if (path.endsWith('/notifications') && request.method == 'HEAD') {
      return http.Response(
        '',
        200,
        request: request,
        headers: {'content-range': '*/0'},
      );
    }
    if (path.endsWith('/categories') ||
        path.endsWith('/products') ||
        path.endsWith('/product_variants') ||
        path.endsWith('/cart_items') ||
        path.endsWith('/notifications')) {
      return jsonResponse(request, []);
    }
    if (path.endsWith('/rpc/get_manager_orders') ||
        path.endsWith('/rpc/get_customer_orders') ||
        path.endsWith('/rpc/get_order_details')) {
      // Missing deployed RPC remains unavailable. Never return a synthetic
      // OrderPage or a successful mutation just to make navigation pass.
      return jsonResponse(request, {
        'code': 'PGRST202',
        'message': 'Function is unavailable in this isolated transport',
      }, status: 404);
    }
    if (path.endsWith('/logout')) return jsonResponse(request, null);
    throw StateError('Unexpected production navigation request: $path');
  }
}

Future<({GoRouter router, ProviderContainer container, SupabaseClient client})>
_mount(WidgetTester tester, _Transport transport) async {
  final client = (await tester.runAsync(
    () => fixtureClient(transport.respond, userId: _customerId),
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
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.runAsync(client.dispose);
  });
  return (
    router: container.read(appRouterProvider),
    container: container,
    client: client,
  );
}

void _expectOneCustomerNavigation(WidgetTester tester) {
  expect(find.byType(MaterialApp), findsOneWidget);
  expect(find.byType(SportsStoreShell), findsOneWidget);
  expect(find.byType(NavigationBar), findsOneWidget);
  expect(find.byKey(const ValueKey('customer-navigation')), findsOneWidget);
  expect(
    find.widgetWithText(NavigationDestination, 'Trang chủ'),
    findsOneWidget,
  );
  expect(
    find.widgetWithText(NavigationDestination, 'Tài khoản'),
    findsOneWidget,
  );
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('manager notification target returns to inbox across branches', (
    tester,
  ) async {
    final app = await _mount(tester, _Transport()..role = 'manager');
    app.router.go('/notifications');
    await _until(
      tester,
      () => find.byType(NotificationsScreen).evaluate().isNotEmpty,
    );
    final page = tester.widget<NotificationsScreen>(
      find.byType(NotificationsScreen),
    );
    expect(
      await page.onNavigate!(
        const NotificationTargetDecision(
          available: true,
          screen: NotificationTargetScreen.managerOrder,
          entityId: _orderId,
          mode: NotificationTargetMode.order,
        ),
      ),
      isTrue,
    );
    await _until(
      tester,
      () => app.router.state.uri.path == '/manager/orders/$_orderId',
    );
    await tester.pump(const Duration(milliseconds: 200));
    app.router.pop();
    await tester.pump(const Duration(milliseconds: 500));
    await _until(
      tester,
      () =>
          app.router.state.uri.path == '/notifications' &&
          find.byType(NotificationsScreen).evaluate().isNotEmpty,
    );
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'manager Account survives profile revalidation and repeated tab visits',
    (tester) async {
      final transport = _Transport()..role = 'manager';
      final app = await _mount(tester, transport);
      app.router.go('/manager/account');
      await _until(
        tester,
        () =>
            find.byKey(const ValueKey('account-logout')).evaluate().isNotEmpty,
      );
      final router = app.container.read(appRouterProvider);
      final reads = transport.requests
          .where((r) => r.url.path.endsWith('/profiles'))
          .length;
      await tester.pump(const Duration(seconds: 15));
      expect(app.container.read(appRouterProvider), same(router));
      expect(
        transport.requests
            .where((r) => r.url.path.endsWith('/profiles'))
            .length,
        reads,
      );
      for (var i = 0; i < 3; i++) {
        await tester.tap(
          find.widgetWithText(NavigationDestination, 'Đơn hàng'),
        );
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(
          find.widgetWithText(NavigationDestination, 'Tài khoản'),
        );
        await _until(
          tester,
          () => find
              .byKey(const ValueKey('account-logout'))
              .evaluate()
              .isNotEmpty,
        );
      }
      expect(app.container.read(appRouterProvider), same(router));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'customer tab switch preserves the same unsubmitted search state',
    (tester) async {
      final app = await _mount(tester, _Transport());
      app.router.go('/customer/products');
      final search = find.byKey(const ValueKey('catalog-search-field'));
      await _until(tester, () => search.evaluate().isNotEmpty);
      final originalPageState = tester.state(find.byType(ProductListPage));
      await tester.enterText(search, 'Unsubmitted customer search');
      await tester.pump();
      await tester.tap(find.widgetWithText(NavigationDestination, 'Giỏ hàng'));
      await _until(tester, () => app.router.state.uri.path == '/customer/cart');
      expect(find.byType(ProductListPage), findsNothing);
      expect(originalPageState.mounted, isTrue);
      await tester.tap(find.widgetWithText(NavigationDestination, 'Sản phẩm'));
      await _until(tester, () => search.evaluate().isNotEmpty);
      expect(
        tester.state(find.byType(ProductListPage)),
        same(originalPageState),
      );
      expect(
        tester.widget<TextField>(search).controller!.text,
        'Unsubmitted customer search',
      );
      _expectOneCustomerNavigation(tester);
    },
  );

  testWidgets('account switch disposes hidden branch private widget state', (
    tester,
  ) async {
    final transport = _Transport();
    final app = await _mount(tester, transport);
    app.router.go('/customer/products');
    final search = find.byKey(const ValueKey('catalog-search-field'));
    await _until(tester, () => search.evaluate().isNotEmpty);
    final previousPageState = tester.state(find.byType(ProductListPage));
    await tester.enterText(search, 'Private text of previous customer');
    await tester.tap(find.widgetWithText(NavigationDestination, 'Giỏ hàng'));
    await _until(tester, () => app.router.state.uri.path == '/customer/cart');
    expect(previousPageState.mounted, isTrue);
    transport.profileUserId = _otherCustomerId;
    await tester.runAsync(
      () => recoverFixtureSession(app.client, _otherCustomerId),
    );
    await _until(
      tester,
      () =>
          app.container.read(featureSessionScopeProvider).userId ==
              _otherCustomerId &&
          !identical(app.container.read(appRouterProvider), app.router),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(previousPageState.mounted, isFalse);
    expect(
      find.text('Private text of previous customer', skipOffstage: false),
      findsNothing,
    );
    final newRouter = app.container.read(appRouterProvider);
    newRouter.go('/customer/products');
    await _until(tester, () => search.evaluate().isNotEmpty);
    expect(
      tester.state(find.byType(ProductListPage)),
      isNot(same(previousPageState)),
    );
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    _expectOneCustomerNavigation(tester);
  });

  testWidgets(
    'production customer flow keeps one navigation and missing Orders RPC fails closed',
    (tester) async {
      final transport = _Transport();
      final app = await _mount(tester, transport);
      for (final path in [
        '/customer/home',
        '/customer/products',
        '/customer/cart',
        '/customer/checkout',
        '/customer/orders',
      ]) {
        app.router.go(path);
        await _until(
          tester,
          () =>
              app.router.state.uri.path == path &&
              find
                  .byKey(const ValueKey('customer-navigation'))
                  .evaluate()
                  .isNotEmpty,
        );
        await tester.pump(const Duration(milliseconds: 120));
        _expectOneCustomerNavigation(tester);
      }
      await _until(
        tester,
        () => transport.requests.any(
          (r) => r.url.path.endsWith('/rpc/get_customer_orders'),
        ),
      );
      expect(find.byType(CustomerOrdersPage), findsOneWidget);
      expect(app.container.read(featureSessionScopeProvider).role, 'customer');

      app.router.push('/customer/orders/$_orderId');
      await _until(
        tester,
        () => find.byType(CustomerOrderDetailsPage).evaluate().isNotEmpty,
      );
      await _until(
        tester,
        () => transport.requests.any(
          (r) => r.url.path.endsWith('/rpc/get_order_details'),
        ),
      );
      await _until(
        tester,
        () => find
            .text('Thao tác hiện chưa khả dụng. Vui lòng thử lại sau.')
            .evaluate()
            .isNotEmpty,
      );
      expect(find.text('Hủy đơn'), findsNothing);
      _expectOneCustomerNavigation(tester);
      app.router.pop();
      await _until(
        tester,
        () => app.router.state.uri.path == '/customer/orders',
      );
      _expectOneCustomerNavigation(tester);
      expect(
        transport.requests.where(
          (r) =>
              r.url.path.contains('/rpc/') &&
              !r.url.path.endsWith('/get_customer_orders') &&
              !r.url.path.endsWith('/get_order_details'),
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'malformed customer detail UUID is denied before repository read',
    (tester) async {
      final transport = _Transport();
      final app = await _mount(tester, transport);
      final uri = Uri.parse('/customer/orders/not-a-uuid');
      expect(OperationalRouteLocation.parse(uri).invalidId, isTrue);
      expect(
        OperationalRouteLocation.parse(Uri.parse('/customer/orders/$_orderId'))
            .invalidId,
        isFalse,
      );
      app.router.go(uri.toString());
      await _until(
        tester,
        () => find
            .byKey(const ValueKey('navigation-invalid-id'))
            .evaluate()
            .isNotEmpty,
      );
      expect(find.byType(CustomerOrderDetailsPage), findsNothing);
      expect(
        transport.requests.where(
          (r) => r.url.path.endsWith('/rpc/get_order_details'),
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
