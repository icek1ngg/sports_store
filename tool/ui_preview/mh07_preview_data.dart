import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/features/orders/domain/models/buyer.dart';
import 'package:sports_store/features/orders/domain/models/cod_summary.dart';
import 'package:sports_store/features/orders/domain/models/delivery_summary.dart';
import 'package:sports_store/features/orders/domain/models/order.dart';
import 'package:sports_store/features/orders/domain/models/order_capabilities.dart';
import 'package:sports_store/features/orders/domain/models/order_command.dart';
import 'package:sports_store/features/orders/domain/models/order_details.dart';
import 'package:sports_store/features/orders/domain/models/order_item.dart';
import 'package:sports_store/features/orders/domain/models/order_mutation_receipt.dart';
import 'package:sports_store/features/orders/domain/models/order_page.dart';
import 'package:sports_store/features/orders/domain/models/order_query.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/domain/models/order_summary.dart';
import 'package:sports_store/features/orders/domain/models/order_timeline_entry.dart';
import 'package:sports_store/features/orders/domain/models/operation_result.dart';
import 'package:sports_store/features/orders/domain/repositories/order_repository.dart';

import '../../test/fixtures/order_list_page_fixtures.dart' as order_fixtures;
import '../../test/fixtures/order_notification_fixtures.dart'
    as notification_fixtures;

/// The preview states are intentionally local to the debug harness. They are
/// never persisted and never reach a production repository.
enum PreviewScenario { data, loading, empty, error, stale, expired }

/// A small, deterministic MH07 data source.
///
/// The repository keeps the real [OrderRepository] contract so the preview
/// exercises the same provider/view-model path as the app. It is deliberately
/// mutable only for preview actions: cancellation updates an in-memory row and
/// returns a typed receipt, while the production repository is untouched.
class PreviewOrderRepository implements OrderRepository {
  PreviewOrderRepository({this.pageSize = 4}) : _records = _buildRecords();

  final int pageSize;
  final List<PreviewOrderRecord> _records;
  final Map<String, OrderMutationReceipt> _receipts = {};

  PreviewScenario scenario = PreviewScenario.data;
  int pageReads = 0;
  int detailReads = 0;

  final customerQueries = <OrderQuery>[];
  final managerQueries = <OrderQuery>[];
  final detailIds = <String>[];

  List<PreviewOrderRecord> get records => List.unmodifiable(_records);

  List<OrderSummary> get customerSummaries =>
      List.unmodifiable(_records.map((record) => record.summary));

  void setScenario(PreviewScenario value) {
    if (scenario == value) return;
    scenario = value;
    _records
      ..clear()
      ..addAll(_buildRecords());
    _receipts.clear();
    pageReads = 0;
    detailReads = 0;
  }

  @override
  Future<OrderPage> getCustomerOrders(OrderQuery query) async {
    customerQueries.add(query);
    await _beforeRead(isDetail: false);
    return _page(query);
  }

  @override
  Future<OrderPage> getManagerOrders(OrderQuery query) async {
    managerQueries.add(query);
    await _beforeRead(isDetail: false);
    return _managerPage(query);
  }

  @override
  Future<OrderDetails> getOrderDetails(String orderId) async {
    detailIds.add(orderId);
    await _beforeRead(isDetail: true);
    final record = _find(orderId);
    if (record == null || scenario == PreviewScenario.empty) {
      throw const AppFailure(code: AppFailure.forbiddenOrUnavailable);
    }
    return record.details;
  }

  @override
  Future<OrderMutationReceipt> cancelCustomer(
    StableOrderCommand command,
  ) async {
    final previous = _receipts[command.requestId];
    if (previous != null) {
      return OrderMutationReceipt(
        operation: previous.operation,
        requestId: previous.requestId,
        eventId: previous.eventId,
        order: previous.order,
        committedAt: previous.committedAt,
        replayed: true,
        currentOrder: null,
      );
    }
    final record = _find(command.orderId);
    if (record == null ||
        command.operation != OrderOperation.customerCancel ||
        record.order.customerId != order_fixtures.listFixtureCustomerId) {
      throw const AppFailure(code: AppFailure.forbiddenOrUnavailable);
    }
    if (record.order.status != OrderStatus.pendingConfirmation) {
      throw const AppFailure(code: AppFailure.cancellationNotAllowed);
    }

    final cancelled = _replaceOrder(
      record.order,
      status: OrderStatus.cancelled,
      cancelReason: 'Khách hàng hủy trong bản xem trước.',
      updatedAt: _previewNow,
    );
    record.order = cancelled;
    final receipt = OrderMutationReceipt(
      operation: command.operation,
      requestId: command.requestId,
      eventId: _uuid(980 + _receipts.length),
      order: cancelled,
      committedAt: _previewNow,
      replayed: false,
      currentOrder: null,
    );
    _receipts[command.requestId] = receipt;
    return receipt;
  }

  @override
  Future<OrderMutationReceipt> confirm(StableOrderCommand command) =>
      _mutationUnavailable();

  @override
  Future<OrderMutationReceipt> reject(StableOrderCommand command) =>
      _mutationUnavailable();

  @override
  Future<OrderMutationReceipt> cancelManager(StableOrderCommand command) =>
      _mutationUnavailable();

  @override
  Future<OperationResult> getOperationResult({
    required String requestId,
    required String orderId,
    required OrderOperation operation,
  }) async {
    final receipt = _receipts[requestId];
    if (receipt == null ||
        receipt.order.id != orderId ||
        receipt.operation != operation) {
      return const OperationResult.notFound();
    }
    return OperationResult.committed(receipt);
  }

  Future<OrderMutationReceipt> _mutationUnavailable() => Future.error(
    const AppFailure(code: AppFailure.externalDependencyUnavailable),
  );

  Future<void> _beforeRead({required bool isDetail}) async {
    if (isDetail) {
      detailReads++;
    } else {
      pageReads++;
    }
    if (scenario == PreviewScenario.loading) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    if (scenario == PreviewScenario.error ||
        (scenario == PreviewScenario.stale &&
            (isDetail ? detailReads : pageReads) > 1)) {
      throw const AppFailure(code: AppFailure.network);
    }
    if (scenario == PreviewScenario.expired) {
      throw const AppFailure(code: AppFailure.unauthenticated);
    }
  }

  OrderPage _page(OrderQuery query) {
    final source = scenario == PreviewScenario.empty
        ? const <PreviewOrderRecord>[]
        : _records;
    final search = query.search?.toLowerCase();
    final filtered = source
        .where((record) {
          final matchesStatus =
              query.statuses.isEmpty ||
              query.statuses.contains(record.order.status);
          if (!matchesStatus || search == null) return matchesStatus;
          final haystack = [
            record.order.id,
            record.order.recipientName,
            ...record.items.map((item) => item.productName),
          ].join(' ').toLowerCase();
          return haystack.contains(search);
        })
        .toList(growable: false);

    final offset = _parseCursor(query.cursor);
    if (offset > filtered.length) {
      throw const AppFailure(code: AppFailure.invalidCursor);
    }
    final take = pageSize < query.limit ? pageSize : query.limit;
    final items = filtered
        .skip(offset)
        .take(take)
        .map((e) => e.summary)
        .toList();
    final nextOffset = offset + items.length;
    return OrderPage(
      items: items,
      nextCursor: nextOffset < filtered.length ? '$nextOffset' : null,
      totalCount: filtered.length,
      statusCounts: _statusCounts(source),
      asOf: _previewNow,
    );
  }

  OrderPage _managerPage(OrderQuery query) {
    final summary = order_fixtures.listFixtureSummary(
      capabilities: order_fixtures.listFixtureCapabilities(
        canCancelCustomer: true,
        canConfirm: true,
        canReject: true,
      ),
    );
    final matchesStatus =
        query.statuses.isEmpty || query.statuses.contains(summary.order.status);
    final matchesSearch =
        query.search == null ||
        '${summary.order.id} ${summary.itemPreview.first.productName}'
            .toLowerCase()
            .contains(query.search!.toLowerCase());
    final items =
        scenario == PreviewScenario.empty || !matchesStatus || !matchesSearch
        ? const <OrderSummary>[]
        : [summary];
    return OrderPage(
      items: items,
      nextCursor: null,
      totalCount: items.length,
      statusCounts: order_fixtures.listFixtureCounts(
        pending: scenario == PreviewScenario.empty ? 0 : 1,
      ),
      asOf: _previewNow,
    );
  }

  int _parseCursor(String? cursor) {
    if (cursor == null) return 0;
    final parsed = int.tryParse(cursor);
    if (parsed == null || parsed < 0) {
      throw const AppFailure(code: AppFailure.invalidCursor);
    }
    return parsed;
  }

  Map<OrderStatus, int> _statusCounts(Iterable<PreviewOrderRecord> source) {
    final result = <OrderStatus, int>{
      for (final status in OrderStatus.values) status: 0,
    };
    for (final record in source) {
      result[record.order.status] = result[record.order.status]! + 1;
    }
    return result;
  }

  PreviewOrderRecord? _find(String id) {
    for (final record in _records) {
      if (record.order.id == id) return record;
    }
    return null;
  }
}

/// Mutable aggregate used by [PreviewOrderRepository] to reflect the one
/// preview-only cancellation action in both list and detail projections.
class PreviewOrderRecord {
  PreviewOrderRecord({
    required this.order,
    required List<OrderItem> items,
    required this.customerName,
    required this.deliverySummary,
    required this.codSummary,
    required List<OrderTimelineEntry> timeline,
  }) : items = List.unmodifiable(items),
       timeline = List.unmodifiable(timeline);

  Order order;
  final List<OrderItem> items;
  final String customerName;
  final DeliverySummary? deliverySummary;
  final CodSummary? codSummary;
  final List<OrderTimelineEntry> timeline;

  OrderCapabilities get capabilities => OrderCapabilities(
    canCancelCustomer: order.status == OrderStatus.pendingConfirmation,
    canConfirm: order.status == OrderStatus.pendingConfirmation,
    canReject: order.status == OrderStatus.pendingConfirmation,
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
    itemQuantityTotal: items.fold<int>(0, (sum, item) => sum + item.quantity),
    customerDisplayName: customerName,
    deliverySummary: deliverySummary,
    codSummary: codSummary,
    returnSummary: null,
    warnings: const [],
    capabilities: capabilities,
  );

  OrderDetails get details => OrderDetails(
    order: order,
    items: items,
    buyer: Buyer(id: order.customerId, fullName: customerName),
    deliverySummary: deliverySummary,
    codSummary: codSummary,
    returnSummaries: const [],
    timeline: timeline,
    historyComplete: true,
    capabilities: capabilities,
    asOf: _previewNow,
  );
}

class _PreviewItemSpec {
  const _PreviewItemSpec(this.name, this.variant, this.price, this.quantity);
  final String name;
  final String variant;
  final int price;
  final int quantity;
}

final _previewNow = DateTime.utc(2026, 10, 8, 3, 32);

List<PreviewOrderRecord> _buildRecords() {
  final rows =
      <
        ({
          int index,
          String id,
          OrderStatus status,
          List<_PreviewItemSpec> items,
        })
      >[
        (
          index: 1,
          id: order_fixtures.listFixtureOrderId,
          status: OrderStatus.pendingConfirmation,
          items: const [
            _PreviewItemSpec('Giày chạy bộ AirFlex', 'Đen / 42', 1290000, 1),
            _PreviewItemSpec('Áo thể thao DryFit', 'Xanh navy / M', 320000, 2),
          ],
        ),
        (
          index: 2,
          id: order_fixtures.listFixtureSecondOrderId,
          status: OrderStatus.preparing,
          items: const [
            _PreviewItemSpec('Vợt cầu lông Carbon Pro', '4U / G5', 890000, 1),
          ],
        ),
        (
          index: 3,
          id: order_fixtures.listFixtureThirdOrderId,
          status: OrderStatus.delivering,
          items: const [
            _PreviewItemSpec('Bóng đá sân cỏ Select', 'Size 5', 560000, 1),
          ],
        ),
        (
          index: 4,
          id: '10000000-0000-4000-8000-000000000004',
          status: OrderStatus.delivered,
          items: const [
            _PreviewItemSpec('Ba lô chạy trail', '18L / Đen', 740000, 1),
            _PreviewItemSpec('Tất chạy Cushion', 'Đen / L', 115000, 3),
          ],
        ),
        (
          index: 5,
          id: '10000000-0000-4000-8000-000000000005',
          status: OrderStatus.cancelled,
          items: const [
            _PreviewItemSpec('Găng tay gym Grip', 'M / Đỏ', 280000, 1),
          ],
        ),
        (
          index: 6,
          id: '10000000-0000-4000-8000-000000000006',
          status: OrderStatus.awaitingPickup,
          items: const [
            _PreviewItemSpec('Thảm yoga Eco', '6mm / Tím', 430000, 1),
          ],
        ),
        (
          index: 7,
          id: '10000000-0000-4000-8000-000000000007',
          status: OrderStatus.delivered,
          items: const [
            _PreviewItemSpec('Áo khoác gió Runner', 'L / Xám', 980000, 1),
          ],
        ),
        (
          index: 8,
          id: '10000000-0000-4000-8000-000000000008',
          status: OrderStatus.pendingConfirmation,
          items: const [
            _PreviewItemSpec('Dây kháng lực PowerBand', 'Bộ 5 mức', 350000, 1),
          ],
        ),
        (
          index: 9,
          id: '10000000-0000-4000-8000-000000000009',
          status: OrderStatus.delivering,
          items: const [
            _PreviewItemSpec('Giày bóng rổ Court', 'Trắng / 43', 1590000, 1),
          ],
        ),
        (
          index: 10,
          id: '10000000-0000-4000-8000-000000000010',
          status: OrderStatus.cancelled,
          items: const [
            _PreviewItemSpec('Mũ chạy bộ Reflect', 'One size / Cam', 210000, 1),
          ],
        ),
        (
          index: 11,
          id: '10000000-0000-4000-8000-000000000011',
          status: OrderStatus.preparing,
          items: const [
            _PreviewItemSpec('Bình nước thể thao', '750ml / Xanh', 190000, 2),
          ],
        ),
        (
          index: 12,
          id: '10000000-0000-4000-8000-000000000012',
          status: OrderStatus.delivered,
          items: const [
            _PreviewItemSpec('Quần short training', 'M / Đen', 420000, 1),
          ],
        ),
        (
          index: 13,
          id: '10000000-0000-4000-8000-000000000013',
          status: OrderStatus.pendingConfirmation,
          items: const [
            _PreviewItemSpec('Băng cổ tay thể thao', 'Đôi / Đen', 140000, 1),
          ],
        ),
        (
          index: 14,
          id: '10000000-0000-4000-8000-000000000014',
          status: OrderStatus.delivering,
          items: const [
            _PreviewItemSpec('Túi đeo hông chạy bộ', 'Đen / 2L', 250000, 1),
          ],
        ),
        (
          index: 15,
          id: '10000000-0000-4000-8000-000000000015',
          status: OrderStatus.cancelled,
          items: const [
            _PreviewItemSpec('Dây nhảy Speed Rope', 'Đen / 3m', 180000, 1),
          ],
        ),
        (
          index: 16,
          id: '10000000-0000-4000-8000-000000000016',
          status: OrderStatus.delivered,
          items: const [
            _PreviewItemSpec('Áo jersey bóng đá', 'L / Đỏ', 610000, 1),
          ],
        ),
      ];

  return [
    for (final row in rows)
      _record(
        index: row.index,
        id: row.id,
        status: row.status,
        specs: row.items,
      ),
  ];
}

PreviewOrderRecord _record({
  required int index,
  required String id,
  required OrderStatus status,
  required List<_PreviewItemSpec> specs,
}) {
  final placedAt = _previewNow.subtract(Duration(days: index - 1, hours: 2));
  final items = [
    for (var itemIndex = 0; itemIndex < specs.length; itemIndex++)
      _item(
        orderId: id,
        index: index,
        itemIndex: itemIndex,
        spec: specs[itemIndex],
        createdAt: placedAt,
      ),
  ];
  final subtotal = items.fold<int>(0, (sum, item) => sum + item.lineTotalVnd);
  final order = Order(
    id: id,
    customerId: order_fixtures.listFixtureCustomerId,
    requestId: _uuid(300 + index),
    status: status,
    recipientName: 'Nguyễn Minh Anh',
    recipientPhone: '0901234${(560 + index).toString().padLeft(3, '0')}',
    addressDetail: 'Tầng 4, 18 phố Huế, quận Hai Bà Trưng, Hà Nội',
    latitude: 21.018,
    longitude: 105.852,
    subtotalVnd: subtotal,
    deliveryFeeVnd: 30000,
    totalCodVnd: subtotal + 30000,
    deliveryAttemptCount: status == OrderStatus.delivered ? 1 : 0,
    placedAt: placedAt,
    confirmedAt:
        status == OrderStatus.pendingConfirmation ||
            status == OrderStatus.cancelled
        ? null
        : placedAt.add(const Duration(minutes: 18)),
    source:
        status == OrderStatus.pendingConfirmation ||
            status == OrderStatus.cancelled
        ? null
        : OrderConfirmationSource.manager,
    confirmedBy:
        status == OrderStatus.pendingConfirmation ||
            status == OrderStatus.cancelled
        ? null
        : notification_fixtures.fixtureManagerId,
    deliveredAt: status == OrderStatus.delivered
        ? placedAt.add(const Duration(days: 1, hours: 3))
        : null,
    cancelReason: status == OrderStatus.cancelled
        ? 'Khách hàng đã hủy đơn.'
        : null,
    createdAt: placedAt,
    updatedAt: placedAt.add(const Duration(minutes: 18)),
  );
  final delivery = _deliverySummary(index: index, order: order);
  final cod = _codSummary(index: index, order: order);
  final timeline = [
    OrderTimelineEntry(
      eventId: _uuid(400 + index),
      sourceEntityType: TimelineEntityType.order,
      sourceEntityId: id,
      eventKind: 'order_placed',
      fromState: null,
      toState: OrderStatus.pendingConfirmation.wireValue,
      actorId: null,
      actorLabel: null,
      actorSource: TimelineActorSource.customer,
      occurredAt: placedAt,
      reason: null,
      source: TimelineSource.actualEvent,
    ),
  ];
  return PreviewOrderRecord(
    order: order,
    items: items,
    customerName: 'Nguyễn Minh Anh',
    deliverySummary: delivery,
    codSummary: cod,
    timeline: timeline,
  );
}

OrderItem _item({
  required String orderId,
  required int index,
  required int itemIndex,
  required _PreviewItemSpec spec,
  required DateTime createdAt,
}) {
  return OrderItem(
    id: _uuid(600 + index * 3 + itemIndex),
    orderId: orderId,
    productId: _uuid(700 + index * 3 + itemIndex),
    variantId: _uuid(800 + index * 3 + itemIndex),
    productName: spec.name,
    variantLabel: spec.variant,
    attributes: const {'preview': true},
    unitPriceVnd: spec.price,
    quantity: spec.quantity,
    lineTotalVnd: spec.price * spec.quantity,
    createdAt: createdAt,
  );
}

DeliverySummary? _deliverySummary({required int index, required Order order}) {
  final taskStatus = switch (order.status) {
    OrderStatus.preparing => DeliveryTaskStatus.pendingAssignment,
    OrderStatus.awaitingPickup => DeliveryTaskStatus.assigned,
    OrderStatus.delivering => DeliveryTaskStatus.inTransit,
    OrderStatus.delivered => DeliveryTaskStatus.delivered,
    _ => null,
  };
  if (taskStatus == null) return null;
  final assigned = order.status != OrderStatus.preparing;
  return DeliverySummary(
    taskId: _uuid(900 + index),
    kind: DeliveryTaskKind.outbound,
    taskStatus: taskStatus,
    assignedShipperId: assigned ? _uuid(920 + index) : null,
    assignedShipperName: assigned ? 'Trần Quốc Bình' : null,
    assignedAt: assigned ? order.placedAt.add(const Duration(hours: 1)) : null,
    acceptedAt:
        order.status == OrderStatus.delivering ||
            order.status == OrderStatus.delivered
        ? order.placedAt.add(const Duration(hours: 2))
        : null,
    startedAt:
        order.status == OrderStatus.delivering ||
            order.status == OrderStatus.delivered
        ? order.placedAt.add(const Duration(hours: 3))
        : null,
    completedAt: order.status == OrderStatus.delivered
        ? order.deliveredAt
        : null,
    amountToCollectVnd: order.totalCodVnd,
    attemptCount: order.deliveryAttemptCount,
    latestAttempt: null,
    failureReason: null,
  );
}

CodSummary _codSummary({required int index, required Order order}) {
  final received = order.status == OrderStatus.delivered;
  final collected = received || order.status == OrderStatus.delivering;
  return CodSummary(
    orderId: order.id,
    shipperId: collected ? _uuid(920 + index) : null,
    status: received
        ? CodStatus.received
        : collected
        ? CodStatus.collected
        : CodStatus.uncollected,
    expectedAmountVnd: order.totalCodVnd,
    collectedAmountVnd: collected ? order.totalCodVnd : 0,
    receivedAmountVnd: received ? order.totalCodVnd : 0,
    collectedAt: collected
        ? order.placedAt.add(const Duration(hours: 5))
        : null,
    collectedBy: collected ? _uuid(920 + index) : null,
    handedOverAt: received ? order.deliveredAt : null,
    receivedAt: received ? order.deliveredAt : null,
    receivedBy: received ? notification_fixtures.fixtureManagerId : null,
  );
}

Order _replaceOrder(
  Order source, {
  required OrderStatus status,
  required String? cancelReason,
  required DateTime updatedAt,
}) {
  return Order(
    id: source.id,
    customerId: source.customerId,
    requestId: source.requestId,
    status: status,
    recipientName: source.recipientName,
    recipientPhone: source.recipientPhone,
    addressDetail: source.addressDetail,
    latitude: source.latitude,
    longitude: source.longitude,
    subtotalVnd: source.subtotalVnd,
    deliveryFeeVnd: source.deliveryFeeVnd,
    totalCodVnd: source.totalCodVnd,
    deliveryAttemptCount: source.deliveryAttemptCount,
    placedAt: source.placedAt,
    confirmedAt: status == OrderStatus.pendingConfirmation
        ? null
        : source.confirmedAt,
    source: status == OrderStatus.pendingConfirmation ? null : source.source,
    confirmedBy: status == OrderStatus.pendingConfirmation
        ? null
        : source.confirmedBy,
    deliveredAt: status == OrderStatus.delivered ? source.deliveredAt : null,
    cancelReason: cancelReason,
    createdAt: source.createdAt,
    updatedAt: updatedAt,
  );
}

String _uuid(int suffix) =>
    '90000000-0000-4000-8000-${suffix.toString().padLeft(12, '0')}';
