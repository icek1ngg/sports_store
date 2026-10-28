import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_orders_page.dart';

import '../../../../../fixtures/order_list_page_fixtures.dart';
import 'mh08_page_test_support.dart';

void main() {
  testWidgets(
    'search and all ten server status filters reset to first cursor',
    (tester) async {
      final repository = OrderListFixtureRepository(
        managerPageLoader: (query) => listFixturePage(
          items: [
            listFixtureSummary(
              id: listFixtureOrderId,
              status: query.statuses.isEmpty
                  ? OrderStatus.pendingConfirmation
                  : query.statuses.single,
              capabilities: listFixtureCapabilities(
                canConfirm: true,
                canReject: true,
              ),
            ),
          ],
          totalCount: 1,
          counts: listFixtureCounts(pending: 1),
        ),
      );
      final container = createMh08Container(repository);
      await pumpMh08Page(
        tester,
        container,
        const ManagerOrdersPage(enablePolling: false),
      );
      repository.managerQueries.clear();
      await tester.enterText(find.byType(TextField), 'buyer');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(repository.managerQueries.last.search, 'buyer');
      for (final label in const [
        'Chờ xác nhận',
        'Đang chuẩn bị',
        'Chờ shipper nhận hàng',
        'Đang giao',
        'Chờ xử lý giao lại',
        'Chờ hàng về cửa hàng',
        'Đã giao hàng',
        'Đã hủy',
        'Đã từ chối',
        'Không giao được — đã nhận hàng về',
      ]) {
        expect(find.text(label), findsAtLeastNWidgets(1));
      }
      final deliveringFilter = find.widgetWithText(FilterChip, 'Đang giao');
      await tester.ensureVisible(deliveringFilter);
      await tester.tap(deliveringFilter);
      await tester.pumpAndSettle();
      expect(repository.managerQueries.last.statuses, [OrderStatus.delivering]);
      expect(repository.managerQueries.last.cursor, isNull);
      await finishMh08Test(tester, container);
    },
  );
}
