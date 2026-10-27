import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_order_identity.dart';

import 'mh09_test_support.dart';

void main() {
  testWidgets(
    'full canonical UUID is visible, semantic and available in tooltip',
    (tester) async {
      final order = mh09Order();
      await pumpMh09(tester, Mh09OrderIdentity(order: order));
      expect(find.text(order.id), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Mã đơn hàng: ${order.id}')),
        matchesSemantics(label: 'Mã đơn hàng: ${order.id}', isHeader: true),
      );
      expect(find.byTooltip(order.id), findsOneWidget);
      final style = tester.widget<Text>(find.text(order.id)).style!;
      expect(style.fontFamily, 'BarlowCondensed');
      expect(style.fontSize, 28);
      expect(style.fontWeight, FontWeight.w700);
      expect(find.textContaining('DH-'), findsNothing);
      expect(find.byType(IconButton), findsNothing);
    },
  );

  testWidgets('server UTC placed-at displays in Hanoi without device time', (
    tester,
  ) async {
    await pumpMh09(tester, Mh09OrderIdentity(order: mh09Order()));
    expect(find.text('Đặt lúc: 08/10/2026 10:32'), findsOneWidget);
    expect(find.textContaining('03:32'), findsNothing);
    expect(find.textContaining('Dự kiến'), findsNothing);
    expect(find.textContaining('Số lần giao'), findsNothing);
  });

  for (final entry in {
    OrderStatus.pendingConfirmation: 'Chờ xác nhận',
    OrderStatus.delivered: 'Đã giao hàng',
    OrderStatus.awaitingRedelivery: 'Chờ xử lý giao lại',
  }.entries) {
    testWidgets('renders current status ${entry.key.wireValue}', (
      tester,
    ) async {
      await pumpMh09(
        tester,
        Mh09OrderIdentity(order: mh09Order(status: entry.key)),
      );
      expect(find.text(entry.value), findsOneWidget);
      expect(find.textContaining('Phân công'), findsNothing);
    });
  }

  testWidgets('rebuild uses the new snapshot and recorded attempt count', (
    tester,
  ) async {
    await pumpMh09(tester, Mh09OrderIdentity(order: mh09Order(attempts: 1)));
    expect(find.text('Số lần giao đã ghi nhận: 1/2'), findsOneWidget);
    await pumpMh09(
      tester,
      Mh09OrderIdentity(
        order: mh09Order(status: OrderStatus.delivered, attempts: 2),
      ),
    );
    expect(find.text('Số lần giao đã ghi nhận: 2/2'), findsOneWidget);
    expect(find.text('Chờ xác nhận'), findsNothing);
    expect(find.text('Đã giao hàng'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('identity wraps at width$width scale$scale', (tester) async {
        final order = mh09Order(attempts: 2);
        await pumpMh09(
          tester,
          Mh09OrderIdentity(order: order),
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(
          find.bySemanticsLabel('Mã đơn hàng: ${order.id}'),
          findsOneWidget,
        );
        expect(find.text('Đặt lúc: 08/10/2026 10:32'), findsOneWidget);
        final text = tester.widget<Text>(find.text(order.id));
        expect(text.softWrap, isTrue);
        expect(text.maxLines, isNull);
      });
    }
  }
}
