import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sports_store/core/utils/display_formatters.dart';
import 'package:sports_store/features/orders/domain/models/cod_summary.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/domain/models/order_summary.dart';
import 'package:sports_store/features/orders/domain/models/order_warning.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_buyer_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_item_preview.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_operational_notice.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_payment_section.dart';

import 'mh08_test_support.dart';

void main() {
  testWidgets('buyer fallback labels the recipient when account is missing', (
    tester,
  ) async {
    await pumpMh08(
      tester,
      Mh08BuyerSection(summary: mh08Summary(accountName: null)),
    );

    expect(find.text('Người nhận'), findsOneWidget);
    expect(find.text('Khách hàng'), findsNothing);
  });

  testWidgets('buyer keeps a distinct account and recipient snapshot', (
    tester,
  ) async {
    await pumpMh08(
      tester,
      Mh08BuyerSection(summary: mh08Summary(accountName: 'Tài khoản quản lý')),
    );

    expect(find.text('Khách hàng'), findsOneWidget);
    expect(find.text('Người nhận'), findsOneWidget);
    expect(find.text('Tài khoản quản lý'), findsOneWidget);
  });

  testWidgets(
    'blank account is unavailable, matching recipient is not duplicated',
    (tester) async {
      final missing = mh08Summary(accountName: '   ');
      await pumpMh08(tester, Mh08BuyerSection(summary: missing));
      expect(find.text('Khách hàng'), findsNothing);
      expect(find.text(missing.order.recipientName), findsOneWidget);
      final matching = mh08Summary(accountName: missing.order.recipientName);
      await pumpMh08(tester, Mh08BuyerSection(summary: matching));
      expect(find.text('Khách hàng'), findsOneWidget);
      expect(find.text('Người nhận'), findsNothing);
      expect(find.text(matching.order.recipientName), findsOneWidget);
    },
  );

  testWidgets(
    'missing item snapshots stay unavailable without catalog image fallback',
    (tester) async {
      final base = mh08Summary();
      final summary = OrderSummary(
        order: base.order,
        itemPreview: const [],
        itemLineCount: 3,
        itemQuantityTotal: 3,
        customerDisplayName: base.customerDisplayName,
        deliverySummary: null,
        codSummary: null,
        returnSummary: null,
        warnings: const [],
        capabilities: base.capabilities,
      );
      await pumpMh08(tester, Mh08ItemPreview(summary: summary));
      expect(find.text('Chưa có bản xem trước sản phẩm'), findsOneWidget);
      expect(find.text('Và 3 dòng sản phẩm khác'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    },
  );

  testWidgets('item preview exposes snapshot name, variant and quantity', (
    tester,
  ) async {
    final summary = mh08Summary(longText: true);
    await pumpMh08(tester, Mh08ItemPreview(summary: summary));

    expect(find.text('${summary.itemQuantityTotal} sản phẩm'), findsOneWidget);
    expect(find.text(summary.itemPreview.first.productName), findsOneWidget);
    expect(
      find.text('Biến thể: ${summary.itemPreview.first.variantLabel}'),
      findsOneWidget,
    );
    expect(
      find.text('Số lượng: ${summary.itemPreview.first.quantity}'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Không có ảnh sản phẩm'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('payment uses integer VND formatting and cash COD pill', (
    tester,
  ) async {
    await pumpMh08(
      tester,
      const Mh08PaymentSection(
        totalCodVnd: 3450000,
        itemQuantityTotal: 3,
        codSummary: null,
      ),
    );

    expect(find.text(formatVnd(3450000)), findsOneWidget);
    expect(find.text('3 sản phẩm'), findsOneWidget);
    expect(find.text('COD • Nhận tiền mặt'), findsOneWidget);
    expect(find.text('Trạng thái COD: Chưa có dữ liệu'), findsOneWidget);
  });

  testWidgets('payment preserves the supplied COD lifecycle status', (
    tester,
  ) async {
    final cod = CodSummary(
      orderId: '00000000-0000-0000-0000-000000000001',
      shipperId: null,
      status: CodStatus.collected,
      expectedAmountVnd: 3450000,
      collectedAmountVnd: 3450000,
      receivedAmountVnd: 0,
      collectedAt: null,
      collectedBy: null,
      handedOverAt: null,
      receivedAt: null,
      receivedBy: null,
    );
    await pumpMh08(
      tester,
      Mh08PaymentSection(
        totalCodVnd: 3450000,
        itemQuantityTotal: 3,
        codSummary: cod,
      ),
    );

    expect(find.text('Trạng thái COD: Shipper đã thu'), findsOneWidget);
  });

  testWidgets('operational notice shrinks when there are no warnings', (
    tester,
  ) async {
    await pumpMh08(tester, const Mh08OperationalNotice(warnings: []));

    expect(find.byKey(const ValueKey('mh08-operational-notice')), findsNothing);
  });

  testWidgets(
    'operational notice renders server message once without technical code',
    (tester) async {
      final warning = OrderWarning(
        code: WarningCode.outboundFailure,
        sourceId: '00000000-0000-0000-0000-000000000002',
        message: 'Cần quản lý kiểm tra trạng thái giao hàng.',
      );
      await pumpMh08(tester, Mh08OperationalNotice(warnings: [warning]));

      expect(find.text(warning.message), findsOneWidget);
      expect(find.text(warning.rawCode), findsNothing);
      expect(
        find.bySemanticsLabel('Cảnh báo: ${warning.message}'),
        findsOneWidget,
      );
    },
  );

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('all sections reflow at width$width scale$scale', (
        tester,
      ) async {
        final summary = mh08Summary(
          longText: true,
          accountName: 'Tên tài khoản rất dài để kiểm tra cách xuống dòng',
        );
        final warning = OrderWarning(
          code: WarningCode.goodsDiscrepancy,
          sourceId: '00000000-0000-0000-0000-000000000003',
          message: 'Nội dung cảnh báo dài cần xuống dòng trong thẻ quản lý đơn hàng.',
        );
        await pumpMh08(
          tester,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Mh08BuyerSection(summary: summary),
              Mh08ItemPreview(summary: summary),
              const Mh08PaymentSection(
                totalCodVnd: 3450000,
                itemQuantityTotal: 3,
                codSummary: null,
              ),
              Mh08OperationalNotice(warnings: [warning]),
            ],
          ),
          width: width,
          scale: scale,
        );

        expect(tester.takeException(), isNull);
      });
    }
  }
}
