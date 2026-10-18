import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_order_details_page.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_orders_page.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_order_card.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_feed.dart';
import 'package:sports_store/shared/widgets/async_content.dart';

import '../../tool/ui_preview/mh08_manager_repository.dart';
import '../../tool/ui_preview/mh08_preview_environment.dart';

import 'mh08_preview_test_support.dart';

void main() {
  testWidgets('all MH08 scenarios expose safe states and recover to data', (
    tester,
  ) async {
    final environment = Mh08PreviewEnvironment();
    try {
      await pumpMh08Preview(tester, environment);
      await selectPreviewScreen(tester, 'MH08');
      await tester.pumpAndSettle();

      for (final scenario in Mh08PreviewScenario.values) {
        environment.selectScenario(scenario);
        await tester.pump();
        switch (scenario) {
          case Mh08PreviewScenario.data:
            await tester.pumpAndSettle();
            expect(find.byType(Mh08OrderCard), findsAtLeastNWidgets(1));
          case Mh08PreviewScenario.loading:
            await tester.pump(const Duration(milliseconds: 799));
            expect(find.byType(Mh08OrderCard), findsNothing);
            expect(find.byType(LoadingState), findsOneWidget);
            await tester.pump(const Duration(milliseconds: 1));
            await tester.pumpAndSettle();
            expect(find.byType(Mh08OrderCard), findsAtLeastNWidgets(1));
          case Mh08PreviewScenario.empty:
            await tester.pumpAndSettle();
            expect(find.text('Chưa có đơn hàng cần xử lý'), findsOneWidget);
            expect(find.byType(Mh08OrderCard), findsNothing);
          case Mh08PreviewScenario.error:
            await tester.pumpAndSettle();
            expect(find.byType(ErrorState), findsOneWidget);
            expect(find.byType(Mh08OrderCard), findsNothing);
          case Mh08PreviewScenario.stale:
            await tester.pump(const Duration(seconds: 1));
            await tester.pumpAndSettle();
            expect(
              find.text('Dữ liệu có thể chưa cập nhật'),
              findsAtLeastNWidgets(1),
            );
            expect(find.byType(Mh08OrderCard), findsAtLeastNWidgets(1));
          case Mh08PreviewScenario.expired:
            await tester.pumpAndSettle();
            expect(find.byType(SessionExpiredState), findsOneWidget);
            expect(find.byType(Mh08OrderCard), findsNothing);
          case Mh08PreviewScenario.unauthorized:
            await tester.pumpAndSettle();
            expect(find.byType(SessionUnavailableState), findsOneWidget);
            expect(find.byType(Mh08OrderCard), findsNothing);
          case Mh08PreviewScenario.sessionUnavailable:
            await tester.pump(const Duration(milliseconds: 100));
            expect(find.byType(LoadingState), findsOneWidget);
            expect(
              find.bySemanticsLabel('Đang xác nhận phiên đăng nhập'),
              findsOneWidget,
            );
            expect(find.byType(Mh08OrderCard), findsNothing);
        }
        expect(tester.takeException(), isNull);

        if (scenario != Mh08PreviewScenario.data) {
          environment.selectScenario(Mh08PreviewScenario.data);
          await tester.pumpAndSettle();
          expect(find.byType(Mh08OrderCard), findsAtLeastNWidgets(1));
        }
      }
    } finally {
      await disposeMh08Preview(tester, environment);
    }
  });

  testWidgets(
    'generation change during loading cannot restore old private rows',
    (tester) async {
      final environment = Mh08PreviewEnvironment();
      try {
        await pumpMh08Preview(tester, environment);
        await selectPreviewScreen(tester, 'MH08');
        await tester.pumpAndSettle();

        environment.selectScenario(Mh08PreviewScenario.loading);
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(Mh08OrderCard), findsNothing);

        environment.selectScenario(Mh08PreviewScenario.unauthorized);
        await tester.pump();
        expect(find.byType(Mh08OrderCard), findsNothing);
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pumpAndSettle();
        expect(find.byType(Mh08OrderCard), findsNothing);
        expect(find.text('Nguyễn Minh Anh'), findsNothing);
        expect(tester.takeException(), isNull);

        environment.selectScenario(Mh08PreviewScenario.data);
        await tester.pumpAndSettle();
        expect(find.byType(Mh08OrderCard), findsAtLeastNWidgets(1));
      } finally {
        await disposeMh08Preview(tester, environment);
      }
    },
  );

  testWidgets('confirm and reject dialogs remain unavailable and fail closed', (
    tester,
  ) async {
    final environment = Mh08PreviewEnvironment();
    try {
      await pumpMh08Preview(tester, environment);
      await selectPreviewScreen(tester, 'MH08');
      await tester.pumpAndSettle();

      await openManagerConfirm(tester);
      await tester.tap(find.byKey(const ValueKey('order-action-submit')));
      await tester.pumpAndSettle();
      expect(
        find.text('Thao tác hiện chưa khả dụng. Vui lòng thử lại sau.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();

      for (var index = 0; index < 2; index++) {
        await openManagerConfirm(tester);
        expect(find.text('Xác nhận đơn hàng'), findsOneWidget);
        await tester.tap(find.text('Đóng'));
        await tester.pumpAndSettle();

        await openManagerReject(tester);
        expect(find.text('Từ chối đơn hàng'), findsOneWidget);
        await tester.tap(find.text('Đóng'));
        await tester.pumpAndSettle();
      }

      await openManagerReject(tester);
      await tester.tap(find.byKey(const ValueKey('order-action-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Vui lòng nhập lý do trước khi gửi.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('order-action-reason')),
        'Cần kiểm tra lại thông tin đơn.',
      );
      await tester.tap(find.byKey(const ValueKey('order-action-submit')));
      await tester.pumpAndSettle();
      expect(
        find.text('Thao tác hiện chưa khả dụng. Vui lòng thử lại sau.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    } finally {
      await disposeMh08Preview(tester, environment);
    }
  });

  testWidgets('expiry while a modal is open clears private dialog content', (
    tester,
  ) async {
    final environment = Mh08PreviewEnvironment();
    try {
      await pumpMh08Preview(tester, environment);
      await selectPreviewScreen(tester, 'MH08');
      await tester.pumpAndSettle();
      await openManagerReject(tester);
      await tester.enterText(
        find.byKey(const ValueKey('order-action-reason')),
        'Private reason',
      );

      environment.selectScenario(Mh08PreviewScenario.expired);
      await tester.pump();
      expect(find.text('Private reason'), findsNothing);
      expect(find.text('Không thể tiếp tục thao tác'), findsOneWidget);
      expect(find.byType(Mh08OrderCard), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
      environment.selectScenario(Mh08PreviewScenario.data);
      await tester.pumpAndSettle();
      expect(find.byType(Mh08OrderCard), findsAtLeastNWidgets(1));
    } finally {
      await disposeMh08Preview(tester, environment);
    }
  });

  testWidgets(
    'MH09 detail keeps exact UUID and refreshes only canonical head',
    (tester) async {
      final environment = Mh08PreviewEnvironment();
      try {
        await pumpMh08Preview(tester, environment);
        await selectPreviewScreen(tester, 'MH08');
        await tester.pumpAndSettle();
        await loadManagerNextPage(tester, environment);

        final headBefore = environment.manager.managerReads
            .where((query) => query.cursor == null)
            .length;
        final canonicalQuery = environment.manager.managerReads
            .where((query) => query.cursor == null)
            .last;
        final nextBefore = environment.manager.managerReads
            .where((query) => query.cursor != null)
            .length;
        final visibleCard = find.byType(Mh08OrderCard).first;
        final firstId = tester
            .widget<Mh08OrderCard>(visibleCard)
            .summary
            .order
            .id;

        await openManagerDetails(tester);
        await tester.pumpAndSettle();
        expect(find.byType(ManagerOrderDetailsPage), findsOneWidget);
        expect(environment.manager.managerDetailReads.last, firstId);
        expect(find.text('Đơn hàng $firstId'), findsOneWidget);
        final headAfterDetail = environment.manager.managerReads
            .where((query) => query.cursor == null)
            .length;
        final nextAfterDetail = environment.manager.managerReads
            .where((query) => query.cursor != null)
            .length;

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(ManagerOrdersPage), findsOneWidget);
        final headAfter = environment.manager.managerReads
            .where((query) => query.cursor == null)
            .length;
        final nextAfter = environment.manager.managerReads
            .where((query) => query.cursor != null)
            .length;
        expect(headAfter, headAfterDetail + 1);
        expect(nextAfter, nextAfterDetail);
        expect(headAfterDetail, greaterThanOrEqualTo(headBefore));
        expect(nextAfterDetail, nextBefore);
        expect(
          environment.manager.managerReads
              .where((query) => query.cursor == null)
              .last,
          canonicalQuery,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await disposeMh08Preview(tester, environment);
      }
    },
  );

  testWidgets('next page failure renders retry and retry succeeds', (
    tester,
  ) async {
    final environment = Mh08PreviewEnvironment();
    try {
      await pumpMh08Preview(tester, environment);
      await selectPreviewScreen(tester, 'MH08');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('DEMO: lỗi trang tiếp theo'));
      await tester.pumpAndSettle();

      await loadManagerNextPage(tester, environment);
      expect(
        find.text('Không thể kết nối. Kiểm tra mạng và thử lại.'),
        findsOneWidget,
      );
      final retry = find.text('Tải lại trang tiếp theo');
      await ensureVisibleInList(tester, retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(retry, findsNothing);
      final orders = tester.widget<OrderFeed>(find.byType(OrderFeed)).orders;
      expect(orders, hasLength(6));
      expect(orders.map((summary) => summary.order.id).toSet(), hasLength(6));
      expect(tester.takeException(), isNull);
    } finally {
      await disposeMh08Preview(tester, environment);
    }
  });
}
