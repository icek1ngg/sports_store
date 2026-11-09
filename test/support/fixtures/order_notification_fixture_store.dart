// Test fixture only. Never imported by application bootstrap or repositories.
import 'dart:convert';

import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/notifications/domain/models/notification_item.dart';
import 'package:sports_store/features/notifications/domain/models/notification_page.dart';
import 'package:sports_store/features/notifications/domain/models/notification_query.dart';
import 'package:sports_store/features/notifications/domain/models/notification_target.dart';
import 'package:sports_store/features/notifications/domain/repositories/notification_repository.dart';
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
import 'package:sports_store/features/orders/domain/models/return_summary.dart';
import 'package:sports_store/features/orders/domain/repositories/order_repository.dart';

enum FixtureAccount { customerA, managerB, customerC, shipper }

/// Isolated, deterministic memory only. No production adapter is constructed.
class OrderNotificationFixtureStore {
  OrderNotificationFixtureStore({
    FixtureAccount account = FixtureAccount.customerA,
  }) {
    _account = account;
    _seed();
  }

  static const customerAId = '10000000-0000-4000-8000-000000000001';
  static const managerBId = '10000000-0000-4000-8000-000000000002';
  static const customerCId = '10000000-0000-4000-8000-000000000003';
  static const shipperId = '10000000-0000-4000-8000-000000000004';
  static String orderId(int index) => _uuid(index);
  static final seedTime = DateTime.utc(2026, 11, 8, 8);
  late FixtureAccount _account;
  String? _localCustomerId;
  int _generation = 0;
  bool _sessionActive = true;
  int _tick = 0;
  int _revision = 0;
  final _records = <String, _Record>{};
  final _notifications = <String, NotificationItem>{};
  final _operations = <String, _SavedOperation>{};
  final _pending = <String, Map<String, StableOrderCommand>>{};
  late final OrderRepository orders = _FixtureOrders(this);
  late final NotificationRepository notifications = _FixtureNotifications(this);
  late final NotificationTargetResolver targetResolver = _FixtureNotifications(
    this,
  );

  FixtureAccount get account => _account;
  SessionScope get session => !_sessionActive
      ? SessionScope(
          userId: null,
          role: null,
          generation: _generation,
          roleResolved: false,
        )
      : SessionScope(
          userId:
              _localCustomerId ??
              switch (_account) {
                FixtureAccount.customerA => customerAId,
                FixtureAccount.managerB => managerBId,
                FixtureAccount.customerC => customerCId,
                FixtureAccount.shipper => shipperId,
              },
          role: _account == FixtureAccount.managerB
              ? 'manager'
              : _account == FixtureAccount.shipper
              ? 'shipper'
              : 'customer',
          generation: _generation,
        );
  PendingOrderCommandStore get pendingCommands =>
      _FixturePending(this, session);

  /// Optional local commerce observer. Called once only for a terminal release.
  void Function(String orderId)? onInventoryRelease;
  bool enableLocalReturns = false;

  void addLocalReturnSummary(String orderId, ReturnSummary summary) {
    final record = _accessible(orderId, session);
    if (summary.orderId != orderId ||
        (session.role == 'customer' &&
            !_capabilities(record, session).canOpenReturnCreation)) {
      throw const AppFailure(code: AppFailure.invalidArgument);
    }
    record.returns.removeWhere((r) => r.returnId == summary.returnId);
    record.returns.add(summary);
    _revision++;
  }

  void publishLocalReturnEvent({
    required String orderId,
    required String returnId,
    required String eventId,
    required String title,
    required bool toManager,
  }) {
    final record = _accessible(orderId, session);
    if (!record.returns.any((r) => r.returnId == returnId) ||
        (toManager ? session.role != 'customer' : session.role != 'manager')) {
      throw const AppFailure(code: AppFailure.forbiddenOrUnavailable);
    }
    final recipient = toManager ? managerBId : record.order.customerId;
    if (_notifications.values.any(
      (n) => n.recipientId == recipient && n.eventId == eventId,
    )) {
      return;
    }
    _tick++;
    _revision++;
    final id = _uuid(7000 + _notifications.length);
    _notifications[id] = NotificationItem(
      id: id,
      recipientId: recipient,
      eventId: eventId,
      subjectType: NotificationSubjectType.returnRequest,
      subjectId: returnId,
      title: title,
      body: 'Yêu cầu trả hàng · ${record.order.recipientName}',
      readAt: null,
      createdAt: _now,
    );
  }

  OrderDetails localOperationalOrder(String orderId) {
    final record = _records[orderId];
    if (record == null ||
        (session.role != 'manager' &&
            !(session.role == 'shipper' &&
                record.delivery?.assignedShipperId == session.userId))) {
      throw const AppFailure(code: AppFailure.forbiddenOrUnavailable);
    }
    return _details(record, session);
  }

  /// Joins local checkout to the same Orders/Notifications aggregate used by UI.
  void addCheckoutOrder(Order order, List<OrderItem> items, String eventId) {
    if (session.role != 'customer' ||
        order.customerId != session.userId ||
        order.status != OrderStatus.pendingConfirmation ||
        _records.containsKey(order.id) ||
        items.isEmpty ||
        items.any((item) => item.orderId != order.id) ||
        items.fold<int>(0, (sum, item) => sum + item.lineTotalVnd) !=
            order.subtotalVnd) {
      throw const AppFailure(code: AppFailure.invalidArgument);
    }
    final placedTick = order.placedAt.difference(seedTime).inSeconds;
    if (placedTick > _tick) _tick = placedTick;
    _tick++;
    _revision++;
    _records[order.id] = _Record(order, List.of(items), null, null, [
      _event(
        order,
        eventId,
        'order_placed',
        null,
        OrderStatus.pendingConfirmation,
        order.placedAt,
        order.customerId,
        null,
      ),
    ], true);
    _notify(managerBId, eventId, order, 'Có đơn hàng mới');
  }

  DateTime get _now => seedTime.add(Duration(seconds: _tick));

  void switchAccount(FixtureAccount account) {
    _sessionActive = true;
    _localCustomerId = null;
    _account = account;
    _generation++;
  }

  void switchLocalCustomer(String userId) {
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(userId)) {
      throw const AppFailure(code: AppFailure.invalidArgument);
    }
    _account = FixtureAccount.customerA;
    _sessionActive = true;
    _localCustomerId = userId;
    _generation++;
  }

  void suspendSession() {
    _sessionActive = false;
    _generation++;
  }

  void reset() {
    _generation++;
    _revision++;
    _tick = 0;
    _records.clear();
    _notifications.clear();
    _operations.clear();
    _pending.clear();
    _seed();
  }

  Future<SessionScope> _capture() async {
    final captured = session;
    await Future<void>.delayed(Duration.zero);
    _check(captured);
    return captured;
  }

  void _check(SessionScope captured) {
    if (captured != session) {
      throw const AppFailure(code: AppFailure.unauthenticated);
    }
  }

  _Record _accessible(String id, SessionScope scope) {
    final record = _records[id];
    if (!{'customer', 'manager'}.contains(scope.role) ||
        record == null ||
        (scope.role != 'manager' && record.order.customerId != scope.userId)) {
      throw const AppFailure(code: AppFailure.forbiddenOrUnavailable);
    }
    return record;
  }

  OrderCapabilities _capabilities(_Record record, SessionScope scope) {
    final pending = record.order.status == OrderStatus.pendingConfirmation;
    final manager = scope.role == 'manager';
    return OrderCapabilities(
      canCancelCustomer: !manager && pending,
      canConfirm: manager && pending,
      canReject: manager && pending,
      canCancelExceptional:
          manager &&
          record.neverAssigned &&
          {
            OrderStatus.preparing,
            OrderStatus.awaitingPickup,
          }.contains(record.order.status),
      canAssign: false,
      canReassign: false,
      canArrangeSecondAttempt: false,
      canRequestEarlyReturn: false,
      canReceiveUndelivered: false,
      canOpenReturnCreation:
          enableLocalReturns &&
          scope.role == 'customer' &&
          record.order.status == OrderStatus.delivered &&
          record.order.deliveredAt != null &&
          _now.difference(record.order.deliveredAt!) <=
              const Duration(days: 7) &&
          !record.returns.any((r) => r.isActive),
    );
  }

  OrderDetails _details(_Record record, SessionScope scope) => OrderDetails(
    order: record.order,
    items: record.items,
    buyer: scope.role == 'manager'
        ? Buyer(
            id: record.order.customerId,
            fullName: record.order.recipientName,
          )
        : null,
    deliverySummary: record.delivery,
    codSummary: record.cod,
    returnSummaries: record.returns,
    timeline: record.timeline,
    historyComplete: record.timeline.every(
      (entry) => entry.source == TimelineSource.actualEvent,
    ),
    capabilities: _capabilities(record, scope),
    asOf: _now,
  );

  OrderSummary _summary(_Record record, SessionScope scope) => OrderSummary(
    order: record.order,
    itemPreview: record.items.take(2).toList(),
    itemLineCount: record.items.length,
    itemQuantityTotal: record.items.fold(0, (sum, item) => sum + item.quantity),
    customerDisplayName: record.order.recipientName,
    deliverySummary: record.delivery,
    codSummary: record.cod,
    returnSummary: record.returns.lastOrNull,
    warnings: const [],
    capabilities: _capabilities(record, scope),
  );

  String _cursor(String key, int offset) => base64Url.encode(
    utf8.encode(
      jsonEncode([session.userId, _generation, _revision, key, offset]),
    ),
  );

  int _offset(String? cursor, String key) {
    if (cursor == null) return 0;
    try {
      final data = jsonDecode(utf8.decode(base64Url.decode(cursor))) as List;
      if (data.length == 5 &&
          data[0] == session.userId &&
          data[1] == _generation &&
          data[2] == _revision &&
          data[3] == key &&
          data[4] is int &&
          (data[4] as int) >= 0) {
        return data[4] as int;
      }
    } catch (_) {
      // Opaque cursors from another account/query are never accepted.
    }
    throw const AppFailure(code: AppFailure.invalidCursor);
  }

  void _notify(
    String recipient,
    String event,
    Order order,
    String title, {
    bool read = false,
  }) {
    final key = '$recipient:$event';
    if (_notifications.values.any(
      (n) => '${n.recipientId}:${n.eventId}' == key,
    )) {
      return;
    }
    final id = _uuid(7000 + _notifications.length);
    _notifications[id] = NotificationItem(
      id: id,
      recipientId: recipient,
      eventId: event,
      subjectType: NotificationSubjectType.order,
      subjectId: order.id,
      title: title,
      body:
          'Đơn hàng ${order.id.substring(order.id.length - 4)} · ${order.recipientName}',
      readAt: read ? _now : null,
      createdAt: _now,
    );
  }

  void _seed() {
    const statuses = [
      OrderStatus.pendingConfirmation,
      OrderStatus.pendingConfirmation,
      OrderStatus.pendingConfirmation,
      OrderStatus.preparing,
      OrderStatus.awaitingPickup,
      OrderStatus.delivering,
      OrderStatus.delivered,
      OrderStatus.cancelled,
      OrderStatus.rejected,
      OrderStatus.pendingConfirmation,
      OrderStatus.delivered,
    ];
    for (var i = 0; i < statuses.length; i++) {
      final id = orderId(i + 1);
      final status = statuses[i];
      final customer = i >= 9 ? customerCId : customerAId;
      final time = seedTime.subtract(Duration(hours: i + 1));
      final confirmed = !{
        OrderStatus.pendingConfirmation,
        OrderStatus.cancelled,
        OrderStatus.rejected,
      }.contains(status);
      final delivered = status == OrderStatus.delivered;
      final hasCustody = status == OrderStatus.delivering || delivered;
      final assigned = status == OrderStatus.awaitingPickup || hasCustody;
      final order = Order(
        id: id,
        customerId: customer,
        requestId: _uuid(1000 + i),
        status: status,
        recipientName: customer == customerAId
            ? 'Nguyễn Minh Anh'
            : 'Trần Thu Chi',
        recipientPhone: customer == customerAId ? '0901234567' : '0912345678',
        addressDetail: customer == customerAId
            ? '12 Phố Huế, Hai Bà Trưng, Hà Nội'
            : '28 Cầu Giấy, Hà Nội',
        latitude: 21.018,
        longitude: 105.851,
        subtotalVnd: 450000 + i * 50000,
        deliveryFeeVnd: 30000,
        totalCodVnd: 480000 + i * 50000,
        deliveryAttemptCount: hasCustody ? 1 : 0,
        placedAt: time,
        confirmedAt: confirmed ? time.add(const Duration(minutes: 10)) : null,
        source: confirmed ? OrderConfirmationSource.manager : null,
        confirmedBy: confirmed ? managerBId : null,
        deliveredAt: delivered ? time.add(const Duration(minutes: 40)) : null,
        cancelReason: status == OrderStatus.cancelled
            ? 'Khách hàng đổi kế hoạch'
            : null,
        createdAt: time,
        updatedAt: time.add(const Duration(minutes: 40)),
      );
      final items = [
        OrderItem(
          id: _uuid(2000 + i),
          orderId: id,
          productId: _uuid(3000 + i),
          variantId: _uuid(4000 + i),
          productName: ['Giày chạy bộ', 'Áo thể thao', 'Vợt cầu lông'][i % 3],
          variantLabel: 'Xanh navy · ${i % 2 == 0 ? '42' : 'M'}',
          attributes: const {'color': 'Xanh navy'},
          unitPriceVnd: order.subtotalVnd,
          quantity: 1,
          lineTotalVnd: order.subtotalVnd,
          createdAt: time,
        ),
      ];
      final cod = CodSummary(
        orderId: id,
        shipperId: assigned ? shipperId : null,
        status: delivered ? CodStatus.collected : CodStatus.uncollected,
        expectedAmountVnd: order.totalCodVnd,
        collectedAmountVnd: delivered ? order.totalCodVnd : 0,
        receivedAmountVnd: 0,
        collectedAt: order.deliveredAt,
        collectedBy: delivered ? shipperId : null,
        handedOverAt: null,
        receivedAt: null,
        receivedBy: null,
      );
      final delivery = DeliverySummary(
        taskId: assigned ? _uuid(5000 + i) : null,
        kind: DeliveryTaskKind.outbound,
        taskStatus: delivered
            ? DeliveryTaskStatus.delivered
            : hasCustody
            ? DeliveryTaskStatus.inTransit
            : assigned
            ? DeliveryTaskStatus.assigned
            : DeliveryTaskStatus.pendingAssignment,
        assignedShipperId: assigned ? shipperId : null,
        assignedShipperName: assigned ? 'Lê Văn Nam' : null,
        assignedAt: assigned ? time.add(const Duration(minutes: 15)) : null,
        acceptedAt: hasCustody ? time.add(const Duration(minutes: 20)) : null,
        startedAt: hasCustody ? time.add(const Duration(minutes: 25)) : null,
        completedAt: order.deliveredAt,
        amountToCollectVnd: order.totalCodVnd,
        attemptCount: order.deliveryAttemptCount,
        latestAttempt: null,
        failureReason: null,
      );
      final timeline = <OrderTimelineEntry>[
        _event(
          order,
          _uuid(6000 + i),
          'order_placed',
          null,
          OrderStatus.pendingConfirmation,
          time,
          customer,
          null,
        ),
        if (confirmed)
          _event(
            order,
            _uuid(6100 + i),
            'order_confirmed_manual',
            OrderStatus.pendingConfirmation,
            OrderStatus.preparing,
            order.confirmedAt!,
            managerBId,
            null,
          ),
        if (status != OrderStatus.pendingConfirmation &&
            status != OrderStatus.preparing)
          OrderTimelineEntry(
            eventId: null,
            sourceEntityType: TimelineEntityType.order,
            sourceEntityId: id,
            eventKind: 'snapshot_milestone',
            fromState: null,
            toState: status.wireValue,
            actorId: null,
            actorLabel: null,
            actorSource: TimelineActorSource.unknown,
            occurredAt: order.updatedAt,
            reason: status == OrderStatus.rejected
                ? 'Không thể đáp ứng đơn hàng'
                : order.cancelReason,
            source: TimelineSource.snapshotMilestone,
          ),
      ];
      _records[id] = _Record(
        order,
        items,
        assigned ? cod : null,
        {OrderStatus.cancelled, OrderStatus.rejected}.contains(status)
            ? null
            : delivery,
        timeline,
        !assigned,
      );
      _notify(
        customer,
        _uuid(8000 + i),
        order,
        'Cập nhật đơn hàng',
        read: i.isEven,
      );
      _notify(
        managerBId,
        _uuid(8000 + i),
        order,
        'Đơn hàng cần theo dõi',
        read: i.isOdd,
      );
    }
  }
}

String _uuid(int n) =>
    '20000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

OrderTimelineEntry _event(
  Order order,
  String eventId,
  String kind,
  OrderStatus? from,
  OrderStatus to,
  DateTime time,
  String actor,
  String? reason,
) => OrderTimelineEntry(
  eventId: eventId,
  sourceEntityType: TimelineEntityType.order,
  sourceEntityId: order.id,
  eventKind: kind,
  fromState: from?.wireValue,
  toState: to.wireValue,
  actorId: actor,
  actorLabel: null,
  actorSource: actor == OrderNotificationFixtureStore.managerBId
      ? TimelineActorSource.manager
      : TimelineActorSource.customer,
  occurredAt: time,
  reason: reason,
  source: TimelineSource.actualEvent,
);

class _Record {
  _Record(
    this.order,
    this.items,
    this.cod,
    this.delivery,
    this.timeline,
    this.neverAssigned,
  );
  Order order;
  final List<OrderItem> items;
  final CodSummary? cod;
  DeliverySummary? delivery;
  final List<OrderTimelineEntry> timeline;
  final bool neverAssigned;
  bool stockReleased = false;
  final List<ReturnSummary> returns = [];
}

class _SavedOperation {
  _SavedOperation(this.actor, this.command, this.result);
  final String actor;
  final StableOrderCommand command;
  final OperationResult result;
}

class _FixtureOrders implements OrderRepository {
  _FixtureOrders(this.store);
  final OrderNotificationFixtureStore store;

  @override
  Future<OrderPage> getCustomerOrders(OrderQuery query) => _page(query, false);
  @override
  Future<OrderPage> getManagerOrders(OrderQuery query) => _page(query, true);
  Future<OrderPage> _page(OrderQuery query, bool manager) async {
    final scope = await store._capture();
    if ((scope.role == 'manager') != manager ||
        !{'customer', 'manager'}.contains(scope.role)) {
      throw const AppFailure(code: AppFailure.forbiddenOrUnavailable);
    }
    final search = query.search?.toLowerCase();
    final source =
        store._records.values
            .where(
              (r) =>
                  (manager || r.order.customerId == scope.userId) &&
                  (search == null ||
                      [
                        r.order.id,
                        r.order.recipientName,
                        ...r.items.map((i) => i.productName),
                      ].join(' ').toLowerCase().contains(search)),
            )
            .toList()
          ..sort((a, b) => b.order.placedAt.compareTo(a.order.placedAt));
    final counts = {
      for (final status in OrderStatus.values)
        status: source.where((r) => r.order.status == status).length,
    };
    final filtered = source
        .where(
          (r) =>
              query.statuses.isEmpty || query.statuses.contains(r.order.status),
        )
        .toList();
    final key = jsonEncode([
      'orders',
      manager,
      search,
      query.statuses.map((s) => s.wireValue).toList(),
      query.limit,
    ]);
    final offset = store._offset(query.cursor, key);
    if (offset > filtered.length) {
      throw const AppFailure(code: AppFailure.invalidCursor);
    }
    final items = filtered
        .skip(offset)
        .take(query.limit)
        .map((r) => store._summary(r, scope))
        .toList();
    final next = offset + items.length;
    return OrderPage(
      items: items,
      nextCursor: next < filtered.length ? store._cursor(key, next) : null,
      totalCount: filtered.length,
      statusCounts: counts,
      asOf: store._now,
    );
  }

  @override
  Future<OrderDetails> getOrderDetails(String orderId) async {
    final scope = await store._capture();
    return store._details(store._accessible(orderId, scope), scope);
  }

  @override
  Future<OrderMutationReceipt> confirm(StableOrderCommand command) =>
      _mutate(command, OrderOperation.confirm);
  @override
  Future<OrderMutationReceipt> reject(StableOrderCommand command) =>
      _mutate(command, OrderOperation.reject);
  @override
  Future<OrderMutationReceipt> cancelCustomer(StableOrderCommand command) =>
      _mutate(command, OrderOperation.customerCancel);
  @override
  Future<OrderMutationReceipt> cancelManager(StableOrderCommand command) =>
      _mutate(command, OrderOperation.managerCancel);

  Future<OrderMutationReceipt> _mutate(
    StableOrderCommand command,
    OrderOperation expected,
  ) async {
    final scope = await store._capture();
    if (command.operation != expected) {
      throw const AppFailure(code: AppFailure.invalidArgument);
    }
    final manager = scope.role == 'manager';
    if ((expected != OrderOperation.customerCancel) != manager) {
      throw const AppFailure(code: AppFailure.forbiddenOrUnavailable);
    }
    final record = store._accessible(command.orderId, scope);
    final key = '${scope.userId}:${command.requestId}';
    final saved = store._operations[key];
    if (saved != null) {
      if (saved.command.orderId != command.orderId ||
          saved.command.operation != command.operation ||
          saved.command.reason != command.reason) {
        throw const AppFailure(code: AppFailure.idempotencyConflict);
      }
      if (saved.result.failure != null) throw saved.result.failure!;
      return _replay(saved.result.receipt!);
    }
    final caps = store._capabilities(record, scope);
    final allowed = switch (expected) {
      OrderOperation.confirm => caps.canConfirm,
      OrderOperation.reject => caps.canReject,
      OrderOperation.customerCancel => caps.canCancelCustomer,
      OrderOperation.managerCancel => caps.canCancelExceptional,
      _ => false,
    };
    if (!allowed) {
      final failure = AppFailure(
        code:
            expected == OrderOperation.customerCancel ||
                expected == OrderOperation.managerCancel
            ? AppFailure.cancellationNotAllowed
            : AppFailure.stateChanged,
        currentOrderRef: OrderStateReference(
          id: record.order.id,
          status: record.order.status.wireValue,
        ),
      );
      store._operations[key] = _SavedOperation(
        scope.userId!,
        command,
        OperationResult.failed(failure),
      );
      throw failure;
    }
    store._tick++;
    store._revision++;
    final previous = record.order;
    final status = expected == OrderOperation.confirm
        ? OrderStatus.preparing
        : expected == OrderOperation.reject
        ? OrderStatus.rejected
        : OrderStatus.cancelled;
    record.order = _updated(
      previous,
      status,
      store._now,
      scope.userId!,
      command.reason,
    );
    if (status != OrderStatus.preparing) {
      record.stockReleased = true;
      record.delivery = null;
      store.onInventoryRelease?.call(record.order.id);
    }
    final eventId = _uuid(10000 + store._operations.length);
    record.timeline.add(
      _event(
        record.order,
        eventId,
        expected == OrderOperation.confirm
            ? 'order_confirmed_manual'
            : expected == OrderOperation.reject
            ? 'order_rejected'
            : 'order_cancelled',
        previous.status,
        status,
        store._now,
        scope.userId!,
        command.reason,
      ),
    );
    final receipt = OrderMutationReceipt(
      operation: expected,
      requestId: command.requestId,
      eventId: eventId,
      order: record.order,
      committedAt: store._now,
      replayed: false,
      currentOrder: null,
    );
    store._operations[key] = _SavedOperation(
      scope.userId!,
      command,
      OperationResult.committed(receipt),
    );
    store._notify(
      record.order.customerId,
      eventId,
      record.order,
      'Đơn hàng đã cập nhật',
    );
    return receipt;
  }

  @override
  Future<OperationResult> getOperationResult({
    required String requestId,
    required String orderId,
    required OrderOperation operation,
  }) async {
    final scope = await store._capture();
    store._accessible(orderId, scope);
    final saved = store._operations['${scope.userId}:$requestId'];
    if (saved == null ||
        saved.command.orderId != orderId ||
        saved.command.operation != operation) {
      return const OperationResult.notFound();
    }
    return saved.result.receipt == null
        ? saved.result
        : OperationResult.committed(_replay(saved.result.receipt!));
  }
}

OrderMutationReceipt _replay(OrderMutationReceipt r) => OrderMutationReceipt(
  operation: r.operation,
  requestId: r.requestId,
  eventId: r.eventId,
  order: r.order,
  committedAt: r.committedAt,
  replayed: true,
  currentOrder: null,
);

Order _updated(
  Order o,
  OrderStatus status,
  DateTime at,
  String actor,
  String? reason,
) => Order(
  id: o.id,
  customerId: o.customerId,
  requestId: o.requestId,
  status: status,
  recipientName: o.recipientName,
  recipientPhone: o.recipientPhone,
  addressDetail: o.addressDetail,
  latitude: o.latitude,
  longitude: o.longitude,
  subtotalVnd: o.subtotalVnd,
  deliveryFeeVnd: o.deliveryFeeVnd,
  totalCodVnd: o.totalCodVnd,
  deliveryAttemptCount: o.deliveryAttemptCount,
  placedAt: o.placedAt,
  confirmedAt: status == OrderStatus.preparing ? at : o.confirmedAt,
  source: status == OrderStatus.preparing
      ? OrderConfirmationSource.manager
      : o.source,
  confirmedBy: status == OrderStatus.preparing ? actor : o.confirmedBy,
  deliveredAt: o.deliveredAt,
  cancelReason: status == OrderStatus.cancelled
      ? reason ?? 'Khách hàng hủy đơn'
      : null,
  createdAt: o.createdAt,
  updatedAt: at,
);

class _FixtureNotifications
    implements NotificationRepository, NotificationTargetResolver {
  _FixtureNotifications(this.store);
  final OrderNotificationFixtureStore store;
  List<NotificationItem> _own(SessionScope scope) =>
      store._notifications.values
          .where((n) => n.recipientId == scope.userId)
          .toList()
        ..sort((a, b) {
          final time = b.createdAt.compareTo(a.createdAt);
          return time == 0 ? b.id.compareTo(a.id) : time;
        });
  NotificationItem _find(String id, SessionScope scope) {
    final item = store._notifications[id];
    if (item == null || item.recipientId != scope.userId) {
      throw const AppFailure(code: AppFailure.forbiddenOrUnavailable);
    }
    return item;
  }

  @override
  Future<NotificationPage> getPage(NotificationQuery query) async {
    final scope = await store._capture();
    final own = _own(scope);
    final filtered = own
        .where((n) => query.filter == NotificationFilter.all || !n.isRead)
        .toList();
    final key = jsonEncode([
      'notifications',
      query.filter.wireValue,
      query.limit,
    ]);
    final offset = store._offset(query.cursor, key);
    if (offset > filtered.length) {
      throw const AppFailure(code: AppFailure.invalidCursor);
    }
    final items = filtered.skip(offset).take(query.limit).toList();
    final next = offset + items.length;
    return NotificationPage(
      items: items,
      nextCursor: next < filtered.length ? store._cursor(key, next) : null,
      unreadCount: own.where((n) => !n.isRead).length,
      asOf: store._now,
    );
  }

  @override
  Future<int> getUnreadCount() async =>
      _own(await store._capture()).where((n) => !n.isRead).length;
  @override
  Future<NotificationItem> markRead(String notificationId) async {
    final scope = await store._capture();
    final item = _find(notificationId, scope);
    if (item.isRead) return item;
    store._tick++;
    // Cursor ordering is unchanged for the all filter, but unread rows changed.
    store._revision++;
    final result = NotificationItem(
      id: item.id,
      recipientId: item.recipientId,
      eventId: item.eventId,
      subjectType: item.subjectType,
      subjectId: item.subjectId,
      title: item.title,
      body: item.body,
      readAt: store._now,
      createdAt: item.createdAt,
    );
    store._notifications[item.id] = result;
    return result;
  }

  @override
  Future<NotificationTargetDecision> resolve(String notificationId) async {
    final scope = await store._capture();
    try {
      final item = _find(notificationId, scope);
      if (item.subjectType == NotificationSubjectType.returnRequest) {
        final records = store._records.values.where(
          (r) => r.returns.any((summary) => summary.returnId == item.subjectId),
        );
        if (records.length != 1) {
          return const NotificationTargetDecision.unavailable();
        }
        store._accessible(records.single.order.id, scope);
        return NotificationTargetDecision(
          available: true,
          screen: scope.role == 'manager'
              ? NotificationTargetScreen.managerReturn
              : NotificationTargetScreen.customerReturn,
          entityId: item.subjectId,
          mode: NotificationTargetMode.returnRequest,
        );
      }
      store._accessible(item.subjectId, scope);
      return NotificationTargetDecision(
        available: true,
        screen: scope.role == 'manager'
            ? NotificationTargetScreen.managerOrder
            : NotificationTargetScreen.customerOrder,
        entityId: item.subjectId,
        mode: NotificationTargetMode.order,
      );
    } on AppFailure {
      return const NotificationTargetDecision.unavailable();
    }
  }
}

class _FixturePending implements PendingOrderCommandStore {
  _FixturePending(this.store, this.scope);
  final OrderNotificationFixtureStore store;
  final SessionScope scope;
  Future<void> _guard() async {
    await Future<void>.delayed(Duration.zero);
    store._check(scope);
  }

  Map<String, StableOrderCommand> get _commands =>
      store._pending.putIfAbsent(scope.userId!, () => {});
  @override
  Future<void> save(StableOrderCommand command) async {
    await _guard();
    final previous = _commands[command.requestId];
    if (previous != null &&
        (previous.orderId != command.orderId ||
            previous.operation != command.operation ||
            previous.reason != command.reason)) {
      throw const AppFailure(code: AppFailure.idempotencyConflict);
    }
    _commands[command.requestId] = command;
  }

  @override
  Future<List<StableOrderCommand>> list() async {
    await _guard();
    return List.unmodifiable(_commands.values);
  }

  @override
  Future<void> remove(String requestId) async {
    await _guard();
    _commands.remove(requestId);
  }
}
