import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sports_store/app/demo/data/local_demo_store.dart';
import 'package:sports_store/app/demo/demo_network_guard.dart';
import 'package:sports_store/app/dev/dev_app.dart';
import 'package:sports_store/app/dev/data/local_auth_repository.dart';
import 'package:sports_store/features/auth/presentation/pages/login_screen.dart';
import 'package:sports_store/features/catalog/presentation/pages/product_list_page.dart';
import 'package:sports_store/features/catalog/presentation/pages/product_management_screen.dart';
import 'package:sports_store/features/cart/presentation/pages/cart_page.dart';
import 'package:sports_store/features/orders/presentation/pages/customer_orders_page.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_orders_page.dart';
import 'package:sports_store/features/deliveries/presentation/pages/delivery_task_list_page.dart';
import 'package:sports_store/shared/widgets/prm_preview_widgets.dart';

Future<void> login(WidgetTester t, String name) async {
  await t.enterText(find.byType(TextFormField).at(0), '$name@local.test');
  await t.enterText(find.byType(TextFormField).at(1), 'sports123');
  await t.ensureVisible(find.widgetWithText(PrimaryButton, 'Đăng nhập'));
  await t.tap(find.widgetWithText(PrimaryButton, 'Đăng nhập'));
  await t.pumpAndSettle();
}

Future<void> tab(WidgetTester t, String label) async {
  await t.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'full app login, preserved customer tabs, role guards and logout privacy stay offline',
    (t) async {
      await t.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final previous = HttpOverrides.current;
      HttpOverrides.global = DemoNetworkGuard();
      addTearDown(() => HttpOverrides.global = previous);
      await t.pumpWidget(const FullDevApp());
      await t.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.textContaining('DEMO LOCAL'), findsNothing);
      await login(t, 'customer');
      expect(find.text('Sẵn sàng cho mọi chuyển động'), findsOneWidget);
      await tab(t, 'Sản phẩm');
      expect(find.byType(ProductListPage), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('catalog-search-field')),
        'Giày',
      );
      await t.testTextInput.receiveAction(TextInputAction.search);
      await t.pumpAndSettle();
      await tab(t, 'Giỏ hàng');
      expect(find.byType(CartPage), findsOneWidget);
      await tab(t, 'Sản phẩm');
      expect(find.text('Giày'), findsOneWidget);
      await tab(t, 'Đơn hàng');
      expect(find.byType(CustomerOrdersPage), findsOneWidget);
      final c = t.element(find.byType(CustomerOrdersPage));
      GoRouter.of(c).go('/manager/orders');
      await t.pumpAndSettle();
      expect(find.byType(ManagerOrdersPage), findsNothing);
      await tab(t, 'Tài khoản');
      await t.tap(find.byKey(const ValueKey('dev-logout')));
      await t.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(CustomerOrdersPage), findsNothing);
      await login(t, 'manager');
      expect(find.byType(ManagerOrdersPage), findsOneWidget);
      expect(find.text('Giỏ hàng'), findsNothing);
      await tab(t, 'Sản phẩm');
      expect(find.byType(ProductManagementScreen), findsOneWidget);
      await tab(t, 'Tài khoản');
      await t.tap(find.byKey(const ValueKey('dev-logout')));
      await t.pumpAndSettle();
      await login(t, 'shipper');
      expect(find.byType(DeliveryTaskListPage), findsOneWidget);
      expect(find.text('Giỏ hàng'), findsNothing);
      expect(find.text('Sản phẩm'), findsNothing);
      await tab(t, 'Thu hộ COD');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    },
  );

  testWidgets(
    'customer nested detail respects Android status inset and system Back',
    (t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      t.view.padding = const FakeViewPadding(top: 96);
      addTearDown(t.view.resetPadding);
      await t.pumpWidget(const FullDevApp());
      await t.pumpAndSettle();
      await login(t, 'customer');
      await tab(t, 'Đơn hàng');
      await t.ensureVisible(find.text('Xem chi tiết').first);
      await t.tap(find.text('Xem chi tiết').first);
      await t.pumpAndSettle();
      expect(find.byType(CustomerOrderDetailsPage), findsOneWidget);
      final inset = t.view.padding.top / t.view.devicePixelRatio;
      expect(inset, greaterThan(0));
      expect(
        t.getTopLeft(find.text('Chi tiết đơn hàng')).dy,
        greaterThanOrEqualTo(inset),
      );
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byType(CustomerOrdersPage), findsOneWidget);
      expect(find.byType(CustomerOrderDetailsPage), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    },
  );

  test('local registration creates an independent customer namespace, never Customer C', () async {
    final store = LocalDemoStore();
    final auth = LocalAuthRepository(store);
    await auth.register(
      fullName: 'Khách mới',
      phone: '0912345678',
      email: 'new@local.test',
      password: 'password123',
    );
    await auth.login(email: 'new@local.test', password: 'password123');
    expect(store.session.userId, isNot(LocalDemoStore.customerCId));
    expect(store.session.role, 'customer');
    expect((await auth.getCurrentProfile())!.fullName, 'Khách mới');
    await auth.logout();
    expect(auth.currentSession.signedIn, isFalse);
    expect(store.session.canReadPrivateData, isFalse);
    await expectLater(
      store.orders.getOrderDetails(LocalDemoStore.orderId(7)),
      throwsA(anything),
    );
    await Future<void>.delayed(Duration.zero);
    auth.dispose();
  });
}
