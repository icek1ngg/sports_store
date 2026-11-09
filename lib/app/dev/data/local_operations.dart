import 'dart:convert';

import '../../demo/data/local_demo_store.dart';
import '../../../../features/deliveries/domain/models/delivery_task.dart';
import '../../../../features/deliveries/domain/models/delivery_task_details.dart';
import '../../../../features/deliveries/domain/models/delivery_task_query.dart';
import '../../../../features/deliveries/domain/models/operational_failure.dart';
import '../../../../features/deliveries/domain/repositories/delivery_repository.dart';
import '../../../../features/cod/domain/models/cod_collection.dart';
import '../../../../features/cod/domain/models/cod_collection_page.dart';
import '../../../../features/cod/domain/models/cod_collection_query.dart';
import '../../../../features/cod/domain/repositories/cod_repository.dart';
import '../../../../features/orders/domain/models/order_details.dart';
import '../../../../features/orders/domain/models/return_summary.dart';
import '../../../../features/deliveries/domain/models/outbound_task_command.dart';
import '../../../../features/deliveries/domain/models/outbound_completion_command.dart';
import '../../../../features/deliveries/domain/models/outbound_failure_command.dart';
import '../../../../features/deliveries/domain/models/outbound_retry_command.dart';
import '../../../../features/deliveries/domain/models/return_pickup_command.dart';
import '../../../../features/deliveries/domain/models/redelivery_command.dart';
import '../../../../features/deliveries/domain/models/delivery_reporting.dart';
import '../../../../features/deliveries/domain/repositories/outbound_task_command_repository.dart';
import '../../../../features/deliveries/domain/repositories/outbound_completion_repository.dart';
import '../../../../features/deliveries/domain/repositories/outbound_failure_repository.dart';
import '../../../../features/deliveries/domain/repositories/outbound_retry_repository.dart';
import '../../../../features/deliveries/domain/repositories/return_pickup_repository.dart';
import '../../../../features/deliveries/domain/repositories/redelivery_repository.dart';
import '../../../../features/deliveries/domain/repositories/delivery_reporting_repository.dart';
import '../../../../features/cod/domain/models/cod_receipt.dart';
import '../../../../features/cod/domain/repositories/cod_receipt_repository.dart';
import '../../../../features/returns/domain/models/return_request_context.dart';
import '../../../../features/returns/domain/models/return_request_submission.dart';
import '../../../../features/returns/domain/models/return_request_failure.dart';
import '../../../../features/returns/domain/models/return_tracking.dart';
import '../../../../features/returns/domain/models/manager_return.dart';
import '../../../../features/returns/domain/repositories/return_request_repository.dart';
import '../../../../features/returns/domain/repositories/return_tracking_repository.dart';
import '../../../../features/returns/domain/repositories/manager_return_repository.dart';

/// Local read projections over the same Orders aggregate, never a Cloud client.
/// Custody/financial writes deliberately remain unavailable until their local
/// transaction implementation can update every affected aggregate together.
class LocalOperations
    implements DeliveryRepository, DeliveryMapReader, CodRepository {
  LocalOperations(this.store);
  final LocalDemoStore store;

  void _guard() {
    if (!{'shipper', 'manager'}.contains(store.session.role)) {
      throw const OperationalFailure(OperationalFailureCode.permissionDenied);
    }
  }

  List<OrderDetails> _orders() {
    _guard();
    final result = <OrderDetails>[];
    for (final i in [5, 6, 7, 11]) {
      try {
        result.add(store.localOperationalOrder(LocalDemoStore.orderId(i)));
      } catch (_) {
        /* Foreign assignments are absent from the projection. */
      }
    }
    return result;
  }

  DeliveryTaskDetails _project(OrderDetails details) {
    final order = details.order;
    final delivery = details.deliverySummary!;
    final cod = details.codSummary;
    final terminal = delivery.completedAt != null;
    return DeliveryTaskDetails(
      task: DeliveryTaskSnapshot(
        taskId: delivery.taskId!,
        kind: DeliveryTaskKind.outbound,
        status: DeliveryTaskStatus.fromValue(delivery.taskStatus!.wireValue),
        attemptNumber: delivery.attemptCount == 0 ? 1 : delivery.attemptCount,
        scope: terminal
            ? DeliverySnapshotScope.history
            : DeliverySnapshotScope.current,
        orderId: order.id,
        amountToCollectVnd: order.totalCodVnd,
        destination: DeliveryDestination(
          name: order.recipientName,
          phone: order.recipientPhone,
          address: order.addressDetail,
          latitude: order.latitude,
          longitude: order.longitude,
        ),
        assignedAt: delivery.assignedAt,
        acceptedAt: delivery.acceptedAt,
        startedAt: delivery.startedAt,
        completedAt: delivery.completedAt,
        itemSource: DeliveryItemSource.orderSnapshot,
      ),
      items: details.items
          .map(
            (item) => DeliveryTaskItem(
              itemId: item.id,
              itemSource: DeliveryItemSource.orderSnapshot,
              productName: item.productName,
              variantLabel: item.variantLabel,
              quantity: item.quantity,
              unitPriceVnd: item.unitPriceVnd,
              lineTotalVnd: item.lineTotalVnd,
            ),
          )
          .toList(),
      asOf: LocalDemoStore.seedTime,
      cod: cod == null
          ? null
          : DeliveryCodSnapshot(
              status: DeliveryCodStatus.fromValue(cod.status.wireValue),
              expectedAmountVnd: cod.expectedAmountVnd,
              collectedAmountVnd: cod.collectedAmountVnd,
              receivedAmountVnd: cod.receivedAmountVnd,
              collectedAt: cod.collectedAt,
              handedOverAt: cod.handedOverAt,
              receivedAt: cod.receivedAt,
            ),
    );
  }

  @override
  Future<List<DeliveryTaskSnapshot>> listTasks() async =>
      _orders().map(_project).map((details) => details.task).toList();

  @override
  Future<DeliveryTaskDetails> getTaskDetails(String taskId) async {
    for (final details in _orders()) {
      if (details.deliverySummary?.taskId == taskId) return _project(details);
    }
    throw const OperationalFailure(OperationalFailureCode.permissionDenied);
  }

  @override
  Future<DeliveryTaskDetails> getMapTaskDetails(String taskId) =>
      getTaskDetails(taskId);
  @override
  Future<DeliveryTaskSnapshot> getTask(String taskId) async =>
      (await getTaskDetails(taskId)).task;

  DeliveryTaskStateGroup _group(DeliveryTaskSnapshot item) =>
      switch (item.status) {
        DeliveryTaskStatus.assigned ||
        DeliveryTaskStatus.accepted => DeliveryTaskStateGroup.waiting,
        DeliveryTaskStatus.inTransit => DeliveryTaskStateGroup.inTransit,
        DeliveryTaskStatus.delivered ||
        DeliveryTaskStatus.returnedToStore => DeliveryTaskStateGroup.completed,
        _ => DeliveryTaskStateGroup.failed,
      };
  @override
  Future<DeliveryTaskPage> queryTasks(DeliveryTaskQuery query) async {
    final all = (await listTasks())
        .where(
          (task) =>
              (query.kind == null || task.kind == query.kind) &&
              (query.query == null ||
                  '${task.orderId} ${task.destination?.name} ${task.destination?.address}'
                      .toLowerCase()
                      .contains(query.query!.toLowerCase())),
        )
        .toList();
    int count(DeliveryTaskStateGroup group) =>
        all.where((item) => _group(item) == group).length;
    final filtered = all
        .where(
          (item) =>
              query.stateGroup == null || _group(item) == query.stateGroup,
        )
        .toList();
    final offset = _offset(query.cursor);
    return DeliveryTaskPage(
      items: filtered.skip(offset).take(query.limit).toList(),
      nextCursor: offset + query.limit < filtered.length
          ? '${offset + query.limit}'
          : null,
      filteredTotal: filtered.length,
      counts: DeliveryTaskCounts(
        waiting: count(DeliveryTaskStateGroup.waiting),
        inTransit: count(DeliveryTaskStateGroup.inTransit),
        completed: count(DeliveryTaskStateGroup.completed),
        ungrouped: count(DeliveryTaskStateGroup.failed),
        failed: count(DeliveryTaskStateGroup.failed),
      ),
      asOf: LocalDemoStore.seedTime,
    );
  }

  @override
  Future<List<CodCollection>> listCollections({
    String? shipperId,
    String? orderId,
  }) async {
    _guard();
    if (store.session.role == 'shipper' &&
        shipperId != null &&
        shipperId != store.session.userId) {
      throw const OperationalFailure(OperationalFailureCode.permissionDenied);
    }
    return _orders()
        .where(
          (details) =>
              details.codSummary != null &&
              (orderId == null || details.order.id == orderId) &&
              (shipperId == null || details.codSummary!.shipperId == shipperId),
        )
        .map((details) {
          final cod = details.codSummary!;
          return CodCollection(
            orderId: cod.orderId,
            orderCode: cod.orderId,
            orderCodeSource: 'order_uuid',
            shipperId: cod.shipperId,
            status: CodStatus.fromValue(cod.status.wireValue),
            expectedAmountVnd: cod.expectedAmountVnd,
            collectedAmountVnd: cod.collectedAmountVnd,
            receivedAmountVnd: cod.receivedAmountVnd,
            collectedBy: cod.collectedBy,
            receivedBy: cod.receivedBy,
            collectedAt: cod.collectedAt,
            handedOverAt: cod.handedOverAt,
            receivedAt: cod.receivedAt,
            createdAt: details.order.createdAt,
            updatedAt: details.order.updatedAt,
          );
        })
        .toList();
  }

  @override
  Future<CodCollectionPage> queryCollections(CodCollectionQuery query) async {
    final all = await listCollections(
      shipperId: query.shipperId,
      orderId: query.orderId,
    );
    int count(CodStatus status) =>
        all.where((item) => item.status == status).length;
    final filtered = all
        .where(
          (item) =>
              query.statuses.isEmpty || query.statuses.contains(item.status),
        )
        .toList();
    final offset = _offset(query.cursor);
    return CodCollectionPage(
      items: filtered.skip(offset).take(query.limit).toList(),
      nextCursor: offset + query.limit < filtered.length
          ? '${offset + query.limit}'
          : null,
      filteredTotal: filtered.length,
      counts: CodCollectionCounts(
        all: all.length,
        uncollected: count(CodStatus.uncollected),
        collected: count(CodStatus.collected),
        received: count(CodStatus.received),
      ),
      outstandingVnd: all.fold(
        0,
        (sum, item) => sum + item.outstandingAmountVnd,
      ),
      asOf: LocalDemoStore.seedTime,
    );
  }

  int _offset(String? cursor) {
    if (cursor == null) return 0;
    final value = int.tryParse(cursor);
    if (value == null || value < 0) {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }
    return value;
  }
}

class LocalUnavailableOutbound implements OutboundTaskCommandRepository {
  const LocalUnavailableOutbound();
  @override
  Future<void> execute(OutboundTaskCommand command) async =>
      throw const OutboundCommandFailure(
        OutboundCommandFailureCode.dependencyUnavailable,
      );
}

class LocalUnavailableCompletion implements OutboundCompletionRepository {
  const LocalUnavailableCompletion();
  @override
  Future<void> execute(OutboundCompletionCommand command) async =>
      throw const OutboundCommandFailure(
        OutboundCommandFailureCode.dependencyUnavailable,
      );
}

class LocalUnavailableFailure implements OutboundFailureRepository {
  const LocalUnavailableFailure();
  @override
  Future<OutboundFailureAck> execute(OutboundFailureCommand command) async =>
      throw const OutboundCommandFailure(
        OutboundCommandFailureCode.dependencyUnavailable,
      );
}

class LocalUnavailableRetry implements OutboundRetryRepository {
  const LocalUnavailableRetry();
  @override
  Future<OutboundRetryAck> execute(OutboundRetryCommand command) async =>
      throw const OutboundCommandFailure(
        OutboundCommandFailureCode.dependencyUnavailable,
      );
}

class LocalUnavailablePickup implements ReturnPickupRepository {
  const LocalUnavailablePickup();
  @override
  Future<ReturnPickupAck> execute(ReturnPickupCommand command) async =>
      throw const OutboundCommandFailure(
        OutboundCommandFailureCode.dependencyUnavailable,
      );
}

class LocalUnavailableRedelivery implements RedeliveryRepository {
  const LocalUnavailableRedelivery();
  @override
  Future<RedeliveryAck> execute(RedeliveryCommand command) async =>
      throw const OutboundCommandFailure(
        OutboundCommandFailureCode.dependencyUnavailable,
      );
}

class LocalUnavailableReporting implements DeliveryReportingRepository {
  const LocalUnavailableReporting();
  @override
  Future<ReportingContext> getContext(String taskId) async =>
      throw const OperationalFailure(OperationalFailureCode.backendUnavailable);
  @override
  Future<ReportingAck> execute(ReportingCommand command) async =>
      throw const OperationalFailure(OperationalFailureCode.backendUnavailable);
}

class LocalUnavailableCodReceipt implements CodReceiptRepository {
  const LocalUnavailableCodReceipt();
  @override
  Future<CodReceipt> confirmReceipt(CodReceiptCommand command) async =>
      throw const OperationalFailure(OperationalFailureCode.backendUnavailable);
}

/// Returns share order snapshots; uploaded evidence stays only in process RAM.
/// Pickup/inspection/refund transitions are unavailable, never shortcut ACKs.
class LocalReturns {
  LocalReturns(this.store);
  final LocalDemoStore store;
  final _rows = <String, ManagerReturnDetail>{};
  final _owners = <String, String>{};
  final _videos = <String, ReturnVideoFile>{};
  final _receipts = <String, ReturnRequestReceipt>{};
  final _fingerprints = <String, String>{};
  final _decisions = <String, String>{};
  late final ReturnRequestRepository requests = _LocalReturnRequests(this);
  late final ReturnTrackingRepository tracking = _LocalReturnTracking(this);
  late final ManagerReturnRepository manager = _LocalManagerReturns(this);
  void reset() {
    _rows.clear();
    _owners.clear();
    _videos.clear();
    _receipts.clear();
    _fingerprints.clear();
    _decisions.clear();
  }

  DateTime get now => LocalDemoStore.seedTime.add(const Duration(hours: 1));
  void _requestId(String value) {
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value)) {
      throw const ReturnRequestFailure(ReturnRequestFailureCode.invalidInput);
    }
  }

  ReturnRequestReceipt _replayReceipt(ReturnRequestReceipt value) =>
      ReturnRequestReceipt(
        returnRequestId: value.returnRequestId,
        orderId: value.orderId,
        status: value.status,
        submittedAt: value.submittedAt,
        replayed: true,
      );
  bool _replayed(String requestId, List<Object?> body) {
    _requestId(requestId);
    final saved = _decisions['${store.session.userId}/$requestId'];
    if (saved == null) return false;
    if (saved != jsonEncode(body)) {
      throw const ReturnRequestFailure(
        ReturnRequestFailureCode.idempotencyConflict,
      );
    }
    return true;
  }

  void _commit(
    String requestId,
    List<Object?> body,
    ManagerReturnDetail row,
    String title, {
    bool toManager = false,
  }) {
    _decisions['${store.session.userId}/$requestId'] = jsonEncode(body);
    store.publishLocalReturnEvent(
      orderId: row.orderId,
      returnId: row.returnId,
      eventId: requestId,
      title: title,
      toManager: toManager,
    );
  }

  void _publish(ManagerReturnDetail row) {
    store.addLocalReturnSummary(
      row.orderId,
      ReturnSummary(
        returnId: row.returnId,
        orderId: row.orderId,
        status: row.status,
        submittedAt: row.submittedAt,
        closedAt: row.closedAt,
        decisionReason: row.decisionReason,
        isActive: row.closedAt == null,
        canSubmitReturn: false,
        eligibilityReason: null,
        returnDeadline: row.deliveredAt?.add(const Duration(days: 7)),
      ),
    );
  }

  void _role(String role) {
    if (store.session.role != role) {
      throw const ReturnRequestFailure(
        ReturnRequestFailureCode.permissionDenied,
      );
    }
  }

  ManagerReturnDetail _read(String id, {bool manager = false}) {
    _role(manager ? 'manager' : 'customer');
    if (!_rows.containsKey(id) ||
        (!manager && _owners[id] != store.session.userId)) {
      throw const ReturnRequestFailure(ReturnRequestFailureCode.returnNotFound);
    }
    return _rows[id]!;
  }

  Never unavailable() => throw const ReturnRequestFailure(
    ReturnRequestFailureCode.backendUnavailable,
  );
}

class _LocalReturnRequests implements ReturnRequestRepository {
  _LocalReturnRequests(this.state);
  final LocalReturns state;
  @override
  Future<ReturnRequestContext> loadContext(String orderId) async {
    state._role('customer');
    final scope = state.store.session;
    final details = await state.store.orders.getOrderDetails(orderId);
    if (scope != state.store.session) {
      throw const ReturnRequestFailure(ReturnRequestFailureCode.sessionExpired);
    }
    final order = details.order;
    final active = state._rows.values
        .where(
          (row) =>
              row.orderId == orderId &&
              row.status != ReturnRequestStatus.initiallyRejected &&
              row.status != ReturnRequestStatus.refunded,
        )
        .firstOrNull;
    final deadline = order.deliveredAt?.add(const Duration(days: 7));
    final eligibility = order.deliveredAt == null
        ? ReturnEligibility.notDelivered
        : active != null
        ? ReturnEligibility.activeReturnExists
        : deadline!.isBefore(state.now)
        ? ReturnEligibility.returnWindowExpired
        : ReturnEligibility.eligible;
    return ReturnRequestContext(
      orderId: orderId,
      orderStatus: order.status.wireValue,
      deliveredAt: order.deliveredAt,
      items: details.items
          .map(
            (item) => ReturnContextItem(
              orderItemId: item.id,
              productName: item.productName,
              variantLabel: item.variantLabel,
              quantity: item.quantity,
              unitPriceVnd: item.unitPriceVnd,
            ),
          )
          .toList(),
      deliveryFeeVnd: order.deliveryFeeVnd,
      totalPaidVnd: order.totalCodVnd,
      serverNow: state.now,
      returnDeadline: deadline,
      canSubmitReturn: eligibility == ReturnEligibility.eligible,
      eligibility: eligibility,
      activeReturnId: active?.returnId,
    );
  }

  @override
  Future<String> uploadVideo({
    required String orderId,
    required String requestId,
    required ReturnVideoFile video,
  }) async {
    final scope = state.store.session;
    state._requestId(requestId);
    await loadContext(orderId);
    if (scope != state.store.session) {
      throw const ReturnRequestFailure(ReturnRequestFailureCode.sessionExpired);
    }
    if (video.bytes.isEmpty ||
        video.sizeBytes > ReturnVideoFile.maxBytes ||
        !ReturnVideoFile.isSupportedName(video.name)) {
      throw const ReturnRequestFailure(ReturnRequestFailureCode.videoRequired);
    }
    final path =
        '${state.store.session.userId}/$orderId/$requestId.${video.extension}';
    state._videos[path] = video;
    return path;
  }

  @override
  Future<ReturnRequestReceipt> submit(ReturnRequestCommand command) async {
    state._role('customer');
    state._requestId(command.requestId);
    final scope = state.store.session;
    final key = '${state.store.session.userId}/${command.requestId}';
    final fingerprint = jsonEncode(command.toRpcParams());
    final saved = state._receipts[key];
    if (saved != null) {
      if (state._fingerprints[key] != fingerprint) {
        throw const ReturnRequestFailure(
          ReturnRequestFailureCode.idempotencyConflict,
        );
      }
      return state._replayReceipt(saved);
    }
    final context = await loadContext(command.orderId);
    if (!context.canSubmitReturn) {
      throw const ReturnRequestFailure(ReturnRequestFailureCode.stateConflict);
    }
    if (!state._videos.containsKey(command.videoObjectPath) ||
        !command.videoObjectPath.startsWith(
          '${state.store.session.userId}/${command.orderId}/',
        )) {
      throw const ReturnRequestFailure(ReturnRequestFailureCode.videoRequired);
    }
    if ([
      command.description,
      command.bankName,
      command.accountNumber,
      command.accountHolder,
    ].any((value) => value.trim().isEmpty)) {
      throw const ReturnRequestFailure(ReturnRequestFailureCode.invalidInput);
    }
    final details = await state.store.orders.getOrderDetails(command.orderId);
    if (scope != state.store.session) {
      throw const ReturnRequestFailure(ReturnRequestFailureCode.sessionExpired);
    }
    // Two same-tick submissions may both have passed the initial read.
    if (state._receipts.containsKey(key)) {
      if (state._fingerprints[key] != fingerprint) {
        throw const ReturnRequestFailure(
          ReturnRequestFailureCode.idempotencyConflict,
        );
      }
      return state._replayReceipt(state._receipts[key]!);
    }
    if (state._rows.values.any(
      (row) => row.orderId == command.orderId && row.closedAt == null,
    )) {
      throw const ReturnRequestFailure(
        ReturnRequestFailureCode.activeReturnExists,
      );
    }
    final order = details.order;
    final id = command.requestId;
    state._owners[id] = order.customerId;
    state._rows[id] = ManagerReturnDetail(
      returnId: id,
      orderId: order.id,
      status: ReturnRequestStatus.pendingReview,
      reason: command.reason,
      description: command.description,
      submittedAt: state.now,
      deliveredAt: order.deliveredAt,
      customer: ManagerReturnContact(
        name: details.buyer?.fullName ?? order.recipientName,
      ),
      recipient: ManagerReturnContact(
        name: order.recipientName,
        phone: order.recipientPhone,
        address: order.addressDetail,
      ),
      subtotalVnd: order.subtotalVnd,
      deliveryFeeVnd: order.deliveryFeeVnd,
      totalVnd: order.totalCodVnd,
      orderItems: details.items
          .map(
            (item) => ManagerReturnOrderItem(
              orderItemId: item.id,
              productName: item.productName,
              variantLabel: item.variantLabel,
              quantity: item.quantity,
              unitPriceVnd: item.unitPriceVnd,
              lineTotalVnd: item.lineTotalVnd,
            ),
          )
          .toList(),
      returnItems: const [],
      videoPaths: [command.videoObjectPath],
      shippers: const [],
      serverNow: state.now,
      bank: ManagerReturnBank(
        bankName: command.bankName,
        accountNumber: command.accountNumber,
        accountHolder: command.accountHolder,
      ),
    );
    final receipt = ReturnRequestReceipt(
      returnRequestId: id,
      orderId: order.id,
      status: 'pending_review',
      submittedAt: state.now,
      replayed: false,
    );
    state._receipts[key] = receipt;
    state._fingerprints[key] = fingerprint;
    state._publish(state._rows[id]!);
    state.store.publishLocalReturnEvent(
      orderId: order.id,
      returnId: id,
      eventId: command.requestId,
      title: 'Có yêu cầu trả hàng mới',
      toManager: true,
    );
    return receipt;
  }
}

class _LocalReturnTracking implements ReturnTrackingRepository {
  _LocalReturnTracking(this.state);
  final LocalReturns state;
  @override
  Future<ReturnTracking> load(String returnId) async {
    final row = state._read(returnId);
    return ReturnTracking(
      returnId: returnId,
      returnCode: returnId,
      orderId: row.orderId,
      orderCode: row.orderId,
      status: row.status,
      reason: row.reason,
      submittedAt: row.submittedAt,
      refreshedAt: state.now,
      events: [
        ReturnTrackingEvent(
          kind: ReturnTrackingEventKind.submitted,
          occurredAt: row.submittedAt,
        ),
        if (row.decisionAt != null)
          ReturnTrackingEvent(
            kind: ReturnTrackingEventKind.initiallyRejected,
            occurredAt: row.decisionAt!,
            note: row.decisionReason,
          ),
        for (final info in row.infoRequests)
          ReturnTrackingEvent(
            kind: ReturnTrackingEventKind.infoRequested,
            occurredAt: info.requestedAt,
            note: info.message,
          ),
      ],
      items: const [],
      merchandiseVnd: row.subtotalVnd,
      deliveryFeeVnd: row.deliveryFeeVnd,
      pickupAddress: row.recipient.address ?? '',
      decisionReason: row.decisionReason,
      infoRequest: row.infoRequests.isEmpty
          ? null
          : ReturnInfoRequest(
              message: row.infoRequests.last.message,
              requestedAt: row.infoRequests.last.requestedAt,
              respondedAt: row.infoRequests.last.respondedAt,
            ),
      refundBankName: row.bank?.bankName,
      refundAccountMasked: row.bank == null
          ? null
          : '••••${row.bank!.accountNumber.substring(row.bank!.accountNumber.length > 4 ? row.bank!.accountNumber.length - 4 : 0)}',
    );
  }

  @override
  Future<void> submitAdditionalInfo({
    required String returnId,
    required String requestId,
    required String description,
    ReturnVideoFile? video,
  }) async {
    final row = state._read(returnId);
    final body = <Object?>[
      'additional_info',
      returnId,
      description.trim(),
      video == null ? null : base64Encode(video.bytes),
    ];
    if (state._replayed(requestId, body)) return;
    final info = row.openInfoRequest;
    if (info == null || description.trim().isEmpty) {
      throw const ReturnRequestFailure(ReturnRequestFailureCode.stateConflict);
    }
    String? responsePath;
    if (video != null) {
      if (video.bytes.isEmpty ||
          video.sizeBytes > ReturnVideoFile.maxBytes ||
          !ReturnVideoFile.isSupportedName(video.name)) {
        throw const ReturnRequestFailure(
          ReturnRequestFailureCode.videoRequired,
        );
      }
      responsePath =
          '${state.store.session.userId}/${row.orderId}/$requestId.${video.extension}';
      state._videos[responsePath] = video;
    }
    state._rows[returnId] = row.copyWith(
      infoRequests: [
        for (final entry in row.infoRequests)
          if (identical(entry, info))
            ManagerInfoRequest(
              message: entry.message,
              requestedAt: entry.requestedAt,
              responseText: description,
              responseVideoPath: responsePath,
              respondedAt: state.now,
            )
          else
            entry,
      ],
    );
    state._commit(
      requestId,
      body,
      row,
      'Khách hàng đã bổ sung thông tin',
      toManager: true,
    );
  }
}

class _LocalManagerReturns implements ManagerReturnRepository {
  _LocalManagerReturns(this.state);
  final LocalReturns state;
  @override
  Future<ManagerReturnList> list({
    ReturnRequestStatus? status,
    String? query,
  }) async {
    state._role('manager');
    final rows = state._rows.values
        .where(
          (row) =>
              query == null ||
              '${row.orderId} ${row.customer.name}'.toLowerCase().contains(
                query.toLowerCase(),
              ),
        )
        .toList();
    return ManagerReturnList(
      items: rows
          .where((row) => status == null || row.status == status)
          .map(
            (row) => ManagerReturnSummary(
              returnId: row.returnId,
              orderId: row.orderId,
              status: row.status,
              reason: row.reason,
              submittedAt: row.submittedAt,
              customerName: row.customer.name,
              totalVnd: row.totalVnd,
              lineCount: row.orderItems.length,
              firstItemName: row.orderItems.firstOrNull?.productName,
            ),
          )
          .toList(),
      counts: {
        for (final value in ReturnRequestStatus.values)
          value: rows.where((row) => row.status == value).length,
      },
      serverNow: state.now,
    );
  }

  @override
  Future<ManagerReturnDetail> load(String returnId) async =>
      state._read(returnId, manager: true);
  @override
  Future<void> reject({
    required String returnId,
    required String requestId,
    required String reason,
  }) async {
    final row = state._read(returnId, manager: true);
    final body = <Object?>['reject', returnId, reason.trim()];
    if (state._replayed(requestId, body)) return;
    if (row.status != ReturnRequestStatus.pendingReview ||
        reason.trim().isEmpty) {
      throw const ReturnRequestFailure(ReturnRequestFailureCode.stateConflict);
    }
    state._rows[returnId] = row.copyWith(
      status: ReturnRequestStatus.initiallyRejected,
      decisionReason: reason,
      decisionAt: state.now,
      closedAt: state.now,
    );
    state._publish(state._rows[returnId]!);
    state._commit(requestId, body, row, 'Yêu cầu trả hàng đã bị từ chối');
  }

  @override
  Future<void> requestInfo({
    required String returnId,
    required String requestId,
    required String message,
  }) async {
    final row = state._read(returnId, manager: true);
    final body = <Object?>['request_info', returnId, message.trim()];
    if (state._replayed(requestId, body)) return;
    if (row.status != ReturnRequestStatus.pendingReview ||
        row.openInfoRequest != null ||
        message.trim().isEmpty) {
      throw const ReturnRequestFailure(ReturnRequestFailureCode.stateConflict);
    }
    state._rows[returnId] = row.copyWith(
      infoRequests: [
        ...row.infoRequests,
        ManagerInfoRequest(message: message, requestedAt: state.now),
      ],
    );
    state._commit(requestId, body, row, 'Vui lòng bổ sung thông tin trả hàng');
  }

  @override
  Future<Uri> videoUrl(String objectPath) async => state.unavailable();
  @override
  Future<Uri> evidenceUrl(ManagerEvidenceKind kind, String objectPath) async =>
      state.unavailable();
  @override
  Future<String> uploadEvidence({
    required String returnId,
    required ManagerEvidenceKind kind,
    required String objectName,
    required ManagerEvidenceFile file,
  }) async => state.unavailable();
  @override
  Future<void> approveCollection({
    required String returnId,
    required String requestId,
    required List<ManagerCollectionLine> lines,
    required String shipperId,
  }) async => state.unavailable();
  @override
  Future<void> receive({
    required String returnId,
    required String taskId,
    required String requestId,
    required List<ManagerReturnItem> items,
  }) async => state.unavailable();
  @override
  Future<void> acceptInspection({
    required String returnId,
    required String requestId,
    required List<ManagerInspectionLine> lines,
    required List<String> evidencePaths,
  }) async => state.unavailable();
  @override
  Future<void> rejectInspection({
    required String returnId,
    required String requestId,
    required String reason,
    required List<String> evidencePaths,
  }) async => state.unavailable();
  @override
  Future<void> recordRefund({
    required String returnId,
    required String requestId,
    required int amountVnd,
    required DateTime transferredAt,
    required String evidencePath,
  }) async => state.unavailable();
  @override
  Future<void> assignRedelivery({
    required String returnId,
    required String requestId,
    required String shipperId,
  }) async => state.unavailable();
}
