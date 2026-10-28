import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sports_store/features/orders/presentation/pages/manager_orders_page.dart';

import '../../../../../fixtures/order_list_page_fixtures.dart';
import 'mh08_page_test_support.dart';

void main() {
  testWidgets(
    'confirm and reject use validation dialog and do not dispatch repository mutation',
    (tester) async {
      final repository = OrderListFixtureRepository(
        managerPage: listFixturePage(
          counts: listFixtureCounts(pending: 1),
          items: [
            listFixtureSummary(
              capabilities: listFixtureCapabilities(
                canConfirm: true,
                canReject: true,
              ),
            ),
          ],
        ),
      );
      final container = createMh08Container(repository);
      await pumpMh08Page(
        tester,
        container,
        const ManagerOrdersPage(enablePolling: false),
      );
      await tester.ensureVisible(find.text('Xác nhận').first);
      await tester.drag(find.byType(ListView).last, const Offset(0, -420));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xác nhận').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('order-action-submit')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('order-action-submit')));
      await tester.pump();
      expect(
        find.text('Thao tác hiện chưa khả dụng. Vui lòng thử lại sau.'),
        findsOneWidget,
      );
      expect(repository.managerQueries.length, 1);
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Từ chối').first);
      await tester.tap(find.text('Từ chối').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('order-action-reason')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('order-action-submit')));
      await tester.pump();
      expect(find.text('Vui lòng nhập lý do trước khi gửi.'), findsOneWidget);
      await finishMh08Test(tester, container);
    },
  );

  testWidgets(
    'detail callback is visibly unavailable when router does not provide one',
    (tester) async {
      final repository = OrderListFixtureRepository(
        managerPage: listFixturePage(),
      );
      final container = createMh08Container(repository);
      await pumpMh08Page(
        tester,
        container,
        const ManagerOrdersPage(enablePolling: false),
      );
      expect(find.text('Chi tiết chưa khả dụng'), findsOneWidget);
      await finishMh08Test(tester, container);
    },
  );
}
