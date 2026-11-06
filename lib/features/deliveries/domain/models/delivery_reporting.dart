import 'delivery_task.dart';

/// The server's `integer` quantity bound for a handover item.
const int maxReportingItemQuantity = 2147483647;

/// The two outbound reporting commands exposed to the shipper UI.
///
/// These values are deliberately not the names of the public RPCs.  The
/// repository owns the mapping from a domain command to its RPC and its
/// approved parameter set.
enum ReportingOperation {
  handover('handover', 'report_store_handover'),
  incident('incident', 'report_delivery_incident');

  const ReportingOperation(this.value, this.rpcName);

  final String value;
  final String rpcName;
}

/// Incident kinds accepted by the deployed P07.4 reporting RPC.
enum ReportingIncidentKind {
  damaged('damaged'),
  lost('lost'),
  other('other');

  const ReportingIncidentKind(this.value);

  final String value;

  static ReportingIncidentKind fromValue(String value) {
    for (final kind in values) {
      if (kind.value == value) return kind;
    }
    throw FormatException('Unknown reporting incident kind: $value');
  }
}

/// One immutable order-item row returned by the reporting context read.
///
/// Product names are display-only.  A handover write sends only
/// [orderItemId] and [quantity]; it never sends the product text or any
/// catalog/price data back to the server.
class ReportItem {
  const ReportItem({
    required this.orderItemId,
    required this.productName,
    this.variantLabel,
    required this.quantity,
  });

  final String orderItemId;
  final String productName;
  final String? variantLabel;
  final int quantity;

  /// Alias useful to callers that use the generic item terminology from the
  /// delivery task models.
  String get itemId => orderItemId;

  @override
  bool operator ==(Object other) {
    return other is ReportItem &&
        orderItemId == other.orderItemId &&
        productName == other.productName &&
        variantLabel == other.variantLabel &&
        quantity == other.quantity;
  }

  @override
  int get hashCode =>
      Object.hash(orderItemId, productName, variantLabel, quantity);

  @override
  String toString() =>
      'ReportItem(orderItemId: $orderItemId, productName: $productName, '
      'variantLabel: $variantLabel, quantity: $quantity)';
}

/// The minimal, role-scoped context used by MH11's reporting actions.
///
/// The read projection intentionally has no order UUID, recipient details,
/// prices, or other order/customer data.  [kind] is fixed to outbound by the
/// reporting read contract because the JSON projection does not expose a
/// task-kind field; unsupported task kinds are rejected by the write RPC.
class ReportingContext {
  const ReportingContext({
    required this.taskId,
    this.kind = DeliveryTaskKind.outbound,
    required this.status,
    required this.orderStatus,
    required this.canHandover,
    required this.canIncident,
    required this.handoverReported,
    this.handoverBlockReason,
    this.incidentBlockReason,
    required this.items,
  });

  final String taskId;
  final DeliveryTaskKind kind;
  final DeliveryTaskStatus status;
  final String? orderStatus;
  final bool canHandover;
  final bool canIncident;
  final bool handoverReported;
  final String? handoverBlockReason;
  final String? incidentBlockReason;
  final List<ReportItem> items;

  /// Explicit aliases keep the model easy to use beside task snapshots.
  DeliveryTaskKind get taskKind => kind;
  DeliveryTaskStatus get taskStatus => status;

  @override
  bool operator ==(Object other) {
    return other is ReportingContext &&
        taskId == other.taskId &&
        kind == other.kind &&
        status == other.status &&
        orderStatus == other.orderStatus &&
        canHandover == other.canHandover &&
        canIncident == other.canIncident &&
        handoverReported == other.handoverReported &&
        handoverBlockReason == other.handoverBlockReason &&
        incidentBlockReason == other.incidentBlockReason &&
        _listEquals(items, other.items);
  }

  @override
  int get hashCode => Object.hash(
    taskId,
    kind,
    status,
    orderStatus,
    canHandover,
    canIncident,
    handoverReported,
    handoverBlockReason,
    incidentBlockReason,
    Object.hashAll(items),
  );

  @override
  String toString() =>
      'ReportingContext(taskId: $taskId, kind: ${kind.value}, '
      'status: ${status.value}, orderStatus: $orderStatus, '
      'canHandover: $canHandover, canIncident: $canIncident, '
      'handoverReported: $handoverReported, items: ${items.length})';

  static bool _listEquals(List<ReportItem> left, List<ReportItem> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

/// Idempotent input for either P07.4 report operation.
///
/// For handover, [items] must come from the authoritative reporting context;
/// the repository sends only their immutable order-item IDs and quantities.
/// For incident, [incidentKind] and [reason] are the only payload fields.
class ReportingCommand {
  const ReportingCommand({
    required this.taskId,
    required this.requestId,
    required this.operation,
    this.items = const <ReportItem>[],
    this.incidentKind,
    this.reason,
  });

  const ReportingCommand.handover({
    required this.taskId,
    required this.requestId,
    required this.items,
  }) : operation = ReportingOperation.handover,
       incidentKind = null,
       reason = null;

  const ReportingCommand.incident({
    required this.taskId,
    required this.requestId,
    required this.incidentKind,
    required this.reason,
  }) : operation = ReportingOperation.incident,
       items = const <ReportItem>[];

  final String taskId;
  final String requestId;
  final ReportingOperation operation;
  final List<ReportItem> items;
  final ReportingIncidentKind? incidentKind;
  final String? reason;

  bool get isHandover => operation == ReportingOperation.handover;
  bool get isIncident => operation == ReportingOperation.incident;

  /// Alias for code that calls the incident enum simply `kind`.
  ReportingIncidentKind? get kind => incidentKind;

  @override
  bool operator ==(Object other) {
    return other is ReportingCommand &&
        taskId == other.taskId &&
        requestId == other.requestId &&
        operation == other.operation &&
        _itemsEqual(items, other.items) &&
        incidentKind == other.incidentKind &&
        reason == other.reason;
  }

  @override
  int get hashCode => Object.hash(
    taskId,
    requestId,
    operation,
    Object.hashAll(items),
    incidentKind,
    reason,
  );

  @override
  String toString() =>
      'ReportingCommand(operation: ${operation.value}, taskId: $taskId, '
      'requestId: $requestId)';

  static bool _itemsEqual(List<ReportItem> left, List<ReportItem> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

/// Strict acknowledgement returned by a committed report transaction.
///
/// [operation] retains the exact server operation string because it is part of
/// the receipt contract (`report_store_handover` or
/// `report_delivery_incident`).
class ReportingAck {
  const ReportingAck({
    required this.taskId,
    required this.orderId,
    required this.operation,
    required this.requestId,
    required this.eventId,
    required this.reportedAt,
    required this.taskStatus,
    required this.orderStatus,
  });

  final String taskId;
  final String orderId;
  final String operation;
  final String requestId;
  final String eventId;
  final DateTime reportedAt;
  final String taskStatus;
  final String orderStatus;

  ReportingOperation get operationKind => switch (operation) {
    'report_store_handover' => ReportingOperation.handover,
    'report_delivery_incident' => ReportingOperation.incident,
    _ => throw StateError('Unknown reporting ACK operation'),
  };

  @override
  bool operator ==(Object other) {
    return other is ReportingAck &&
        taskId == other.taskId &&
        orderId == other.orderId &&
        operation == other.operation &&
        requestId == other.requestId &&
        eventId == other.eventId &&
        reportedAt == other.reportedAt &&
        taskStatus == other.taskStatus &&
        orderStatus == other.orderStatus;
  }

  @override
  int get hashCode => Object.hash(
    taskId,
    orderId,
    operation,
    requestId,
    eventId,
    reportedAt,
    taskStatus,
    orderStatus,
  );

  @override
  String toString() =>
      'ReportingAck(operation: $operation, taskId: $taskId, '
      'requestId: $requestId, taskStatus: $taskStatus, '
      'orderStatus: $orderStatus)';
}

// Naming aliases for callers that prefer the feature-qualified vocabulary.
typedef DeliveryReportingContext = ReportingContext;
typedef DeliveryReportingItem = ReportItem;
typedef DeliveryReportingCommand = ReportingCommand;
typedef DeliveryReportingAck = ReportingAck;
typedef DeliveryReportingOperation = ReportingOperation;
typedef DeliveryReportingIncidentKind = ReportingIncidentKind;
