import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/returns/domain/models/return_reason.dart';
import 'package:sports_store/features/returns/presentation/pages/create_return_page.dart';
import 'package:sports_store/features/returns/presentation/view_models/create_return_state.dart';
import 'package:sports_store/features/returns/presentation/widgets/create_return_sections.dart';

ReturnOrderOverview _order({
  DateTime? reference,
  bool canSubmitReturn = true,
  String productName = 'Áo Thể Thao Nam',
  int unitPriceVnd = 260000,
}) => ReturnOrderOverview(
  orderId: '00000000-0000-4000-8000-000000000128',
  orderCode: 'DH000128',
  deliveredAt: DateTime.utc(2026, 10, 1, 7, 30),
  returnDeadline: DateTime.utc(2026, 10, 8, 7, 30),
  referenceTime: reference ?? DateTime.utc(2026, 10, 3, 7, 30),
  deliveryFeeVnd: 30000,
  canSubmitReturn: canSubmitReturn,
  lines: [
    ReturnOrderLine(
      productName: productName,
      variantLabel: 'Màu Đen / Size M',
      quantity: 2,
      unitPriceVnd: unitPriceVnd,
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  ReturnOrderOverview order, {
  ValueChanged<ReturnReason>? onContinue,
}) async {
  tester.view.physicalSize = const Size(390, 884);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: CreateReturnPage(order: order, onContinue: onContinue),
      ),
    ),
  );
}

Future<Finder> _reason(WidgetTester tester, String wire) async {
  final finder = find.byKey(ValueKey('mh13-reason-$wire'));
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.descendant(
      of: find.byKey(const ValueKey('mh13-scroll')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  return finder;
}

void main() {
  test('reason wire values match public.return_reason', () {
    expect(ReturnReason.values.map((r) => r.wireValue), [
      'defective',
      'wrong_item',
      'missing_items',
    ]);
    expect(ReturnReason.fromWire('wrong_item'), ReturnReason.wrongItem);
  });

  test('totals and deadline derive from integer VND and server time', () {
    final order = _order();
    expect(order.merchandiseVnd, 520000);
    expect(order.totalPaidVnd, 550000);
    expect(order.daysSinceDelivery, 2);
    expect(order.timeRemaining.inDays, 5);
    expect(order.isEligible, isTrue);
    expect(
      _order(reference: DateTime.utc(2026, 10, 8, 7, 30)).isEligible,
      isFalse,
    );
    expect(_order(canSubmitReturn: false).isEligible, isFalse);
  });

  testWidgets('renders mock-up content and keeps submit fixed', (tester) async {
    await _pump(tester, _order(), onContinue: (_) {});

    expect(find.text('Yêu cầu trả hàng'), findsOneWidget);
    expect(find.text('Đơn #DH000128'), findsOneWidget);
    expect(find.text('Đã giao'), findsOneWidget);
    expect(find.textContaining('đã nhận 2 ngày trước'), findsOneWidget);
    expect(find.text('Tổng đã thanh toán'), findsOneWidget);
    expect(find.text('550.000 ₫'), findsOneWidget);
    expect(find.text('Vì sao bạn muốn trả hàng?'), findsOneWidget);
    expect(find.text('Tiếp tục'), findsOneWidget);
    expect(
      find.text('Tiếp theo: video và thông tin hoàn tiền'),
      findsOneWidget,
    );
    expect(find.textContaining('MH13'), findsNothing);
    expect(find.byTooltip('Trợ giúp'), findsNothing);
    expect(find.text('14:30, 08/10/2026'), findsOneWidget);
    expect(find.text('Còn 5 ngày'), findsOneWidget);
    expect(find.text(ReturnDeadlineNotice.policy), findsOneWidget);

    final submit = find.byKey(const ValueKey('mh13-submit'));
    final before = tester.getTopLeft(submit);
    await tester.drag(
      find.byKey(const ValueKey('mh13-scroll')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(submit), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('submit is enabled only after choosing a reason', (tester) async {
    ReturnReason? submitted;
    await _pump(tester, _order(), onContinue: (r) => submitted = r);

    final submit = find.byKey(const ValueKey('mh13-submit'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await tester.tap(await _reason(tester, 'wrong_item'));
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);

    await tester.tap(submit);
    expect(submitted, ReturnReason.wrongItem);
  });

  testWidgets('expired order cannot pick a reason or submit', (tester) async {
    await _pump(
      tester,
      _order(reference: DateTime.utc(2026, 10, 9)),
      onContinue: (_) {},
    );
    expect(find.text('Đã hết hạn'), findsOneWidget);
    await tester.tap(await _reason(tester, 'defective'));
    await tester.pump();
    final submit = find.byKey(const ValueKey('mh13-submit'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
  });

  testWidgets('long product name and large price fit at 390 width', (
    tester,
  ) async {
    await _pump(
      tester,
      _order(
        productName:
            'Áo Thể Thao Nam STRIDE DryFit Pro Tay Ngắn Thoáng Khí Phiên Bản '
            'Giới Hạn Mùa Thu 2026',
        unitPriceVnd: 12990000,
      ),
      onContinue: (_) {},
    );
    expect(find.text('25.980.000 ₫'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final submit = tester.getRect(find.byKey(const ValueKey('mh13-submit')));
    expect(submit.bottom, lessThanOrEqualTo(884));
  });
}
