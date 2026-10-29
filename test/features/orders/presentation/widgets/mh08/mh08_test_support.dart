import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/domain/models/cod_summary.dart';
import 'package:sports_store/features/orders/domain/models/order.dart';
import 'package:sports_store/features/orders/domain/models/order_item.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/domain/models/order_summary.dart';
import 'package:sports_store/features/orders/domain/models/order_warning.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_notification_theme.dart';

import '../../../../../fixtures/order_list_page_fixtures.dart';

Future<void> pumpMh08(
  WidgetTester tester,
  Widget child, {
  double width = 390,
  double scale = 1,
}) async {
  tester.view
    ..physicalSize = Size(width, 844)
    ..devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: OrderNotificationTheme.data(ThemeData(useMaterial3: true)),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 844),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(20), child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Only test snapshots. Reuses the existing fixture's identity and invariants.
OrderSummary mh08Summary({
  String? accountName = 'Nguyễn Minh Anh',
  bool longText = false,
  List<OrderWarning> warnings = const [],
  CodSummary? codSummary,
  OrderStatus status = OrderStatus.pendingConfirmation,
}) {
  final base = listFixtureSummary(status: status);
  final source = base.order;
  final order = Order(
    id: source.id,
    customerId: source.customerId,
    requestId: source.requestId,
    status: source.status,
    recipientName: longText
        ? 'Người nhận với tên tiếng Việt rất dài ' * 3
        : source.recipientName,
    recipientPhone: source.recipientPhone,
    addressDetail: longText
        ? 'Địa chỉ giao hàng phường Cầu Giấy Hà Nội rất dài ' * 3
        : source.addressDetail,
    latitude: source.latitude,
    longitude: source.longitude,
    subtotalVnd: source.subtotalVnd,
    deliveryFeeVnd: source.deliveryFeeVnd,
    totalCodVnd: source.totalCodVnd,
    deliveryAttemptCount: source.deliveryAttemptCount,
    placedAt: source.placedAt,
    confirmedAt: source.confirmedAt,
    source: source.source,
    confirmedBy: source.confirmedBy,
    deliveredAt: source.deliveredAt,
    cancelReason: source.cancelReason,
    createdAt: source.createdAt,
    updatedAt: source.updatedAt,
  );
  final item = base.itemPreview.single;
  return OrderSummary(
    order: order,
    customerDisplayName: accountName,
    itemPreview: [
      OrderItem(
        id: item.id,
        orderId: item.orderId,
        productId: item.productId,
        variantId: item.variantId,
        productName: longText
            ? 'Giày thể thao chuyên dụng chạy đường dài ' * 4
            : item.productName,
        variantLabel: longText
            ? 'Đen phối xám phiên bản đặc biệt cỡ 42 ' * 3
            : item.variantLabel,
        attributes: item.attributes,
        unitPriceVnd: item.unitPriceVnd,
        quantity: item.quantity,
        lineTotalVnd: item.lineTotalVnd,
        createdAt: item.createdAt,
      ),
    ],
    itemLineCount: base.itemLineCount,
    itemQuantityTotal: base.itemQuantityTotal,
    deliverySummary: base.deliverySummary,
    codSummary: codSummary,
    returnSummary: base.returnSummary,
    warnings: warnings,
    capabilities: base.capabilities,
  );
}
