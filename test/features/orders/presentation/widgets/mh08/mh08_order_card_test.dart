import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/utils/display_formatters.dart';
import 'package:sports_store/features/orders/domain/models/order_item.dart';
import 'package:sports_store/features/orders/domain/models/order_summary.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_order_card.dart';

import 'mh08_test_support.dart';

void main() {
  testWidgets('card preserves UUID, server time and independent status label', (
    tester,
  ) async {
    final summary = mh08Summary();
    final semantics = tester.ensureSemantics();
    try {
      await pumpMh08(
        tester,
        Mh08OrderCard(
          summary: summary,
          isFresh: true,
          showDecisionActions: false,
        ),
      );
      expect(find.text(summary.order.id), findsOneWidget);
      expect(find.byTooltip(summary.order.id), findsOneWidget);
      expect(
        find.bySemanticsLabel('Đơn hàng ${summary.order.id}'),
        findsOneWidget,
      );
      expect(
        find.text(formatHanoiDateTime(summary.order.placedAt)),
        findsOneWidget,
      );
      expect(find.text('08/10/2026 10:32'), findsOneWidget);
      expect(find.text(orderStatusLabel(summary.order.status)), findsOneWidget);
      expect(find.textContaining('DH-'), findsNothing);
      expect(find.byKey(const ValueKey('mh08-confirm')), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'card renders every supplied snapshot and keeps aggregate quantity in payment',
    (tester) async {
      final base = mh08Summary();
      final first = base.itemPreview.single;
      final second = OrderItem(
        id: '00000000-0000-0000-0000-000000000002',
        orderId: first.orderId,
        productId: '00000000-0000-0000-0000-000000000003',
        variantId: '00000000-0000-0000-0000-000000000004',
        productName: 'Bóng đá sân cỏ fixture',
        variantLabel: 'Trắng / 5',
        attributes: const {},
        unitPriceVnd: 100000,
        quantity: 2,
        lineTotalVnd: 200000,
        createdAt: first.createdAt,
      );
      final summary = OrderSummary(
        order: base.order,
        itemPreview: [first, second],
        itemLineCount: 2,
        itemQuantityTotal: 3,
        customerDisplayName: base.customerDisplayName,
        deliverySummary: base.deliverySummary,
        codSummary: base.codSummary,
        returnSummary: base.returnSummary,
        warnings: base.warnings,
        capabilities: base.capabilities,
      );
      final semantics = tester.ensureSemantics();
      try {
        await pumpMh08(
          tester,
          Mh08OrderCard(
            summary: summary,
            isFresh: true,
            showDecisionActions: true,
            canConfirm: true,
            canReject: true,
            onConfirm: () {},
            onReject: () {},
          ),
        );
        expect(find.text(first.productName), findsOneWidget);
        expect(find.text(second.productName), findsOneWidget);
        expect(find.text('Biến thể: ${first.variantLabel}'), findsOneWidget);
        expect(find.text('Số lượng: ${first.quantity}'), findsOneWidget);
        expect(find.text('Biến thể: ${second.variantLabel}'), findsOneWidget);
        expect(find.text('Số lượng: ${second.quantity}'), findsOneWidget);
        expect(find.text('3 sản phẩm'), findsOneWidget);
        expect(find.text(summary.order.recipientName), findsOneWidget);
        expect(find.text(summary.order.addressDetail), findsOneWidget);
        expect(find.text(summary.order.recipientPhone), findsOneWidget);
        expect(
          find.bySemanticsLabel('Không có ảnh sản phẩm'),
          findsNWidgets(2),
        );
        expect(
          find.bySemanticsLabel('Đơn hàng ${summary.order.id}'),
          findsOneWidget,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('compact card keeps decision and detail hit targets at scale 2', (
    tester,
  ) async {
    await pumpMh08(
      tester,
      Mh08OrderCard(
        summary: mh08Summary(),
        isFresh: true,
        showDecisionActions: true,
        canConfirm: true,
        canReject: true,
        onConfirm: () {},
        onReject: () {},
        onOpenOrder: () {},
      ),
      width: 320,
      scale: 2,
    );
    for (final key in ['mh08-reject', 'mh08-confirm', 'mh08-open-order']) {
      final finder = find.byKey(ValueKey(key));
      await tester.ensureVisible(finder);
      final size = tester.getSize(finder);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('header reflows every order status at compact widths', (
    tester,
  ) async {
    Future<void> pumpStatusMatrix({
      required double width,
      required double scale,
    }) async {
      await pumpMh08(
        tester,
        Column(
          children: [
            for (final status in OrderStatus.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Mh08OrderCard(
                  summary: mh08Summary(status: status),
                  isFresh: true,
                  showDecisionActions: false,
                ),
              ),
          ],
        ),
        width: width,
        scale: scale,
      );
      expect(tester.takeException(), isNull);
      for (final status in OrderStatus.values) {
        expect(find.text(orderStatusLabel(status)), findsOneWidget);
      }
    }

    await pumpStatusMatrix(width: 390, scale: 1);
    await pumpStatusMatrix(width: 320, scale: 2);
  });

  testWidgets(
    'card trusts supplied eligibility rather than domain status/capability',
    (tester) async {
      var confirms = 0;
      final summary = mh08Summary(status: OrderStatus.delivered);
      expect(summary.capabilities.canConfirm, isFalse);
      await pumpMh08(
        tester,
        Mh08OrderCard(
          summary: summary,
          isFresh: true,
          showDecisionActions: true,
          canConfirm: true,
          onConfirm: () => confirms++,
        ),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('mh08-confirm')));
      await tester.tap(find.byKey(const ValueKey('mh08-confirm')));
      expect(confirms, 1);
    },
  );

  testWidgets(
    'pending card without supplied eligibility never enables decisions',
    (tester) async {
      var calls = 0;
      await pumpMh08(
        tester,
        Mh08OrderCard(
          summary: mh08Summary(),
          isFresh: true,
          showDecisionActions: true,
          onConfirm: () => calls++,
          onReject: () => calls++,
        ),
      );
      for (final key in ['mh08-confirm', 'mh08-reject']) {
        final finder = find.byKey(ValueKey(key));
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        expect(tester.widget<FilledButton>(finder).onPressed, isNull);
      }
      expect(calls, 0);
    },
  );

  testWidgets('freshness blocks decisions, detail remains parent-controlled', (
    tester,
  ) async {
    var decisions = 0;
    var opened = 0;
    await pumpMh08(
      tester,
      Mh08OrderCard(
        summary: mh08Summary(),
        isFresh: false,
        showDecisionActions: true,
        canConfirm: true,
        canReject: true,
        onConfirm: () => decisions++,
        onReject: () => decisions++,
        onOpenOrder: () => opened++,
      ),
    );
    expect(find.text('Dữ liệu có thể chưa cập nhật'), findsOneWidget);
    final confirm = find.byKey(const ValueKey('mh08-confirm'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    final detail = find.byKey(const ValueKey('mh08-open-order'));
    await tester.ensureVisible(detail);
    await tester.tap(detail);
    expect(decisions, 0);
    expect(opened, 1);
  });

  for (final gate in ['missing', 'disabled', 'busy']) {
    testWidgets('$gate detail callback is disabled and visibly unavailable', (
      tester,
    ) async {
      var calls = 0;
      await pumpMh08(
        tester,
        Mh08OrderCard(
          summary: mh08Summary(),
          isFresh: true,
          showDecisionActions: false,
          enabled: gate != 'disabled',
          isBusy: gate == 'busy',
          onOpenOrder: gate == 'missing' ? null : () => calls++,
        ),
      );
      final detail = find.byKey(const ValueKey('mh08-open-order'));
      await tester.ensureVisible(detail);
      expect(find.text('Chi tiết chưa khả dụng'), findsOneWidget);
      final reason = switch (gate) {
        'missing' => 'Chi tiết đơn hàng hiện chưa khả dụng',
        'disabled' => 'Chi tiết đơn hàng hiện không khả dụng',
        _ => 'Đang xử lý đơn hàng',
      };
      expect(find.byTooltip(reason), findsOneWidget);
      if (gate == 'busy') {
        expect(find.text('Đang xử lý đơn hàng'), findsOneWidget);
      }
      await tester.tap(detail);
      expect(calls, 0);
      expect(tester.widget<OutlinedButton>(detail).onPressed, isNull);
    });
  }

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('long Vietnamese card fits width$width scale$scale', (
        tester,
      ) async {
        await pumpMh08(
          tester,
          Mh08OrderCard(
            summary: mh08Summary(
              longText: true,
              accountName: 'Tên tài khoản tiếng Việt rất dài ' * 4,
              status: OrderStatus.undeliverableReturned,
            ),
            isFresh: true,
            showDecisionActions: true,
            canConfirm: true,
            canReject: true,
            onConfirm: () {},
            onReject: () {},
          ),
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const ValueKey('mh08-confirm')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(Mh08OrderCard)).width, width - 40);
      });
    }
  }
}
