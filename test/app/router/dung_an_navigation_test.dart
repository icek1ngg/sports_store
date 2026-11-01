import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/router/app_router.dart';
import 'package:sports_store/app/sports_store_app.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/features/auth/presentation/view_models/auth_providers.dart';
import 'package:sports_store/features/catalog/presentation/pages/product_management_screen.dart';
import 'package:sports_store/features/chat/presentation/pages/conversation_list_screen.dart';
import 'package:sports_store/features/deliveries/presentation/pages/delivery_task_list_page.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_orders_page.dart';
import 'package:sports_store/features/orders/presentation/view_models/order_providers.dart';

import '../../features/support/operational_supabase_fixture.dart';
import '../../fixtures/order_list_page_fixtures.dart';

const manager = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const customer = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

Future<void> until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 150 && !ready(); i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(ready(), isTrue);
}

void main() {
  testWidgets('revoked shipper role refreshes profile without redirect loop', (
    tester,
  ) async {
    var profileReads = 0;
    var roleReads = 0;
    final client = (await tester.runAsync(
      () => fixtureClient((request) async {
        if (request.url.path.endsWith('/profiles')) {
          if (request.url.queryParameters['select'] == 'role') {
            roleReads++;
            return jsonResponse(request, [
              {'role': 'manager'},
            ]);
          }
          profileReads++;
          return jsonResponse(request, [
            {
              'id': manager,
              'role': profileReads == 1 ? 'shipper' : 'manager',
              'full_name': 'Quản lý',
            },
          ]);
        }
        if (request.url.path.endsWith('/categories') ||
            request.url.path.endsWith('/products') ||
            request.url.path.endsWith('/product_variants')) {
          return jsonResponse(request, []);
        }
        throw StateError('Unexpected request ${request.url.path}');
      }, userId: manager),
    ))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseClientProvider.overrideWithValue(client)],
        child: const SportsStoreApp(),
      ),
    );
    await until(
      tester,
      () => find
          .text('Dịch vụ quản lý đơn hàng chưa được tích hợp.')
          .evaluate()
          .isNotEmpty,
    );
    await tester.pumpAndSettle();
    expect(profileReads, 2);
    final settledRoleReads = roleReads;
    await tester.pump(const Duration(seconds: 1));
    expect(roleReads, settledRoleReads);
    expect(find.byType(DeliveryTaskListPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(client.dispose);
  });

  testWidgets(
    'root Auth bridge loads injected MH08 and manager can return from COD',
    (tester) async {
      final orders = OrderListFixtureRepository(managerPage: listFixturePage());
      final client = (await tester.runAsync(
        () => fixtureClient((request) async {
          if (request.url.path.endsWith('/profiles')) {
            if (request.url.queryParameters['select'] == 'role') {
              return jsonResponse(request, {'role': 'manager'});
            }
            return jsonResponse(request, [
              {
                'id': manager,
                'role': 'manager',
                'full_name': 'Manager',
                'phone': null,
              },
            ]);
          }
          if (request.url.path.endsWith('/list_cod_collections')) {
            return jsonResponse(request, {
              'items': [],
              'next_cursor': null,
              'filtered_total': 0,
              'counts': {
                'all': 0,
                'uncollected': 0,
                'collected': 0,
                'received': 0,
              },
              'outstanding_vnd': 0,
              'as_of': '2026-10-30T03:00:00Z',
            });
          }
          if (request.url.path.endsWith('/categories') ||
              request.url.path.endsWith('/products') ||
              request.url.path.endsWith('/product_variants')) {
            return jsonResponse(request, []);
          }
          throw StateError('Unexpected request ${request.url.path}');
        }, userId: manager),
      ))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supabaseClientProvider.overrideWithValue(client),
            // The same root-container bridge installed by lib/main.dart.
            featureSessionScopeProvider.overrideWith(
              (ref) => ref.watch(trustedFeatureSessionProvider),
            ),
            orderRepositoryProvider.overrideWithValue(orders),
          ],
          child: const SportsStoreApp(),
        ),
      );
      await until(
        tester,
        () =>
            orders.managerQueries.isNotEmpty &&
            find.byType(ManagerOrdersPage).evaluate().isNotEmpty,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SportsStoreApp)),
      );
      expect(container.read(featureSessionScopeProvider).userId, manager);
      expect(container.read(featureSessionScopeProvider).role, 'manager');
      final originalScope = container.read(featureSessionScopeProvider);
      await tester.tap(find.text('COD'));
      await until(
        tester,
        () => find.byKey(const ValueKey('manager-home')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const ValueKey('manager-home')));
      await until(
        tester,
        () => find.byType(ManagerOrdersPage).evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Sản phẩm'));
      await until(
        tester,
        () => find.text('Không có sản phẩm phù hợp.').evaluate().isNotEmpty,
      );
      await tester.runAsync(() => recoverFixtureSession(client, customer));
      await until(
        tester,
        () =>
            !container.read(featureSessionScopeProvider).canReadPrivateData ||
            container.read(featureSessionScopeProvider).userId == customer,
      );
      expect(
        container.read(featureSessionScopeProvider).generation,
        greaterThan(originalScope.generation),
      );
      expect(find.byType(ManagerOrdersPage), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    },
  );

  testWidgets(
    'manager navigation uses live repositories; sign out removes private UI',
    (tester) async {
      final calls = <String>[];
      final client = (await tester.runAsync(
        () => fixtureClient((request) async {
          calls.add(request.url.path);
          if (request.url.path.endsWith('/profiles')) {
            if (request.url.queryParameters['select'] == 'role') {
              return jsonResponse(request, {'role': 'manager'});
            }
            return jsonResponse(request, [
              {
                'id': manager,
                'role': 'manager',
                'full_name': 'Quản lý',
                'phone': null,
              },
            ]);
          }
          if (request.url.path.endsWith('/categories') ||
              request.url.path.endsWith('/products') ||
              request.url.path.endsWith('/product_variants') ||
              request.url.path.endsWith('/list_chat_conversations')) {
            return jsonResponse(request, []);
          }
          if (request.url.path.endsWith('/logout')) {
            return jsonResponse(request, {});
          }
          throw StateError('Unexpected request ${request.url.path}');
        }, userId: manager),
      ))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [supabaseClientProvider.overrideWithValue(client)],
          child: const SportsStoreApp(),
        ),
      );
      await until(
        tester,
        () => find
            .text('Dịch vụ quản lý đơn hàng chưa được tích hợp.')
            .evaluate()
            .isNotEmpty,
      );
      expect(calls.any((p) => p.endsWith('/profiles')), isTrue);
      final router = ProviderScope.containerOf(
        tester.element(find.byType(SportsStoreApp)),
      ).read(appRouterProvider);
      expect(router.state.uri.path, '/manager/orders');
      router.go('/manager/products');
      await until(
        tester,
        () => find.text('Không có sản phẩm phù hợp.').evaluate().isNotEmpty,
      );
      expect(calls.any((p) => p.endsWith('/products')), isTrue);
      router.go('/chat');
      await until(
        tester,
        () => find.text('Chưa có hội thoại phù hợp.').evaluate().isNotEmpty,
      );
      expect(calls.any((p) => p.endsWith('/list_chat_conversations')), isTrue);
      expect(find.byType(ConversationListScreen), findsOneWidget);
      // Account changes must close imperative forms/sheets as well as route pages.
      showModalBottomSheet<void>(
        context: tester.element(find.byType(ConversationListScreen)),
        builder: (_) =>
            const SizedBox(height: 100, child: Text('Private manager draft')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Private manager draft'), findsOneWidget);
      await tester.runAsync(() => recoverFixtureSession(client, customer));
      await until(
        tester,
        () => find.text('Private manager draft').evaluate().isEmpty,
      );
      // Restore the manager and exercise the real logout button separately.
      await tester.runAsync(() => recoverFixtureSession(client, manager));
      await until(tester, () => find.text('Đăng xuất').evaluate().isNotEmpty);
      await tester.tap(find.text('Đăng xuất'));
      await until(tester, () => find.text('Đăng nhập').evaluate().isNotEmpty);
      expect(find.byType(ConversationListScreen), findsNothing);
      expect(find.byType(ProductManagementScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    },
  );

  testWidgets(
    'customer metadata cannot authorize manager products and can start own chat',
    (tester) async {
      var productReads = 0;
      final client = (await tester.runAsync(
        () => fixtureClient((request) async {
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {
                'id': customer,
                'role': 'customer',
                'full_name': 'Khách hàng',
                'phone': null,
              },
            ]);
          }
          if (request.url.path.endsWith('/products')) productReads++;
          if (request.url.path.endsWith('/list_chat_conversations') ||
              request.url.path.endsWith('/categories') ||
              request.url.path.endsWith('/products') ||
              request.url.path.endsWith('/product_variants')) {
            return jsonResponse(request, []);
          }
          return jsonResponse(request, {});
        }, userId: customer),
      ))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [supabaseClientProvider.overrideWithValue(client)],
          child: const SportsStoreApp(),
        ),
      );
      await until(
        tester,
        () => find
            .byKey(const ValueKey('catalog-products-empty-scroll'))
            .evaluate()
            .isNotEmpty,
      );
      final router = ProviderScope.containerOf(
        tester.element(find.byType(SportsStoreApp)),
      ).read(appRouterProvider);
      expect(router.state.uri.path, '/customer/products');
      router.go('/chat');
      await until(
        tester,
        () => find.text('Liên hệ cửa hàng').evaluate().isNotEmpty,
      );
      final readsBeforeDenied = productReads;
      router.go('/manager/products');
      await until(
        tester,
        () => find
            .text('Chỉ quản lý được truy cập màn sản phẩm.')
            .evaluate()
            .isNotEmpty,
      );
      expect(productReads, readsBeforeDenied);
      router.go('/chat/not-a-uuid');
      await until(
        tester,
        () => find.text('Mã hội thoại không hợp lệ.').evaluate().isNotEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    },
  );

  testWidgets('customer home opens the integrated MH04 catalog', (
    tester,
  ) async {
    final client = (await tester.runAsync(
      () => fixtureClient((request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {
              'id': customer,
              'role': 'customer',
              'full_name': 'Khách',
              'phone': null,
            },
          ]);
        }
        if (request.url.path.endsWith('/categories') ||
            request.url.path.endsWith('/products') ||
            request.url.path.endsWith('/product_variants')) {
          return jsonResponse(request, []);
        }
        throw StateError('Unexpected request ${request.url.path}');
      }, userId: customer),
    ))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseClientProvider.overrideWithValue(client)],
        child: const SportsStoreApp(),
      ),
    );
    await until(
      tester,
      () => find
          .byKey(const ValueKey('catalog-products-empty-scroll'))
          .evaluate()
          .isNotEmpty,
    );
    expect(find.byType(ConversationListScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(client.dispose);
  });

  testWidgets('shipper goes directly to MH10 without another open-task click', (
    tester,
  ) async {
    final client = (await tester.runAsync(
      () => fixtureClient((request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {
              'id': shipperA,
              'role': 'shipper',
              'full_name': 'Shipper',
              'phone': null,
            },
          ]);
        }
        if (request.url.path.endsWith('/list_my_delivery_tasks')) {
          return jsonResponse(request, {
            'items': [],
            'next_cursor': null,
            'filtered_total': 0,
            'counts': {
              'waiting': 0,
              'in_transit': 0,
              'completed': 0,
              'ungrouped': 0,
            },
            'as_of': '2026-10-30T03:00:00Z',
          });
        }
        throw StateError('Unexpected request ${request.url.path}');
      }, userId: shipperA),
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
    await until(
      tester,
      () =>
          container.read(appRouterProvider).state.uri.path == '/shipper/tasks',
    );
    expect(find.text('Mở nhiệm vụ giao hàng'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(client.dispose);
  });
}
