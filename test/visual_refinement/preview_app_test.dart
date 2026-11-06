import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/domain/models/order_command.dart';
import 'package:sports_store/features/orders/domain/models/order_query.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/notifications/presentation/widgets/unread_badge.dart';
import 'package:sports_store/features/orders/presentation/pages/customer_orders_page.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_orders_page.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_order_details_page.dart';
import 'package:sports_store/features/notifications/presentation/pages/notifications_page.dart';

import '../../tool/ui_preview/preview_app.dart';
import '../fixtures/order_list_page_fixtures.dart';

void main() {
  testWidgets('debug preview switches screens through isolated fixture DI', (
    tester,
  ) async {
    await tester.pumpWidget(const UiPreviewApp());
    await tester.pumpAndSettle();
    expect(find.byType(CustomerOrdersPage), findsOneWidget);
    for (final screen in ['MH08', 'MH09', 'MH17']) {
      await tester.tap(find.byTooltip('Chọn màn hình'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(screen));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('DEMO UI · dữ liệu kiểm thử'), findsOneWidget);
      expect(
        find.byType(switch (screen) {
          'MH08' => ManagerOrdersPage,
          'MH09' => ManagerOrderDetailsPage,
          _ => NotificationsPage,
        }),
        findsOneWidget,
      );
    }
    await tester.tap(find.byTooltip('Chọn trạng thái'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('expired'));
    await tester.pumpAndSettle();
    expect(find.text('Đơn hàng đã được xác nhận'), findsNothing);
    expect(find.byType(UnreadBadge), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('server unread badge stays compact inside a tall toolbar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            toolbarHeight: 64,
            actions: const [Center(child: UnreadBadge(count: 124))],
          ),
        ),
      ),
    );
    final badge = find.byType(UnreadBadge);
    expect(tester.getSize(badge).height, lessThan(40));
    expect(find.text('99+'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('124 thông báo chưa đọc'), findsOneWidget);
    semantics.dispose();
  });

  test(
    'MH07 preview data supports filtering, pagination and simulated cancel',
    () async {
      final repository = PreviewOrderRepository();

      final first = await repository.getCustomerOrders(OrderQuery());
      expect(first.totalCount, 16);
      expect(first.items, hasLength(4));
      expect(first.nextCursor, '4');
      expect(
        first.items.first.itemLineCount,
        greaterThan(1),
        reason: 'The first demo order intentionally has multiple item lines.',
      );

      final second = await repository.getCustomerOrders(
        OrderQuery(cursor: first.nextCursor),
      );
      expect(second.items, hasLength(4));
      expect(second.items.first.order.id, isNot(first.items.first.order.id));

      final delivered = await repository.getCustomerOrders(
        OrderQuery(statuses: [OrderStatus.delivered]),
      );
      expect(delivered.items, isNotEmpty);
      expect(
        delivered.items.every(
          (row) => row.order.status == OrderStatus.delivered,
        ),
        isTrue,
      );

      final search = await repository.getCustomerOrders(
        OrderQuery(search: 'AirFlex'),
      );
      expect(search.items, hasLength(1));
      expect(search.items.single.order.id, listFixtureOrderId);

      final command = StableOrderCommand(
        orderId: listFixtureOrderId,
        requestId: '30000000-0000-4000-8000-000000000099',
        operation: OrderOperation.customerCancel,
      );
      final receipt = await repository.cancelCustomer(command);
      expect(receipt.order.status, OrderStatus.cancelled);
      final cancelled = await repository.getCustomerOrders(
        OrderQuery(statuses: [OrderStatus.cancelled]),
      );
      expect(
        cancelled.items.any((row) => row.order.id == listFixtureOrderId),
        isTrue,
      );
    },
  );
}
