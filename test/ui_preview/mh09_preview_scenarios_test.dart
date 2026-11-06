import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_order_details_page.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_items_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_action_dialog.dart';
import 'package:sports_store/shared/widgets/async_content.dart';

import '../../tool/ui_preview/mh09_preview_scenario.dart';
import 'mh09_preview_test_support.dart';

const _longRecipient =
    'Người nhận hàng tại Trung tâm thể thao Thành phố Hà Nội, quầy số 12';
const _largeLastItem =
    'Bộ dụng cụ thể thao chuyên nghiệp phiên bản minh họa MH09 40';

void main() {
  testWidgets(
    'MH09 selector renders the forty-row world and can reach its last item',
    (tester) async {
      final environment = await openMh09PreviewOrder(tester, summaryIndex: 8);
      try {
        await selectMh09PreviewScenario(tester, Mh09PreviewScenario.large);
        expect(find.byType(ManagerOrderDetailsPage), findsOneWidget);
        expect(find.text(_longRecipient), findsOneWidget);
        expect(find.text('40 dòng sản phẩm'), findsOneWidget);
        expect(find.byType(Mh09ItemsSection), findsOneWidget);

        final lastItem = find.text(_largeLastItem);
        await tester.ensureVisible(lastItem);
        await tester.pumpAndSettle();
        expect(lastItem, findsOneWidget);
        expect(find.textContaining('kích thước tiêu chuẩn 40'), findsOneWidget);
        final history = find.text('Lịch sử đơn hàng');
        await tester.ensureVisible(history);
        await tester.pumpAndSettle();
        expect(history.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await disposeMh08Preview(tester, environment);
      }
    },
  );

  testWidgets('missing MH09 projections remain independent', (tester) async {
    final environment = await openMh09PreviewOrder(tester, summaryIndex: 4);
    try {
      await selectMh09PreviewScenario(
        tester,
        Mh09PreviewScenario.missingDelivery,
      );
      expect(find.text('Chưa có dữ liệu giao hàng'), findsOneWidget);
      expect(find.text('Chưa có dữ liệu COD'), findsNothing);
      expect(find.text('Vũ Gia Hân'), findsOneWidget);

      await selectMh09PreviewScenario(tester, Mh09PreviewScenario.missingCod);
      expect(find.text('Chưa có dữ liệu COD'), findsNWidgets(2));
      expect(find.text('Chưa có dữ liệu giao hàng'), findsNothing);
      expect(find.text('Vũ Gia Hân'), findsOneWidget);

      await selectMh09PreviewScenario(tester, Mh09PreviewScenario.missingBuyer);
      expect(find.text('Chưa có thông tin tài khoản'), findsOneWidget);
      expect(find.text('Chưa có dữ liệu giao hàng'), findsNothing);
      expect(find.text('Chưa có dữ liệu COD'), findsNothing);

      await selectMh09PreviewScenario(tester, Mh09PreviewScenario.normal);
      expect(find.text('Chờ duyệt'), findsOneWidget);
      await selectMh09PreviewScenario(tester, Mh09PreviewScenario.emptyReturns);
      expect(find.text('Chưa có dữ liệu yêu cầu trả hàng'), findsOneWidget);
      expect(find.text('Chưa có dữ liệu giao hàng'), findsNothing);
      expect(find.text('Chưa có dữ liệu COD'), findsNothing);
      expect(find.text('Vũ Gia Hân'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await disposeMh08Preview(tester, environment);
    }
  });

  testWidgets('error and stale scenarios keep a safe read-only snapshot', (
    tester,
  ) async {
    final environment = await openMh09PreviewOrder(tester);
    try {
      final orderId = environment.manager.summaries.first.order.id;
      await selectMh09PreviewScenario(tester, Mh09PreviewScenario.error);
      expect(find.text(orderId), findsOneWidget);
      expect(find.text('Dữ liệu có thể chưa cập nhật'), findsOneWidget);
      await tester.tap(find.byTooltip('Tải lại'));
      await tester.pumpAndSettle();
      expect(find.text(orderId), findsOneWidget);
      expect(find.text('Dữ liệu có thể chưa cập nhật'), findsNothing);

      await selectMh09PreviewScenario(tester, Mh09PreviewScenario.stale);
      expect(find.text(orderId), findsOneWidget);
      expect(find.text('Dữ liệu có thể chưa cập nhật'), findsOneWidget);
      final confirm = find.byKey(const ValueKey('mh09-action-confirm'));
      expect(confirm, findsOneWidget);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      expect(find.byType(OrderActionDialog), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await disposeMh08Preview(tester, environment);
    }
  });

  testWidgets('loading scenario is held by the explicit release gate', (
    tester,
  ) async {
    final environment = await openMh09PreviewOrder(tester);
    try {
      environment.mh09.holdLoading = true;
      await selectMh09PreviewScenario(
        tester,
        Mh09PreviewScenario.loading,
        settle: false,
      );
      expect(find.byTooltip('Đang tải lại'), findsOneWidget);
      expect(
        find.text(environment.manager.summaries.first.order.id),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      environment.mh09.releaseLoading();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Tải lại'), findsOneWidget);
      expect(find.text('Dữ liệu có thể chưa cập nhật'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await disposeMh08Preview(tester, environment);
    }
  });

  testWidgets(
    'expired, unauthorized and unresolved scenes do not read private data',
    (tester) async {
      for (final scenario in const [
        Mh09PreviewScenario.expired,
        Mh09PreviewScenario.unauthorized,
        Mh09PreviewScenario.unresolved,
      ]) {
        final environment = await openMh09PreviewOrder(tester);
        try {
          final orderId = environment.manager.summaries.first.order.id;
          final buyer =
              environment.manager.summaries.first.customerDisplayName!;
          final reads = environment.manager.managerDetailReads.length;
          await selectMh09PreviewScenario(
            tester,
            scenario,
            settle: scenario != Mh09PreviewScenario.unresolved,
          );
          if (scenario == Mh09PreviewScenario.unresolved) {
            await tester.pump();
          } else {
            await tester.pumpAndSettle();
          }
          expect(environment.manager.managerDetailReads.length, reads);
          expect(find.text(orderId), findsNothing);
          expect(find.text(buyer), findsNothing);
          expect(find.byKey(const ValueKey('mh09-items-card')), findsNothing);
          if (scenario == Mh09PreviewScenario.expired) {
            expect(find.byType(SessionExpiredState), findsOneWidget);
          } else if (scenario == Mh09PreviewScenario.unresolved) {
            expect(find.byType(LoadingState), findsOneWidget);
          } else {
            expect(find.byType(SessionUnavailableState), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await disposeMh08Preview(tester, environment);
        }
      }
    },
  );

  testWidgets(
    'held manager A loading cannot restore its forty-row world for B',
    (tester) async {
      final environment = await openMh09PreviewOrder(tester, summaryIndex: 8);
      try {
        await selectMh09PreviewScenario(tester, Mh09PreviewScenario.large);
        expect(find.text('40 dòng sản phẩm'), findsOneWidget);
        final container = previewContainer(tester);
        final oldCache = container.read(epochCacheProvider);
        environment.mh09.holdLoading = true;
        await selectMh09PreviewScenario(
          tester,
          Mh09PreviewScenario.loading,
          settle: false,
        );
        await selectMh09PreviewScenario(
          tester,
          Mh09PreviewScenario.accountSwitch,
          settleBefore: false,
        );
        final newCache = container.read(epochCacheProvider);
        expect(previewContainer(tester), same(container));
        expect(identical(newCache, oldCache), isFalse);
        expect(find.text('40 dòng sản phẩm'), findsNothing);
        expect(find.text(_largeLastItem), findsNothing);
        expect(find.text('1 dòng sản phẩm'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await disposeMh08Preview(tester, environment);
      }
    },
  );

  testWidgets(
    'confirm and reject preview commands repeat validation and fail closed',
    (tester) async {
      final environment = await openMh09PreviewOrder(tester);
      try {
        for (var cycle = 0; cycle < 2; cycle++) {
          await selectMh09PreviewScenario(
            tester,
            Mh09PreviewScenario.confirmOnly,
          );
          await tester.tap(find.byKey(const ValueKey('mh09-action-confirm')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('order-action-submit')));
          await tester.pump();
          expect(
            find.text('Thao tác hiện chưa khả dụng. Vui lòng thử lại sau.'),
            findsOneWidget,
          );
          await tester.tap(find.text('Đóng'));
          await tester.pumpAndSettle();

          await selectMh09PreviewScenario(
            tester,
            Mh09PreviewScenario.rejectOnly,
          );
          await tester.tap(find.byKey(const ValueKey('mh09-action-reject')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('order-action-submit')));
          await tester.pump();
          expect(
            find.text('Vui lòng nhập lý do trước khi gửi.'),
            findsOneWidget,
          );
          await tester.enterText(
            find.byKey(const ValueKey('order-action-reason')),
            'Lý do preview $cycle',
          );
          await tester.tap(find.byKey(const ValueKey('order-action-submit')));
          await tester.pump();
          expect(
            find.text('Thao tác hiện chưa khả dụng. Vui lòng thử lại sau.'),
            findsOneWidget,
          );
          await tester.tap(find.text('Đóng'));
          await tester.pumpAndSettle();
        }

        await selectMh09PreviewScenario(
          tester,
          Mh09PreviewScenario.confirmOnly,
        );
        await tester.tap(find.byKey(const ValueKey('mh09-action-confirm')));
        await tester.pumpAndSettle();
        environment.selectMh09Scenario(Mh09PreviewScenario.commandsDenied);
        await tester.pumpAndSettle();
        expect(
          find.text('Dữ liệu đã thay đổi. Làm mới trước khi tiếp tục.'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('order-action-submit')),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.text('Đóng'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        await disposeMh08Preview(tester, environment);
      }
    },
  );

  testWidgets('expiry while reject dialog is open clears its private reason', (
    tester,
  ) async {
    final environment = await openMh09PreviewOrder(tester);
    try {
      await selectMh09PreviewScenario(tester, Mh09PreviewScenario.rejectOnly);
      await tester.tap(find.byKey(const ValueKey('mh09-action-reject')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('order-action-reason')),
        'Lý do nội bộ cần xóa',
      );
      environment.selectMh09Scenario(Mh09PreviewScenario.expired);
      await tester.pumpAndSettle();
      expect(find.text('Lý do nội bộ cần xóa'), findsNothing);
      expect(find.text('Không thể tiếp tục thao tác'), findsOneWidget);
      expect(
        find.text(environment.manager.summaries.first.order.id),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('mh09-items-card')), findsNothing);
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
      expect(find.byType(SessionExpiredState), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await disposeMh08Preview(tester, environment);
    }
  });
}
