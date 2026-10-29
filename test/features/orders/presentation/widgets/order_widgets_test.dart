import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sports_store/features/orders/domain/models/order.dart';
import 'package:sports_store/features/orders/domain/models/order_capabilities.dart';
import 'package:sports_store/features/orders/domain/models/order_item.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/domain/models/order_summary.dart';
import 'package:sports_store/features/orders/domain/models/order_timeline_entry.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_card.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_items_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_payment_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_recipient_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_status_badge.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_timeline.dart';

const orderId = '10000000-0000-4000-8000-000000000001';
const customerId = '20000000-0000-4000-8000-000000000001';
const requestId = '30000000-0000-4000-8000-000000000001';
const productId = '70000000-0000-4000-8000-000000000001';
const variantId = '80000000-0000-4000-8000-000000000001';
const itemId = '60000000-0000-4000-8000-000000000001';
const timelineEventId = '40000000-0000-4000-8000-000000000001';
const timelineEventId2 = '40000000-0000-4000-8000-000000000002';

Order _order() {
  final placed = DateTime.utc(2026, 10, 8, 3, 32);
  return Order(
    id: orderId,
    customerId: customerId,
    requestId: requestId,
    status: OrderStatus.pendingConfirmation,
    recipientName: 'Người nhận có địa chỉ rất dài để kiểm tra wrapping',
    recipientPhone: '0900000000',
    addressDetail: 'Địa chỉ dài tại Hà Nội, nội dung cần hiển thị đầy đủ',
    latitude: 21.028,
    longitude: 105.834,
    subtotalVnd: 3450000,
    deliveryFeeVnd: 30000,
    totalCodVnd: 3480000,
    deliveryAttemptCount: 0,
    placedAt: placed,
    confirmedAt: null,
    source: null,
    confirmedBy: null,
    deliveredAt: null,
    cancelReason: null,
    createdAt: placed,
    updatedAt: placed,
  );
}

OrderItem _item() {
  final created = DateTime.utc(2026, 10, 8, 3, 32);
  return OrderItem(
    id: itemId,
    orderId: orderId,
    productId: productId,
    variantId: variantId,
    productName: 'Sản phẩm minh họa có tên dài',
    variantLabel: 'Màu xanh / Kích thước L',
    attributes: const {},
    unitPriceVnd: 3450000,
    quantity: 1,
    lineTotalVnd: 3450000,
    createdAt: created,
  );
}

Widget _host(Widget child, {bool largeText = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(320, 900),
        textScaler: largeText ? TextScaler.linear(2) : TextScaler.noScaling,
      ),
      child: Scaffold(
        body: SingleChildScrollView(child: SizedBox(width: 320, child: child)),
      ),
    ),
  );
}

void main() {
  testWidgets('order card displays full UUID, status and exact VND amount', (
    tester,
  ) async {
    final order = _order();
    final item = _item();
    final summary = OrderSummary(
      order: order,
      itemPreview: [item],
      itemLineCount: 1,
      itemQuantityTotal: 1,
      customerDisplayName: null,
      deliverySummary: null,
      codSummary: null,
      returnSummary: null,
      warnings: const [],
      capabilities: const OrderCapabilities.none(),
    );

    await tester.pumpWidget(_host(OrderCard(summary: summary)));

    expect(find.text('Đơn hàng $orderId'), findsOneWidget);
    expect(find.text('Chờ xác nhận'), findsOneWidget);
    expect(find.text('COD: 3.480.000 ₫'), findsOneWidget);
    expect(find.textContaining('Sản phẩm minh họa'), findsOneWidget);
  });

  testWidgets('detail sections wrap long recipient and item text', (
    tester,
  ) async {
    final order = _order();
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            OrderRecipientSection(order: order),
            OrderItemsSection(items: [_item()]),
            OrderPaymentSection(order: order),
          ],
        ),
      ),
    );

    expect(find.text(order.addressDetail), findsOneWidget);
    expect(find.textContaining('Màu xanh'), findsOneWidget);
    expect(find.text('Tổng COD'), findsOneWidget);
  });

  testWidgets('status badge has text semantics independent of colour', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const OrderStatusBadge(status: OrderStatus.delivered)),
    );

    expect(find.text('Đã giao hàng'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(OrderStatusBadge)),
      matchesSemantics(label: 'Trạng thái đơn: Đã giao hàng'),
    );
  });

  testWidgets('timeline does not invent an actor when source is unknown', (
    tester,
  ) async {
    final entry = OrderTimelineEntry(
      eventId: null,
      sourceEntityType: TimelineEntityType.order,
      sourceEntityId: orderId,
      eventKind: 'snapshot_milestone',
      fromState: null,
      toState: null,
      actorId: null,
      actorLabel: null,
      actorSource: TimelineActorSource.unknown,
      occurredAt: DateTime.utc(2026, 10, 8, 3, 32),
      reason: null,
      source: TimelineSource.snapshotMilestone,
    );

    await tester.pumpWidget(
      _host(OrderTimeline(entries: [entry], historyComplete: false)),
    );

    expect(find.text('Mốc từ bản ghi đơn'), findsNWidgets(2));
    expect(find.textContaining('Thực hiện bởi:'), findsNothing);
    expect(find.text('Lịch sử có thể chưa đầy đủ'), findsOneWidget);
  });

  testWidgets(
    'timeline sorts events, deduplicates ids and prefers actual milestones',
    (tester) async {
      final placedAt = DateTime.utc(2026, 10, 8, 3, 32);
      final confirmedAt = DateTime.utc(2026, 10, 8, 4, 00);
      final placed = OrderTimelineEntry(
        eventId: timelineEventId,
        sourceEntityType: TimelineEntityType.order,
        sourceEntityId: orderId,
        eventKind: 'order_placed',
        fromState: null,
        toState: 'pending_confirmation',
        actorId: null,
        actorLabel: null,
        actorSource: TimelineActorSource.unknown,
        occurredAt: placedAt,
        reason: null,
        source: TimelineSource.actualEvent,
      );
      final duplicatePlaced = OrderTimelineEntry(
        eventId: timelineEventId,
        sourceEntityType: TimelineEntityType.order,
        sourceEntityId: orderId,
        eventKind: 'order_placed',
        fromState: null,
        toState: 'pending_confirmation',
        actorId: null,
        actorLabel: null,
        actorSource: TimelineActorSource.unknown,
        occurredAt: placedAt,
        reason: 'duplicate delivery',
        source: TimelineSource.actualEvent,
      );
      final confirmed = OrderTimelineEntry(
        eventId: timelineEventId2,
        sourceEntityType: TimelineEntityType.order,
        sourceEntityId: orderId,
        eventKind: 'order_confirmed_manual',
        fromState: 'pending_confirmation',
        toState: 'preparing',
        actorId: null,
        actorLabel: null,
        actorSource: TimelineActorSource.manager,
        occurredAt: confirmedAt,
        reason: null,
        source: TimelineSource.actualEvent,
      );
      final placedFallback = OrderTimelineEntry(
        eventId: null,
        sourceEntityType: TimelineEntityType.order,
        sourceEntityId: orderId,
        eventKind: 'snapshot_milestone',
        fromState: null,
        toState: 'pending_confirmation',
        actorId: null,
        actorLabel: null,
        actorSource: TimelineActorSource.unknown,
        occurredAt: placedAt,
        reason: null,
        source: TimelineSource.snapshotMilestone,
      );

      await tester.pumpWidget(
        _host(
          OrderTimeline(
            entries: [confirmed, placedFallback, duplicatePlaced, placed],
          ),
        ),
      );

      expect(find.text('Đơn hàng được tạo'), findsOneWidget);
      expect(find.text('Đơn hàng được xác nhận'), findsOneWidget);
      expect(find.text('Mốc từ bản ghi đơn'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Đơn hàng được tạo')).dy,
        lessThan(tester.getTopLeft(find.text('Đơn hàng được xác nhận')).dy),
      );
    },
  );

  testWidgets('order widgets fit 320 width at 2x text scale', (tester) async {
    final order = _order();
    final item = _item();
    final summary = OrderSummary(
      order: order,
      itemPreview: [item],
      itemLineCount: 1,
      itemQuantityTotal: 1,
      customerDisplayName: null,
      deliverySummary: null,
      codSummary: null,
      returnSummary: null,
      warnings: const [],
      capabilities: const OrderCapabilities.none(),
    );
    final entry = OrderTimelineEntry(
      eventId: timelineEventId,
      sourceEntityType: TimelineEntityType.order,
      sourceEntityId: orderId,
      eventKind: 'order_placed',
      fromState: null,
      toState: 'pending_confirmation',
      actorId: null,
      actorLabel: null,
      actorSource: TimelineActorSource.unknown,
      occurredAt: order.placedAt,
      reason: null,
      source: TimelineSource.actualEvent,
    );

    await tester.pumpWidget(
      _host(
        Column(
          children: [
            OrderCard(summary: summary),
            OrderRecipientSection(order: order),
            OrderItemsSection(items: [item]),
            OrderPaymentSection(order: order),
            OrderTimeline(entries: [entry]),
          ],
        ),
        largeText: true,
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
