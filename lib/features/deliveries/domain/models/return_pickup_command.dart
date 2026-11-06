import 'outbound_failure_command.dart';

/// Return-pickup writes owned by the current shipper.
///
/// Handover is deliberately a separate operation from collection. It reports
/// that custody was handed from the shipper to the store; it does not mutate
/// the delivery task, return request, order, stock, COD or store receipt.
enum ReturnPickupOperation {
  collect('collect_return_items'),
  fail('fail_return_pickup_task'),
  handover('report_return_pickup_handover');

  const ReturnPickupOperation(this.value);

  final String value;

  // Readable aliases for callers that use the RPC-oriented action names.
  static const collectItems = ReturnPickupOperation.collect;
  static const failTask = ReturnPickupOperation.fail;
  static const collectReturnItems = ReturnPickupOperation.collect;
  static const failReturnPickupTask = ReturnPickupOperation.fail;
  static const reportReturnPickupHandover = ReturnPickupOperation.handover;

  static ReturnPickupOperation fromValue(String value) {
    for (final operation in values) {
      if (operation.value == value) return operation;
    }
    throw FormatException('Unknown return-pickup operation: $value');
  }

  String get rpcName => value;
}

/// One item in the immutable approved return plan sent to
/// `collect_return_items`.
///
/// Product names, prices and order-item IDs are intentionally absent.  The
/// server resolves the approved plan from the task snapshot and compares this
/// exact `(return_item_id, quantity)` list before changing custody.
class ReturnPickupItem {
  const ReturnPickupItem({required this.returnItemId, required this.quantity});

  final String returnItemId;
  final int quantity;

  /// Alias used by code that treats all delivery item references uniformly.
  String get itemId => returnItemId;

  int get quantityToCollect => quantity;

  bool get hasUuidShape => _uuid.hasMatch(returnItemId);

  bool get hasValidQuantity => quantity >= 1 && quantity <= _maxInt32;

  bool get isValid => hasUuidShape && hasValidQuantity;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'return_item_id': returnItemId,
    'quantity': quantity,
  };

  @override
  bool operator ==(Object other) =>
      other is ReturnPickupItem &&
      returnItemId == other.returnItemId &&
      quantity == other.quantity;

  @override
  int get hashCode => Object.hash(returnItemId, quantity);

  @override
  String toString() =>
      'ReturnPickupItem(returnItemId: $returnItemId, quantity: $quantity)';
}

/// Immutable, idempotent input for one P08.1 shipper write.
///
/// [returnRequestId] and [orderId] are local ACK guards.  They are not sent
/// as RPC parameters because the server derives both from the assigned task.
/// Keeping them in the command lets a caller reject a receipt for a task that
/// was displayed against a different request/order without widening the write
/// API.
class ReturnPickupCommand {
  ReturnPickupCommand({
    required this.taskId,
    required this.requestId,
    required this.returnRequestId,
    required this.orderId,
    required this.operation,
    Iterable<ReturnPickupItem> items = const <ReturnPickupItem>[],
    this.reason,
    this.description,
  }) : items = List<ReturnPickupItem>.unmodifiable(items);

  ReturnPickupCommand.collect({
    required String taskId,
    required String requestId,
    required String returnRequestId,
    required String orderId,
    required Iterable<ReturnPickupItem> items,
  }) : this(
         taskId: taskId,
         requestId: requestId,
         returnRequestId: returnRequestId,
         orderId: orderId,
         operation: ReturnPickupOperation.collect,
         items: items,
       );

  ReturnPickupCommand.fail({
    required String taskId,
    required String requestId,
    required String returnRequestId,
    required String orderId,
    required OutboundFailureReason reason,
    String? description,
  }) : this(
         taskId: taskId,
         requestId: requestId,
         returnRequestId: returnRequestId,
         orderId: orderId,
         operation: ReturnPickupOperation.fail,
         reason: reason,
         description: description,
       );

  ReturnPickupCommand.handover({
    required String taskId,
    required String requestId,
    required String returnRequestId,
    required String orderId,
    required Iterable<ReturnPickupItem> items,
  }) : this(
         taskId: taskId,
         requestId: requestId,
         returnRequestId: returnRequestId,
         orderId: orderId,
         operation: ReturnPickupOperation.handover,
         items: items,
       );

  final String taskId;
  final String requestId;
  final String returnRequestId;
  final String orderId;
  final ReturnPickupOperation operation;
  final List<ReturnPickupItem> items;
  final OutboundFailureReason? reason;
  final String? description;

  /// Common aliases make the local guard explicit at call sites.
  String get returnId => returnRequestId;

  String get stableRequestId => requestId;

  String get requestKey => requestId;

  ReturnPickupOperation get action => operation;

  List<ReturnPickupItem> get collectionItems => items;

  bool get isCollect => operation == ReturnPickupOperation.collect;

  bool get isHandover => operation == ReturnPickupOperation.handover;

  bool get isStoreHandover => isHandover;

  bool get isFail => operation == ReturnPickupOperation.fail;

  bool get isFailure => isFail;

  OutboundFailureReason? get failureReason => reason;

  bool get hasUuidShape =>
      _uuid.hasMatch(taskId) &&
      _uuid.hasMatch(requestId) &&
      _uuid.hasMatch(returnRequestId) &&
      _uuid.hasMatch(orderId);

  bool get hasNonBlankIds =>
      taskId.trim().isNotEmpty &&
      requestId.trim().isNotEmpty &&
      returnRequestId.trim().isNotEmpty &&
      orderId.trim().isNotEmpty;

  bool get hasCanonicalItems {
    if (items.isEmpty) return false;
    String? previous;
    final seen = <String>{};
    for (final item in items) {
      if (!item.isValid) return false;
      final id = item.returnItemId.toLowerCase();
      if (!seen.add(id)) return false;
      if (previous != null && id.compareTo(previous) < 0) return false;
      previous = id;
    }
    return true;
  }

  bool get hasValidDescription {
    if (reason != OutboundFailureReason.other) return true;
    final text = description?.trim();
    return text != null && text.isNotEmpty;
  }

  String? get trimmedDescription {
    final text = description?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  /// Local validation is intentionally stricter than merely checking IDs;
  /// invalid commands never cause a profile read or an RPC dispatch.
  bool get isValid {
    if (!hasUuidShape || !hasNonBlankIds) return false;
    switch (operation) {
      case ReturnPickupOperation.collect:
      case ReturnPickupOperation.handover:
        return reason == null && description == null && hasCanonicalItems;
      case ReturnPickupOperation.fail:
        return items.isEmpty && reason != null && hasValidDescription;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ReturnPickupCommand &&
      taskId == other.taskId &&
      requestId == other.requestId &&
      returnRequestId == other.returnRequestId &&
      orderId == other.orderId &&
      operation == other.operation &&
      _itemsEqual(items, other.items) &&
      reason == other.reason &&
      description == other.description;

  @override
  int get hashCode => Object.hash(
    taskId,
    requestId,
    returnRequestId,
    orderId,
    operation,
    Object.hashAll(items),
    reason,
    description,
  );

  @override
  String toString() =>
      'ReturnPickupCommand(operation: ${operation.value}, taskId: $taskId, '
      'requestId: $requestId, items: ${items.length}, '
      'hasReason: ${reason != null})';

  static bool _itemsEqual(
    List<ReturnPickupItem> left,
    List<ReturnPickupItem> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

/// Validated receipt returned by one committed pickup transaction.
class ReturnPickupAck {
  const ReturnPickupAck({
    required this.taskId,
    required this.returnRequestId,
    required this.orderId,
    required this.operation,
    required this.taskStatus,
    required this.returnStatus,
    required this.eventId,
    required this.requestId,
    required this.occurredAt,
    this.acceptedAt,
    this.startedAt,
    this.reportedAt,
    this.failedAt,
    this.reason,
    this.description,
  });

  final String taskId;
  final String returnRequestId;
  final String orderId;
  final ReturnPickupOperation operation;
  final String taskStatus;
  final String returnStatus;
  final String eventId;
  final String requestId;
  final DateTime occurredAt;
  final DateTime? acceptedAt;
  final DateTime? startedAt;
  final DateTime? reportedAt;
  final DateTime? failedAt;
  final OutboundFailureReason? reason;
  final String? description;

  bool get isCollection => operation == ReturnPickupOperation.collect;

  bool get isHandover => operation == ReturnPickupOperation.handover;

  bool get isFailure => operation == ReturnPickupOperation.fail;

  OutboundFailureReason? get failureReason => reason;

  String? get reasonCode => reason?.value;

  String? get reasonDescription => description;

  /// The server uses one transaction timestamp for all pickup milestones.
  DateTime? get committedAt => switch (operation) {
    ReturnPickupOperation.collect => occurredAt,
    ReturnPickupOperation.handover => reportedAt,
    ReturnPickupOperation.fail => failedAt,
  };

  bool matches(ReturnPickupCommand command) {
    if (taskId.toLowerCase() != command.taskId.toLowerCase() ||
        returnRequestId.toLowerCase() !=
            command.returnRequestId.toLowerCase() ||
        orderId.toLowerCase() != command.orderId.toLowerCase() ||
        requestId.toLowerCase() != command.requestId.toLowerCase() ||
        operation != command.operation) {
      return false;
    }
    if (command.isCollect) {
      return taskStatus == 'in_transit' &&
          returnStatus == 'returning_to_store' &&
          acceptedAt != null &&
          startedAt != null &&
          reportedAt == null &&
          failedAt == null &&
          reason == null &&
          description == null;
    }
    if (command.isHandover) {
      return taskStatus == 'in_transit' &&
          returnStatus == 'returning_to_store' &&
          acceptedAt == null &&
          startedAt == null &&
          reportedAt != null &&
          reportedAt == occurredAt &&
          failedAt == null &&
          reason == null &&
          description == null;
    }
    return taskStatus == 'failed' &&
        returnStatus == 'awaiting_return_pickup' &&
        acceptedAt == null &&
        startedAt == null &&
        reportedAt == null &&
        failedAt != null &&
        reason == command.reason &&
        description == command.trimmedDescription;
  }

  @override
  bool operator ==(Object other) =>
      other is ReturnPickupAck &&
      taskId == other.taskId &&
      returnRequestId == other.returnRequestId &&
      orderId == other.orderId &&
      operation == other.operation &&
      taskStatus == other.taskStatus &&
      returnStatus == other.returnStatus &&
      eventId == other.eventId &&
      requestId == other.requestId &&
      occurredAt == other.occurredAt &&
      acceptedAt == other.acceptedAt &&
      startedAt == other.startedAt &&
      reportedAt == other.reportedAt &&
      failedAt == other.failedAt &&
      reason == other.reason &&
      description == other.description;

  @override
  int get hashCode => Object.hash(
    taskId,
    returnRequestId,
    orderId,
    operation,
    taskStatus,
    returnStatus,
    eventId,
    requestId,
    occurredAt,
    acceptedAt,
    startedAt,
    reportedAt,
    failedAt,
    reason,
    description,
  );
}

const int _maxInt32 = 2147483647;
final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Compatibility aliases for feature-level wiring that uses longer names.
typedef ReturnPickupCollectionItem = ReturnPickupItem;
typedef ReturnPickupCommandItem = ReturnPickupItem;
typedef ReturnPickupCollectItem = ReturnPickupItem;
typedef ReturnPickupFailureReason = OutboundFailureReason;
typedef ReturnPickupAckResult = ReturnPickupAck;
typedef ReturnPickupCommandOperation = ReturnPickupOperation;

/// The narrow marker projection used to prevent a duplicate handover button
/// after MH11 is reopened. `reported_at` is nullable only while `reported` is
/// false; the server remains authoritative for both fields.
class ReturnPickupHandoverStatus {
  const ReturnPickupHandoverStatus({
    required this.taskId,
    required this.reported,
    this.reportedAt,
  });

  final String taskId;
  final bool reported;
  final DateTime? reportedAt;

  bool get isReported => reported;

  bool get isValid =>
      _uuid.hasMatch(taskId) && (!reported || reportedAt?.isUtc == true);

  bool matchesTask(String expectedTaskId) =>
      taskId.toLowerCase() == expectedTaskId.toLowerCase();

  @override
  bool operator ==(Object other) =>
      other is ReturnPickupHandoverStatus &&
      taskId == other.taskId &&
      reported == other.reported &&
      reportedAt == other.reportedAt;

  @override
  int get hashCode => Object.hash(taskId, reported, reportedAt);

  @override
  String toString() =>
      'ReturnPickupHandoverStatus(taskId: $taskId, reported: $reported, '
      'reportedAt: $reportedAt)';
}

typedef ReturnPickupHandoverMarker = ReturnPickupHandoverStatus;
