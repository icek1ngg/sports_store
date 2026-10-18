import 'package:sports_store/features/orders/domain/models/buyer.dart';
import 'package:sports_store/features/orders/domain/models/cod_summary.dart';
import 'package:sports_store/features/orders/domain/models/delivery_summary.dart';
import 'package:sports_store/features/orders/domain/models/order.dart';
import 'package:sports_store/features/orders/domain/models/order_capabilities.dart';
import 'package:sports_store/features/orders/domain/models/order_details.dart';
import 'package:sports_store/features/orders/domain/models/order_item.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/domain/models/order_summary.dart';
import 'package:sports_store/features/orders/domain/models/order_timeline_entry.dart';
import 'package:sports_store/features/orders/domain/models/order_warning.dart';

import 'mh08_manager_projections.dart';
import 'mh08_manager_timeline.dart';

final mh08PreviewAsOf = DateTime.utc(2026, 10, 15, 8, 30);

class Mh08ManagerItemSpec {
  const Mh08ManagerItemSpec(this.name, this.variant, this.price, this.quantity);
  final String name;
  final String variant;
  final int price;
  final int quantity;
}

class Mh08ManagerSeed {
  const Mh08ManagerSeed({
    required this.index,
    required this.status,
    required this.accountName,
    required this.managerActions,
    required this.items,
    this.nullProjection = false,
    this.recipient = 'Người nhận đơn thể thao',
    this.address = 'Tầng 4, 18 phố Huế, quận Hai Bà Trưng, Hà Nội',
  });
  final int index;
  final OrderStatus status;
  final String? accountName;
  final bool managerActions;
  final List<Mh08ManagerItemSpec> items;
  final bool nullProjection;
  final String recipient;
  final String address;
}

/// One read-only aggregate used by the MH08 preview repository.
class Mh08ManagerRecord {
  Mh08ManagerRecord({
    required this.order,
    required this.accountName,
    required List<OrderItem> items,
    required this.deliverySummary,
    required this.codSummary,
    required List<OrderWarning> warnings,
    required this.buyer,
    required List<OrderTimelineEntry> timeline,
    required this.managerActions,
  }) : items = List.unmodifiable(items),
       warnings = List.unmodifiable(warnings),
       timeline = List.unmodifiable(timeline);

  factory Mh08ManagerRecord.fromSeed(Mh08ManagerSeed seed) {
    final orderId = Mh08ManagerProjections.uuid(20000 - seed.index);
    final customerId = Mh08ManagerProjections.uuid(2000 + seed.index);
    final placedAt = mh08PreviewAsOf.subtract(Duration(days: seed.index));
    final taskId = Mh08ManagerProjections.uuid(6000 + seed.index);
    final items = [
      for (var i = 0; i < seed.items.length; i++)
        OrderItem(
          id: Mh08ManagerProjections.uuid(3000 + seed.index * 10 + i),
          orderId: orderId,
          productId: Mh08ManagerProjections.uuid(4000 + seed.index * 10 + i),
          variantId: Mh08ManagerProjections.uuid(5000 + seed.index * 10 + i),
          productName: seed.items[i].name,
          variantLabel: seed.items[i].variant,
          attributes: const {'source': 'MH08 preview'},
          unitPriceVnd: seed.items[i].price,
          quantity: seed.items[i].quantity,
          lineTotalVnd: seed.items[i].price * seed.items[i].quantity,
          createdAt: placedAt,
        ),
    ];
    final subtotal = items.fold<int>(0, (sum, item) => sum + item.lineTotalVnd);
    final confirmed =
        seed.status == OrderStatus.pendingConfirmation ||
            seed.status == OrderStatus.rejected
        ? null
        : placedAt.add(const Duration(minutes: 20));
    final deliveredAt = seed.status == OrderStatus.delivered
        ? placedAt.add(const Duration(days: 1, hours: 2))
        : null;
    final failedAt = seed.status == OrderStatus.awaitingRedelivery
        ? placedAt.add(const Duration(hours: 1))
        : null;
    final order = Order(
      id: orderId,
      customerId: customerId,
      requestId: Mh08ManagerProjections.uuid(7000 + seed.index),
      status: seed.status,
      recipientName: seed.recipient,
      recipientPhone: '090100${(seed.index + 10).toString().padLeft(2, '0')}',
      addressDetail: seed.address,
      latitude: 21.018 + seed.index / 10000,
      longitude: 105.852 + seed.index / 10000,
      subtotalVnd: subtotal,
      deliveryFeeVnd: 30000,
      totalCodVnd: subtotal + 30000,
      deliveryAttemptCount:
          seed.status == OrderStatus.delivered ||
              seed.status == OrderStatus.awaitingRedelivery
          ? 1
          : 0,
      placedAt: placedAt,
      confirmedAt: confirmed,
      source: confirmed == null ? null : OrderConfirmationSource.manager,
      confirmedBy: confirmed == null ? null : Mh08ManagerProjections.uuid(8000),
      deliveredAt: deliveredAt,
      cancelReason: seed.status == OrderStatus.rejected
          ? 'Quản lý từ chối đơn trong dữ liệu minh họa.'
          : null,
      createdAt: placedAt,
      updatedAt:
          deliveredAt ?? failedAt ?? placedAt.add(const Duration(minutes: 20)),
    );
    final failed = seed.status == OrderStatus.awaitingRedelivery;
    final delivery = seed.nullProjection
        ? null
        : Mh08ManagerProjections.delivery(
            order,
            seed.status,
            taskId,
            failed,
            placedAt,
            confirmed,
          );
    final cod = seed.nullProjection
        ? null
        : Mh08ManagerProjections.cod(order, seed.status);
    final warnings = failed
        ? [
            OrderWarning(
              code: WarningCode.outboundFailure,
              sourceId: taskId,
              message: 'Giao hàng thất bại, cần xử lý giao lại.',
            ),
          ]
        : const <OrderWarning>[];
    return Mh08ManagerRecord(
      order: order,
      accountName: seed.accountName,
      items: items,
      deliverySummary: delivery,
      codSummary: cod,
      warnings: warnings,
      buyer: Buyer(id: customerId, fullName: seed.accountName),
      timeline: Mh08ManagerTimeline.build(order, taskId, failed),
      managerActions: seed.managerActions,
    );
  }

  final Order order;
  final String? accountName;
  final List<OrderItem> items;
  final DeliverySummary? deliverySummary;
  final CodSummary? codSummary;
  final List<OrderWarning> warnings;
  final Buyer? buyer;
  final List<OrderTimelineEntry> timeline;
  final bool managerActions;

  OrderCapabilities get capabilities => OrderCapabilities(
    canCancelCustomer: false,
    canConfirm: managerActions,
    canReject: managerActions,
    canCancelExceptional: false,
    canAssign: false,
    canReassign: false,
    canArrangeSecondAttempt: false,
    canRequestEarlyReturn: false,
    canReceiveUndelivered: false,
    canOpenReturnCreation: false,
  );

  OrderSummary get summary => OrderSummary(
    order: order,
    itemPreview: items.take(2).toList(growable: false),
    itemLineCount: items.length,
    itemQuantityTotal: items.fold(0, (sum, item) => sum + item.quantity),
    customerDisplayName: accountName,
    deliverySummary: deliverySummary,
    codSummary: codSummary,
    returnSummary: null,
    warnings: warnings,
    capabilities: capabilities,
  );

  OrderDetails get details => OrderDetails(
    order: order,
    items: items,
    buyer: buyer,
    deliverySummary: deliverySummary,
    codSummary: codSummary,
    returnSummaries: const [],
    timeline: timeline,
    historyComplete: true,
    capabilities: capabilities,
    asOf: order.updatedAt,
  );
}
