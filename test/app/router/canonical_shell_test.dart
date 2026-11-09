import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sports_store/app/shells/sports_store_shell.dart';
import 'package:sports_store/core/state/read_snapshot.dart';
import 'package:sports_store/features/auth/presentation/view_models/auth_providers.dart';
import 'package:sports_store/features/notifications/presentation/providers/notification_providers.dart';

class _FreshCount extends UnreadCountFoundationViewModel {
  @override
  ReadSnapshot<int> build() => const ReadSnapshot(data: 4);
}

class _StaleCount extends UnreadCountFoundationViewModel {
  @override
  ReadSnapshot<int> build() => const ReadSnapshot(data: 12, stale: true);
}

GoRouter _router(String role, {String? initial}) {
  final paths = switch (role) {
    'customer' => [
      '/customer/home',
      '/customer/products',
      '/customer/cart',
      '/customer/orders',
      '/customer/account',
      '/customer/checkout',
      '/customer/orders/:orderId',
    ],
    'manager' => [
      '/manager/orders',
      '/manager/products',
      '/manager/returns',
      '/manager/account',
      '/manager/orders/:orderId',
      '/cod',
    ],
    _ => [
      '/shipper/tasks',
      '/cod',
      '/shipper/account',
      '/shipper/tasks/:taskId/map',
    ],
  };
  return GoRouter(
    initialLocation: initial ?? paths.first,
    routes: [
      ShellRoute(
        builder: (c, s, child) =>
            SportsStoreShell(role: role, location: s.uri, child: child),
        routes: [
          for (final path in paths)
            GoRoute(
              path: path,
              builder: (c, s) {
                if (path.endsWith('/account')) {
                  return const SportsStoreAccountPage();
                }
                if (path.endsWith('/home')) return const SportsStoreHomePage();
                return Center(child: Text(s.uri.path));
              },
            ),
          GoRoute(
            path: '/notifications',
            builder: (c, s) => const Text('inbox-outlet'),
          ),
          GoRoute(path: '/chat', builder: (c, s) => const Text('chat-outlet')),
        ],
      ),
    ],
  );
}

Future<void> _pump(WidgetTester tester, GoRouter router, AppRole role) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentProfileProvider.overrideWith(
          (ref) async => AppProfile(
            id: 'account-1',
            role: role,
            fullName: 'Account under test',
          ),
        ),
        unreadCountFoundationProvider.overrideWith(_FreshCount.new),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });
}

void main() {
  final roles = {
    AppRole.customer: [
      'Trang chủ',
      'Sản phẩm',
      'Giỏ hàng',
      'Đơn hàng',
      'Tài khoản',
    ],
    AppRole.manager: ['Đơn hàng', 'Sản phẩm', 'Trả hàng', 'Tài khoản'],
    AppRole.shipper: ['Giao hàng', 'Thu hộ COD', 'Tài khoản'],
  };
  for (final entry in roles.entries) {
    testWidgets(
      '${entry.key.name} has one functional role navbar and account menu',
      (tester) async {
        final router = _router(entry.key.name);
        await _pump(tester, router, entry.key);
        expect(find.byType(MaterialApp), findsOneWidget);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(
          tester
              .widgetList<NavigationDestination>(
                find.byType(NavigationDestination),
              )
              .map((d) => d.label)
              .toList(),
          entry.value,
        );
        for (var index = 0; index < entry.value.length; index++) {
          await tester.tap(
            find.widgetWithText(NavigationDestination, entry.value[index]),
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<NavigationBar>(find.byType(NavigationBar))
                .selectedIndex,
            index,
          );
          expect(find.byType(SportsStoreShell), findsOneWidget);
        }
        expect(find.text('Account under test'), findsOneWidget);
        expect(
          find.text('Hội thoại'),
          entry.key == AppRole.shipper ? findsNothing : findsOneWidget,
        );
        expect(
          find.text('Đối soát COD'),
          entry.key == AppRole.manager ? findsOneWidget : findsNothing,
        );
        expect(find.text('DEMO LOCAL'), findsNothing);
        expect(find.text('Customer A'), findsNothing);
        await tester.tap(find.widgetWithText(ListTile, 'Thông báo'));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '/notifications');
        expect(find.byType(NavigationBar), findsOneWidget);
        router.pop();
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '/${entry.key.name}/account');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'checkout success destination and order detail Back retain the same shell',
    (tester) async {
      final router = _router('customer', initial: '/customer/checkout');
      await _pump(tester, router, AppRole.customer);
      final shell = tester.element(find.byType(SportsStoreShell));
      router.go('/customer/orders');
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(SportsStoreShell)), same(shell));
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3,
      );
      router.push('/customer/orders/order-1');
      await tester.pumpAndSettle();
      expect(find.text('/customer/orders/order-1'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/customer/orders');
      expect(find.byType(MaterialApp), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
    },
  );

  testWidgets(
    'shipper map deep link has one header and Back fallback to own task list',
    (tester) async {
      final router = _router('shipper', initial: '/shipper/tasks/task-1/map');
      await _pump(tester, router, AppRole.shipper);
      expect(find.text('Bản đồ'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/shipper/tasks');
      expect(find.byType(NavigationBar), findsOneWidget);
    },
  );

  testWidgets(
    'notification badge exposes fresh count and hides stale private snapshot',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            unreadCountFoundationProvider.overrideWith(_FreshCount.new),
          ],
          child: const MaterialApp(
            home: Scaffold(body: SportsStoreNotificationBell()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);
      expect(find.text('4'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            unreadCountFoundationProvider.overrideWith(_StaleCount.new),
          ],
          child: const MaterialApp(
            home: Scaffold(body: SportsStoreNotificationBell()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
      expect(find.text('12'), findsNothing);
    },
  );
}
