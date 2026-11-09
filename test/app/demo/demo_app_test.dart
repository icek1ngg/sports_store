import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/demo/data/local_demo_store.dart';
import 'package:sports_store/app/demo/demo_app.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/features/notifications/domain/models/notification_query.dart';
import 'package:sports_store/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:sports_store/features/notifications/presentation/widgets/notification_tile.dart';
import 'package:sports_store/features/notifications/presentation/widgets/unread_badge.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/presentation/pages/customer_orders_page.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_order_details_page.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_orders_page.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_order_card.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh07_order_card.dart';

Future<void> _selectAccount(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('demo-account-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(MaterialApp)),
  listen: false,
);

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('role navigation reuses actual pages and one provider scope', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = LocalDemoStore();
    await tester.pumpWidget(LocalDemoApp(store: store));
    await tester.pumpAndSettle();
    final container = _container(tester);
    expect(find.byType(CustomerOrdersPage), findsOneWidget);
    expect(
      container.read(featureSessionScopeProvider).userId,
      LocalDemoStore.customerAId,
    );

    await _selectAccount(tester, 'Manager B');
    expect(find.byType(ManagerOrdersPage), findsOneWidget);
    expect(identical(container, _container(tester)), isTrue);
    await tester.ensureVisible(
      find.byKey(const ValueKey('mh08-open-order')).first,
    );
    await tester.tap(find.byKey(const ValueKey('mh08-open-order')).first);
    await tester.pumpAndSettle();
    expect(find.byType(ManagerOrderDetailsPage), findsOneWidget);

    await _selectAccount(tester, 'Customer C');
    expect(find.byType(CustomerOrdersPage), findsOneWidget);
    expect(find.byType(ManagerOrderDetailsPage), findsNothing);
    expect(
      container.read(featureSessionScopeProvider).userId,
      LocalDemoStore.customerCId,
    );
    expect(find.textContaining('Nguyễn Minh Anh'), findsNothing);
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });

  testWidgets(
    'manager confirmation reaches customer state and reset restores seed',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = LocalDemoStore();
      await tester.pumpWidget(LocalDemoApp(store: store));
      await tester.pumpAndSettle();
      await _selectAccount(tester, 'Manager B');
      final card = tester.widget<Mh08OrderCard>(
        find.byType(Mh08OrderCard).first,
      );
      final orderId = card.summary.order.id;
      expect(card.summary.order.status, OrderStatus.pendingConfirmation);
      final confirm = find.byKey(const ValueKey('mh08-confirm')).first;
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('order-action-submit')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        ((await tester.runAsync(() => store.orders.getOrderDetails(orderId)))!)
            .order
            .status,
        OrderStatus.preparing,
      );
      await _selectAccount(tester, 'Customer A');
      expect(
        ((await tester.runAsync(() => store.orders.getOrderDetails(orderId)))!)
            .order
            .status,
        OrderStatus.preparing,
      );
      expect(find.byType(CustomerOrdersPage), findsOneWidget);
      expect(
        tester
            .widgetList<Mh07OrderCard>(find.byType(Mh07OrderCard))
            .firstWhere((card) => card.summary.order.id == orderId)
            .summary
            .order
            .status,
        OrderStatus.preparing,
      );
      await tester.tap(find.byKey(const ValueKey('demo-reset')));
      await tester.pumpAndSettle();
      expect(
        ((await tester.runAsync(() => store.orders.getOrderDetails(orderId)))!)
            .order
            .status,
        OrderStatus.pendingConfirmation,
      );
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    },
  );

  testWidgets(
    'account switch closes a live action dialog without stale mutation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = LocalDemoStore(account: DemoAccount.managerB);
      await tester.pumpWidget(LocalDemoApp(store: store));
      await tester.pumpAndSettle();
      final reject = find.byKey(const ValueKey('mh08-reject')).first;
      await tester.ensureVisible(reject);
      await tester.tap(reject);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('order-action-reason')),
        'Lý do riêng của quản lý',
      );
      // Simulate an account event while a modal blocks physical toolbar taps.
      tester
          .widget<PopupMenuButton<DemoAccount>>(
            find.byKey(const ValueKey('demo-account-menu')),
          )
          .onSelected!(DemoAccount.customerC);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Lý do riêng của quản lý'), findsNothing);
      expect(find.byType(CustomerOrdersPage), findsOneWidget);
      expect(store.session.userId, LocalDemoStore.customerCId);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    },
  );

  testWidgets(
    'notification read state and count remain recipient scoped offline',
    (tester) async {
      var networkClients = 0;
      await HttpOverrides.runZoned(
        () async {
          await tester.binding.setSurfaceSize(const Size(1000, 1400));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final store = LocalDemoStore();
          await tester.pumpWidget(LocalDemoApp(store: store));
          await tester.pumpAndSettle();
          await tester.tap(find.text('MH17').last);
          await tester.pumpAndSettle();
          expect(find.byType(NotificationsScreen), findsOneWidget);
          final before = (await tester.runAsync(
            () => store.notifications.getUnreadCount(),
          ))!;
          expect(
            tester.widget<UnreadBadge>(find.byType(UnreadBadge)).count,
            before,
          );
          final unread = tester
              .widgetList<NotificationTile>(find.byType(NotificationTile))
              .firstWhere((tile) => !tile.notification.isRead);
          final notificationId = unread.notification.id;
          final tile = find.byKey(ValueKey(notificationId));
          final read = find.descendant(
            of: tile,
            matching: find.text('Đánh dấu đã đọc'),
          );
          await tester.ensureVisible(read);
          await tester.tap(read);
          await tester.pumpAndSettle();
          expect(
            (await tester.runAsync(
              () => store.notifications.getUnreadCount(),
            ))!,
            before - 1,
          );
          expect(
            tester.widget<UnreadBadge>(find.byType(UnreadBadge)).count,
            before - 1,
          );

          await _selectAccount(tester, 'Customer C');
          await tester.tap(find.text('MH17').last);
          await tester.pumpAndSettle();
          expect(find.byKey(ValueKey(notificationId)), findsNothing);
          final page = (await tester.runAsync(
            () => store.notifications.getPage(NotificationQuery()),
          ))!;
          expect(
            page.items.every(
              (item) => item.recipientId == LocalDemoStore.customerCId,
            ),
            isTrue,
          );
          expect(
            tester
                .widgetList<NotificationTile>(find.byType(NotificationTile))
                .every(
                  (tile) =>
                      tile.notification.recipientId ==
                      LocalDemoStore.customerCId,
                ),
            isTrue,
          );
          await _selectAccount(tester, 'Customer A');
          await tester.tap(find.text('MH17').last);
          await tester.pumpAndSettle();
          expect(
            (await tester.runAsync(
              () => store.notifications.getUnreadCount(),
            ))!,
            before - 1,
          );
          expect(tester.takeException(), isNull);
          await _dispose(tester);
        },
        createHttpClient: (_) {
          networkClients++;
          throw StateError('Local demo attempted to create a network client.');
        },
      );
      expect(networkClients, 0);
    },
  );
}
