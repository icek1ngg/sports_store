import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/router/app_router.dart';
import 'package:sports_store/app/sports_store_app.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/catalog/presentation/pages/product_management_screen.dart';
import 'package:sports_store/features/chat/presentation/pages/conversation_list_screen.dart';
import 'package:sports_store/features/deliveries/presentation/pages/delivery_task_list_page.dart';

import '../../features/support/operational_supabase_fixture.dart';

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
      () => find.byType(ProductManagementScreen).evaluate().isNotEmpty,
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

  for (final entry in ['/', '/login']) {
    testWidgets('shipper enters MH10 automatically from $entry', (
      tester,
    ) async {
      final client = (await tester.runAsync(
        () => fixtureClient((request) async {
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'id': manager, 'role': 'shipper', 'full_name': 'Giao hàng'},
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
        }, userId: manager),
      ))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [supabaseClientProvider.overrideWithValue(client)],
          child: const SportsStoreApp(),
        ),
      );
      final router = ProviderScope.containerOf(
        tester.element(find.byType(SportsStoreApp)),
      ).read(appRouterProvider);
      router.go(entry);
      await until(
        tester,
        () => find.byType(DeliveryTaskListPage).evaluate().isNotEmpty,
      );
      expect(router.state.uri.path, '/shipper/tasks');
      expect(find.text('Mở nhiệm vụ giao hàng'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    });
  }

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
        () => find.text('Không có sản phẩm phù hợp.').evaluate().isNotEmpty,
      );
      expect(calls.any((p) => p.endsWith('/products')), isTrue);
      expect(calls.any((p) => p.endsWith('/profiles')), isTrue);
      final router = ProviderScope.containerOf(
        tester.element(find.byType(SportsStoreApp)),
      ).read(appRouterProvider);
      await tester.tap(find.text('COD'));
      await until(
        tester,
        () => find.byKey(const ValueKey('mh12-outlet')).evaluate().isNotEmpty,
      );
      expect(router.state.uri.path, '/cod');
      expect(
        tester
            .widget<NavigationBar>(
              find.byKey(const ValueKey('manager-navigation')),
            )
            .selectedIndex,
        2,
      );
      await tester.tap(find.text('Sản phẩm'));
      await until(
        tester,
        () => find.byType(ProductManagementScreen).evaluate().isNotEmpty,
      );
      expect(router.state.uri.path, '/manager/products');
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
          if (request.url.path.endsWith('/list_chat_conversations')) {
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
        () => find.text('Liên hệ cửa hàng').evaluate().isNotEmpty,
      );
      final router = ProviderScope.containerOf(
        tester.element(find.byType(SportsStoreApp)),
      ).read(appRouterProvider);
      await tester.tap(find.byTooltip('Danh mục sản phẩm'));
      await until(tester, () => router.state.uri.path == '/customer/products');
      router.go('/');
      await until(
        tester,
        () => find.text('Liên hệ cửa hàng').evaluate().isNotEmpty,
      );
      router.go('/manager/products');
      await until(
        tester,
        () => find
            .text('Chỉ quản lý được truy cập màn sản phẩm.')
            .evaluate()
            .isNotEmpty,
      );
      expect(productReads, 0);
      router.go('/chat/not-a-uuid');
      await until(
        tester,
        () => find.text('Mã hội thoại không hợp lệ.').evaluate().isNotEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    },
  );
}
