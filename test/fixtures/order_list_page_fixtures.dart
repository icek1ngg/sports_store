import 'dart:async';

import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/features/orders/domain/models/buyer.dart';
import 'package:sports_store/features/orders/domain/models/order.dart';
import 'package:sports_store/features/orders/domain/models/order_capabilities.dart';
import 'package:sports_store/features/orders/domain/models/order_command.dart';
import 'package:sports_store/features/orders/domain/models/order_details.dart';
import 'package:sports_store/features/orders/domain/models/order_item.dart';
import 'package:sports_store/features/orders/domain/models/operation_result.dart';
import 'package:sports_store/features/orders/domain/models/order_page.dart';
import 'package:sports_store/features/orders/domain/models/order_query.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/domain/models/order_summary.dart';
import 'package:sports_store/features/orders/domain/models/order_timeline_entry.dart';
import 'package:sports_store/features/orders/domain/models/order_mutation_receipt.dart';
import 'package:sports_store/features/orders/domain/models/return_summary.dart';
import 'package:sports_store/features/orders/domain/repositories/order_repository.dart';

const listFixtureCustomerId = '20000000-0000-4000-8000-000000000001';
const listFixtureOtherCustomerId = '20000000-0000-4000-8000-000000000002';
const listFixtureOrderId = '10000000-0000-4000-8000-000000000001';
const listFixtureSecondOrderId = '10000000-0000-4000-8000-000000000002';
const listFixtureThirdOrderId = '10000000-0000-4000-8000-000000000003';
const listFixtureRequestId = '30000000-0000-4000-8000-000000000001';
const listFixtureProductId = '70000000-0000-4000-8000-000000000001';
const listFixtureVariantId = '80000000-0000-4000-8000-000000000001';
const listFixtureItemId = '60000000-0000-4000-8000-000000000001';
const listFixtureTimelineId = '40000000-0000-4000-8000-000000000001';
const listFixtureReturnId = '50000000-0000-4000-8000-000000000001';

final listFixtureTime = DateTime.utc(2026, 10, 8, 3, 32);

Map<OrderStatus, int> listFixtureCounts({
  int pending = 0,
  int preparing = 0,
  int awaitingPickup = 0,
  int delivering = 0,
  int awaitingRedelivery = 0,
  int awaitingStoreReturn = 0,
  int delivered = 0,
  int cancelled = 0,
  int rejected = 0,
  int undeliverableReturned = 0,
}) {
  return {
    OrderStatus.pendingConfirmation: pending,
    OrderStatus.preparing: preparing,
    OrderStatus.awaitingPickup: awaitingPickup,
    OrderStatus.delivering: delivering,
    OrderStatus.awaitingRedelivery: awaitingRedelivery,
    OrderStatus.awaitingStoreReturn: awaitingStoreReturn,
    OrderStatus.delivered: delivered,
    OrderStatus.cancelled: cancelled,
    OrderStatus.rejected: rejected,
    OrderStatus.undeliverableReturned: undeliverableReturned,
  };
}

OrderCapabilities listFixtureCapabilities({
  bool canCancelCustomer = false,
  bool canConfirm = false,
  bool canReject = false,
  bool canOpenReturnCreation = false,
}) {
  return OrderCapabilities(
    canCancelCustomer: canCancelCustomer,
    canConfirm: canConfirm,
    canReject: canReject,
    canCancelExceptional: false,
    canAssign: false,
    canReassign: false,
    canArrangeSecondAttempt: false,
    canRequestEarlyReturn: false,
    canReceiveUndelivered: false,
    canOpenReturnCreation: canOpenReturnCreation,
  );
}

Order _listFixtureOrder({
  String id = listFixtureOrderId,
  String customerId = listFixtureCustomerId,
  OrderStatus status = OrderStatus.pendingConfirmation,
  DateTime? placedAt,
}) {
  final placed = placedAt ?? listFixtureTime;
  return Order(
    id: id,
    customerId: customerId,
    requestId: listFixtureRequestId,
    status: status,
    recipientName: 'Người nhận fixture',
    recipientPhone: '0900000000',
    addressDetail: 'Địa chỉ fixture tại Hà Nội',
    latitude: 21.028,
    longitude: 105.834,
    subtotalVnd: 3450000,
    deliveryFeeVnd: 30000,
    totalCodVnd: 3480000,
    deliveryAttemptCount: 0,
    placedAt: placed,
    confirmedAt: status == OrderStatus.pendingConfirmation ? null : placed,
    source: status == OrderStatus.pendingConfirmation
        ? null
        : OrderConfirmationSource.manager,
    confirmedBy: status == OrderStatus.pendingConfirmation
        ? null
        : listFixtureCustomerId,
    deliveredAt: status == OrderStatus.delivered ? placed : null,
    cancelReason: null,
    createdAt: placed,
    updatedAt: placed,
  );
}

OrderItem listFixtureItem({
  String orderId = listFixtureOrderId,
  String id = listFixtureItemId,
}) {
  return OrderItem(
    id: id,
    orderId: orderId,
    productId: listFixtureProductId,
    variantId: listFixtureVariantId,
    productName: 'Giày chạy bộ fixture',
    variantLabel: 'Đen / 42',
    attributes: const {'color': 'black'},
    unitPriceVnd: 3450000,
    quantity: 1,
    lineTotalVnd: 3450000,
    createdAt: listFixtureTime,
  );
}

OrderSummary listFixtureSummary({
  String id = listFixtureOrderId,
  String customerId = listFixtureCustomerId,
  OrderStatus status = OrderStatus.pendingConfirmation,
  OrderCapabilities? capabilities,
  ReturnSummary? returnSummary,
}) {
  final order = _listFixtureOrder(
    id: id,
    customerId: customerId,
    status: status,
  );
  return OrderSummary(
    order: order,
    itemPreview: [listFixtureItem(orderId: id, id: listFixtureItemId)],
    itemLineCount: 1,
    itemQuantityTotal: 1,
    customerDisplayName: customerId == listFixtureCustomerId
        ? 'Khách hàng fixture'
        : 'Khách hàng khác',
    deliverySummary: null,
    codSummary: null,
    returnSummary: returnSummary,
    warnings: const [],
    capabilities: capabilities ?? const OrderCapabilities.none(),
  );
}

OrderPage listFixturePage({
  List<OrderSummary>? items,
  String? nextCursor,
  int? totalCount,
  Map<OrderStatus, int>? counts,
}) {
  final rows = items ?? [listFixtureSummary()];
  return OrderPage(
    items: rows,
    nextCursor: nextCursor,
    totalCount: totalCount ?? rows.length,
    statusCounts: counts ?? listFixtureCounts(pending: rows.length),
    asOf: listFixtureTime,
  );
}

OrderTimelineEntry listFixtureTimeline() {
  return OrderTimelineEntry(
    eventId: listFixtureTimelineId,
    sourceEntityType: TimelineEntityType.order,
    sourceEntityId: listFixtureOrderId,
    eventKind: 'order_placed',
    fromState: null,
    toState: OrderStatus.pendingConfirmation.wireValue,
    actorId: null,
    actorLabel: null,
    actorSource: TimelineActorSource.system,
    occurredAt: listFixtureTime,
    reason: null,
    source: TimelineSource.actualEvent,
  );
}

OrderDetails listFixtureDetails({
  OrderStatus status = OrderStatus.pendingConfirmation,
  OrderCapabilities? capabilities,
  ReturnSummary? returnSummary,
}) {
  final order = _listFixtureOrder(status: status);
  return OrderDetails(
    order: order,
    items: [listFixtureItem()],
    buyer: Buyer(id: order.customerId, fullName: 'Khách hàng fixture'),
    deliverySummary: null,
    codSummary: null,
    returnSummaries: returnSummary == null
        ? const []
        : <ReturnSummary>[returnSummary],
    timeline: [listFixtureTimeline()],
    historyComplete: true,
    capabilities: capabilities ?? const OrderCapabilities.none(),
    asOf: listFixtureTime,
  );
}

ReturnSummary listFixtureActiveReturn() {
  return ReturnSummary(
    returnId: listFixtureReturnId,
    orderId: listFixtureOrderId,
    status: ReturnRequestStatus.pendingReview,
    submittedAt: listFixtureTime,
    closedAt: null,
    decisionReason: null,
    isActive: true,
    canSubmitReturn: false,
    eligibilityReason: null,
    returnDeadline: listFixtureTime.add(const Duration(days: 7)),
  );
}

/// Test-only repository with explicit page/detail controls. It never appears
/// in production providers and throws an AppFailure for unconfigured reads.
class OrderListFixtureRepository implements OrderRepository {
  OrderListFixtureRepository({
    this.customerPage,
    this.managerPage,
    this.details,
    this.customerFailure,
    this.managerFailure,
    this.detailFailure,
    this.customerPageLoader,
    this.managerPageLoader,
  });

  OrderPage? customerPage;
  OrderPage? managerPage;
  OrderDetails? details;
  AppFailure? customerFailure;
  AppFailure? managerFailure;
  AppFailure? detailFailure;
  FutureOr<OrderPage> Function(OrderQuery query)? customerPageLoader;
  FutureOr<OrderPage> Function(OrderQuery query)? managerPageLoader;
  final customerQueries = <OrderQuery>[];
  final managerQueries = <OrderQuery>[];
  final detailIds = <String>[];

  @override
  Future<OrderPage> getCustomerOrders(OrderQuery query) async {
    customerQueries.add(query);
    final loader = customerPageLoader;
    if (loader != null) return await loader(query);
    final failure = customerFailure;
    if (failure != null) throw failure;
    final page = customerPage;
    if (page == null) {
      throw const AppFailure(code: AppFailure.externalDependencyUnavailable);
    }
    return page;
  }

  @override
  Future<OrderPage> getManagerOrders(OrderQuery query) async {
    managerQueries.add(query);
    final loader = managerPageLoader;
    if (loader != null) return await loader(query);
    final failure = managerFailure;
    if (failure != null) throw failure;
    final page = managerPage;
    if (page == null) {
      throw const AppFailure(code: AppFailure.externalDependencyUnavailable);
    }
    return page;
  }

  @override
  Future<OrderDetails> getOrderDetails(String orderId) async {
    detailIds.add(orderId);
    final failure = detailFailure;
    if (failure != null) throw failure;
    final value = details;
    if (value == null) {
      throw const AppFailure(code: AppFailure.externalDependencyUnavailable);
    }
    return value;
  }

  @override
  Future<OrderMutationReceipt> confirm(StableOrderCommand command) =>
      _mutationUnavailable();

  @override
  Future<OrderMutationReceipt> reject(StableOrderCommand command) =>
      _mutationUnavailable();

  @override
  Future<OrderMutationReceipt> cancelCustomer(StableOrderCommand command) =>
      _mutationUnavailable();

  @override
  Future<OrderMutationReceipt> cancelManager(StableOrderCommand command) =>
      _mutationUnavailable();

  @override
  Future<OperationResult> getOperationResult({
    required String requestId,
    required String orderId,
    required OrderOperation operation,
  }) => throw const AppFailure(code: AppFailure.externalDependencyUnavailable);

  Future<OrderMutationReceipt> _mutationUnavailable() => Future.error(
    const AppFailure(code: AppFailure.externalDependencyUnavailable),
  );
}
