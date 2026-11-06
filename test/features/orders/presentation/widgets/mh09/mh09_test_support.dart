import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/data/models/order_dto.dart';
import 'package:sports_store/features/orders/domain/models/order.dart';
import 'package:sports_store/features/orders/domain/models/order_item.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_notification_theme.dart';

import '../../../../../fixtures/order_notification_fixtures.dart';

/// Intentionally has no ProviderScope: components must need only their inputs.
Future<void> pumpMh09(
  WidgetTester tester,
  Widget child, {
  double width = 390,
  double scale = 1,
  double gutters = 20,
  double height = 844,
}) async {
  tester.view
    ..physicalSize = Size(width, height)
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
          size: Size(width, height),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: gutters),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
  // Busy headers contain an indeterminate progress indicator: no pumpAndSettle.
  await tester.pump();
}

Order mh09Order({
  OrderStatus status = OrderStatus.pendingConfirmation,
  String recipientName = 'Người nhận minh họa',
  String recipientPhone = '0900000000',
  String addressDetail = '25 Nguyễn Chí Thanh, Hà Nội',
  int attempts = 0,
}) => OrderDto.fromJson({
  ...fixtureOrderJson(status: status.wireValue),
  'recipient_name': recipientName,
  'recipient_phone': recipientPhone,
  'address_detail': addressDetail,
  'delivery_attempt_count': attempts,
}).domain;

OrderItem mh09Item({
  int index = 1,
  String productName = 'Giày chạy bộ snapshot',
  String variantLabel = 'Đen / EU 42',
  int quantity = 1,
  int unitPriceVnd = 3450000,
}) => OrderItemDto.fromJson({
  ...fixtureOrderItemJson(),
  'id': '60000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
  'product_name': productName,
  'variant_label': variantLabel,
  'unit_price_vnd': unitPriceVnd,
  'quantity': quantity,
  'line_total_vnd': quantity * unitPriceVnd,
}).domain;
