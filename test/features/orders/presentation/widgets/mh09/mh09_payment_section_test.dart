import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_payment_section.dart';

import 'mh09_02b_test_support.dart';

void main() {
  testWidgets('renders the exact financial snapshot without promotions', (
    tester,
  ) async {
    final order = mh09FinancialOrder();
    await pumpMh09(tester, Mh09PaymentSection(order: order));
    expect(find.text('3.450.000 ₫'), findsOneWidget);
    expect(find.text('30.000 ₫'), findsOneWidget);
    expect(find.text('3.480.000 ₫'), findsOneWidget);
    expect(find.text('Thanh toán khi nhận hàng (COD)'), findsOneWidget);
    for (final unsupported in [
      'Khuyến mãi',
      'Voucher',
      'Giảm giá',
      'Miễn phí',
    ]) {
      expect(find.textContaining(unsupported), findsNothing);
    }
    final style = tester.widget<Text>(find.text('3.480.000 ₫')).style!;
    expect(style.fontFamily, 'BarlowCondensed');
    expect(style.fontSize, 32);
    expect(style.fontWeight, FontWeight.w700);
  });

  testWidgets('null COD remains unknown even when order is delivered', (
    tester,
  ) async {
    await pumpMh09(
      tester,
      Mh09PaymentSection(
        order: mh09FinancialOrder(status: OrderStatus.delivered),
      ),
    );
    expect(find.text('Chưa có dữ liệu COD'), findsOneWidget);
    for (final fabricated in [
      'Chưa thu',
      'Shipper đã thu',
      'Cửa hàng đã nhận',
    ]) {
      expect(find.text('Trạng thái COD: $fabricated'), findsNothing);
    }
    expect(find.text('0 ₫'), findsNothing);
    expect(find.textContaining('Đã thu từ khách'), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  for (final entry in {
    CodStatus.uncollected: 'Chưa thu',
    CodStatus.collected: 'Shipper đã thu',
    CodStatus.received: 'Cửa hàng đã nhận',
  }.entries) {
    testWidgets('uses authoritative COD ${entry.key.wireValue} only', (
      tester,
    ) async {
      final order = mh09FinancialOrder(status: OrderStatus.delivered);
      await pumpMh09(
        tester,
        Mh09PaymentSection(
          order: order,
          codSummary: mh09Cod(order, status: entry.key),
        ),
      );
      expect(find.text('Trạng thái COD: ${entry.value}'), findsOneWidget);
      expect(find.text('Chưa có dữ liệu COD'), findsNothing);
      expect(find.text('3.480.000 ₫'), findsOneWidget);
      expect(find.textContaining('Hoàn tiền'), findsNothing);
    });
  }

  testWidgets('large integer amounts are exact and fully accessible', (
    tester,
  ) async {
    final order = mh09FinancialOrder(subtotalVnd: 999999999999999);
    await pumpMh09(
      tester,
      Mh09PaymentSection(order: order),
      width: 320,
      scale: 2,
    );
    expect(find.text('999.999.999.999.999 ₫'), findsOneWidget);
    const total = '1.000.000.000.029.999 ₫';
    expect(find.text(total), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Tổng COD: $total')),
      matchesSemantics(label: 'Tổng COD: $total'),
    );
    expect(tester.widget<Text>(find.text(total)).maxLines, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('real zero subtotal is rendered without changing the order fee', (
    tester,
  ) async {
    await pumpMh09(
      tester,
      Mh09PaymentSection(order: mh09FinancialOrder(subtotalVnd: 0)),
    );
    expect(find.text('0 ₫'), findsOneWidget);
    expect(find.text('30.000 ₫'), findsNWidgets(2));
    expect(find.text('Chưa có dữ liệu COD'), findsOneWidget);
  });

  testWidgets(
    'new inputs replace the old snapshot without local financial state',
    (tester) async {
      final first = mh09FinancialOrder();
      await pumpMh09(
        tester,
        Mh09PaymentSection(
          order: first,
          codSummary: mh09Cod(first, status: CodStatus.collected),
        ),
      );
      await pumpMh09(
        tester,
        Mh09PaymentSection(order: mh09FinancialOrder(subtotalVnd: 120000)),
      );
      expect(find.text('3.480.000 ₫'), findsNothing);
      expect(find.text('150.000 ₫'), findsOneWidget);
      expect(find.text('Trạng thái COD: Shipper đã thu'), findsNothing);
      expect(find.text('Chưa có dữ liệu COD'), findsOneWidget);
    },
  );

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('payment fits width$width scale$scale with full semantics', (
        tester,
      ) async {
        await pumpMh09(
          tester,
          Mh09PaymentSection(order: mh09FinancialOrder()),
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
        for (final label in [
          'Tạm tính: 3.450.000 ₫',
          'Phí giao hàng: 30.000 ₫',
          'Tổng COD: 3.480.000 ₫',
        ]) {
          expect(find.bySemanticsLabel(label), findsOneWidget);
        }
      });
    }
  }
}
