import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_orders_page.dart';
import 'package:sports_store/shared/widgets/async_content.dart';

import '../../../../../fixtures/order_list_page_fixtures.dart';
import 'mh08_page_test_support.dart';

void main() {
  testWidgets('retains manager rows after a failed next page', (tester) async {
    var nextReads = 0;
    var allowRetry = false;
    final second = listFixtureSummary(
      id: listFixtureSecondOrderId,
      status: OrderStatus.preparing,
    );
    final repository = OrderListFixtureRepository(
      managerPageLoader: (query) {
        if (query.cursor != null) {
          nextReads++;
          if (!allowRetry) {
            throw const AppFailure(
              code: AppFailure.externalDependencyUnavailable,
            );
          }
          return listFixturePage(items: [second], totalCount: 5);
        }
        return listFixturePage(
          nextCursor: 'cursor-manager',
          totalCount: 5,
          counts: listFixtureCounts(pending: 5),
        );
      },
    );
    final container = createMh08Container(repository);
    await pumpMh08Page(
      tester,
      container,
      const ManagerOrdersPage(enablePolling: false),
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -420));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(nextReads, 1);
    expect(find.text(listFixtureOrderId), findsOneWidget);
    expect(find.text('Tải lại trang tiếp theo'), findsOneWidget);
    allowRetry = true;
    await tester.tap(find.text('Tải lại trang tiếp theo'));
    await tester.pumpAndSettle();
    expect(nextReads, 2);
    expect(find.text(listFixtureSecondOrderId), findsOneWidget);
    await finishMh08Test(tester, container);
  });

  testWidgets('clears manager rows when the next page loses private access', (
    tester,
  ) async {
    final repository = OrderListFixtureRepository(
      managerPageLoader: (query) {
        if (query.cursor != null) {
          throw const AppFailure(code: AppFailure.unauthenticated);
        }
        return listFixturePage(
          items: [
            listFixtureSummary(
              capabilities: listFixtureCapabilities(
                canConfirm: true,
                canReject: true,
              ),
            ),
          ],
          nextCursor: 'cursor-private',
          counts: listFixtureCounts(pending: 1),
        );
      },
    );
    final container = createMh08Container(repository);
    await pumpMh08Page(
      tester,
      container,
      const ManagerOrdersPage(enablePolling: false),
    );

    await requestMh08LoadMoreIfVisible(tester);
    await tester.pump();
    await tester.pump();

    expect(find.byType(SessionExpiredState), findsOneWidget);
    expect(find.text(listFixtureOrderId), findsNothing);
    expect(find.text('1 đơn hàng'), findsNothing);
    expect(find.text('Xác nhận'), findsNothing);
    expect(find.text('Từ chối'), findsNothing);
    expect(find.text('Tải lại trang tiếp theo'), findsNothing);
    await finishMh08Test(tester, container);
  });

  testWidgets('resets an invalid manager cursor to the canonical head', (
    tester,
  ) async {
    var canonicalReads = 0;
    final repository = OrderListFixtureRepository(
      managerPageLoader: (query) {
        if (query.cursor != null) {
          throw const AppFailure(code: AppFailure.invalidCursor);
        }
        canonicalReads++;
        return listFixturePage(
          nextCursor: canonicalReads == 1 ? 'cursor-invalid' : null,
        );
      },
    );
    final container = createMh08Container(repository);
    await pumpMh08Page(
      tester,
      container,
      const ManagerOrdersPage(enablePolling: false),
    );

    await requestMh08LoadMoreIfVisible(tester);

    expect(
      repository.managerQueries.where((query) => query.cursor != null),
      hasLength(1),
    );
    expect(repository.managerQueries.last.cursor, isNull);
    await finishMh08Test(tester, container);
  });

  testWidgets('keeps manager pagination enabled for an identical refresh', (
    tester,
  ) async {
    final page = listFixturePage(nextCursor: 'cursor-same');
    final repository = OrderListFixtureRepository(
      managerPageLoader: (query) {
        if (query.cursor != null) {
          throw const AppFailure(
            code: AppFailure.externalDependencyUnavailable,
          );
        }
        return page;
      },
    );
    final container = createMh08Container(repository);
    await pumpMh08Page(
      tester,
      container,
      const ManagerOrdersPage(enablePolling: false),
    );
    await requestMh08LoadMoreIfVisible(tester);
    expect(find.text('Tải lại trang tiếp theo'), findsOneWidget);

    await tester.tap(find.byTooltip('Làm mới đơn hàng'));
    await tester.pumpAndSettle();

    await requestMh08LoadMoreIfVisible(tester);

    expect(find.text('Tải lại trang tiếp theo'), findsOneWidget);
    await finishMh08Test(tester, container);
  });
}
