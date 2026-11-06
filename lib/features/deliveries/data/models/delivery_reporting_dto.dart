import '../../domain/models/delivery_reporting.dart';
import '../../domain/models/delivery_task.dart';
import 'dto_readers.dart';

/// DTO for one item in `get_my_delivery_reporting_context`.
final class ReportItemDto {
  const ReportItemDto({
    required this.orderItemId,
    required this.productName,
    this.variantLabel,
    required this.quantity,
  });

  static const responseKeys = <String>{
    'order_item_id',
    'product_name',
    'variant_label',
    'quantity',
  };

  factory ReportItemDto.fromJson(Map<String, dynamic> json) {
    _checkKeys(json, responseKeys, 'report item');
    if (!json.containsKey('variant_label')) {
      throw DeliveryDtoReaders.invalid(
        'variant_label',
        'null or a non-blank string',
      );
    }
    return ReportItemDto(
      orderItemId: DeliveryDtoReaders.readRequiredUuid(json, 'order_item_id'),
      productName: DeliveryDtoReaders.readRequiredString(json, 'product_name'),
      variantLabel: DeliveryDtoReaders.readNullableString(
        json,
        'variant_label',
      ),
      quantity: DeliveryDtoReaders.readRequiredInteger(json, 'quantity'),
    );
  }

  final String orderItemId;
  final String productName;
  final String? variantLabel;
  final int quantity;

  ReportItem toDomain() {
    DeliveryDtoReaders.checkUuid(orderItemId, 'order_item_id');
    if (productName.trim().isEmpty) {
      throw DeliveryDtoReaders.invalid('product_name', 'a non-blank string');
    }
    if (variantLabel != null && variantLabel!.trim().isEmpty) {
      throw DeliveryDtoReaders.invalid(
        'variant_label',
        'null or a non-blank string',
      );
    }
    if (quantity < 1 || quantity > maxReportingItemQuantity) {
      throw DeliveryDtoReaders.invalid('quantity', 'a positive 32-bit integer');
    }
    return ReportItem(
      orderItemId: orderItemId,
      productName: productName,
      variantLabel: variantLabel,
      quantity: quantity,
    );
  }

  static void _checkKeys(
    Map<String, dynamic> json,
    Set<String> allowed,
    String key,
  ) {
    if (json.keys.any((entry) => !allowed.contains(entry))) {
      throw DeliveryDtoReaders.invalid(
        key,
        'only the approved reporting projection fields',
      );
    }
  }
}

/// Strict DTO for the exact public reporting-context projection.
///
/// This RPC intentionally omits order identity, recipient/PII, prices and
/// catalog attributes.  A missing or extra field is rejected instead of
/// silently widening that privacy boundary.
final class ReportingContextDto {
  ReportingContextDto({
    required this.taskId,
    required this.taskStatus,
    required this.orderStatus,
    required this.canHandover,
    required this.canIncident,
    required this.handoverReported,
    this.handoverBlockReason,
    this.incidentBlockReason,
    required List<ReportItemDto> items,
  }) : items = List.unmodifiable(items);

  static const responseKeys = <String>{
    'task_id',
    'task_status',
    'order_status',
    'can_handover',
    'can_incident',
    'handover_reported',
    'handover_block_reason',
    'incident_block_reason',
    'items',
  };

  /// Decode the exact response.  [requestedTaskId] is optional for direct
  /// DTO use, but the production repository always supplies it so a response
  /// for another assigned task cannot be accepted.
  factory ReportingContextDto.fromJson(
    Map<String, dynamic> json, {
    String? requestedTaskId,
    String? taskId,
  }) {
    final expectedTaskId = requestedTaskId ?? taskId;
    if (expectedTaskId != null) {
      DeliveryDtoReaders.checkUuid(expectedTaskId, 'task_id');
    }
    _checkKeys(json, responseKeys, 'reporting context');

    final actualTaskId = DeliveryDtoReaders.readRequiredUuid(json, 'task_id');
    if (expectedTaskId != null && !_sameUuid(actualTaskId, expectedTaskId)) {
      throw DeliveryDtoReaders.invalid('task_id', 'the requested task UUID');
    }

    final taskStatus = DeliveryDtoReaders.readRequiredString(
      json,
      'task_status',
      nonBlank: false,
    );
    // This maps only known server states.  Unknown future states must not be
    // presented as a guessed/known state by the client.
    DeliveryTaskStatus.fromValue(taskStatus);

    if (!json.containsKey('order_status')) {
      throw DeliveryDtoReaders.invalid(
        'order_status',
        'null or a known order status',
      );
    }
    final orderStatus = DeliveryDtoReaders.readNullableString(
      json,
      'order_status',
    );
    if (orderStatus != null && !_knownOrderStatuses.contains(orderStatus)) {
      throw DeliveryDtoReaders.invalid(
        'order_status',
        'null or a known order status',
      );
    }

    final canHandover = _readRequiredBool(json, 'can_handover');
    final canIncident = _readRequiredBool(json, 'can_incident');
    final handoverReported = _readRequiredBool(json, 'handover_reported');

    if (!json.containsKey('handover_block_reason')) {
      throw DeliveryDtoReaders.invalid(
        'handover_block_reason',
        'null or a non-blank string',
      );
    }
    if (!json.containsKey('incident_block_reason')) {
      throw DeliveryDtoReaders.invalid(
        'incident_block_reason',
        'null or a non-blank string',
      );
    }
    final handoverBlockReason = DeliveryDtoReaders.readNullableString(
      json,
      'handover_block_reason',
    );
    final incidentBlockReason = DeliveryDtoReaders.readNullableString(
      json,
      'incident_block_reason',
    );
    if (handoverBlockReason != null &&
        !_knownBlockReasons.contains(handoverBlockReason)) {
      throw DeliveryDtoReaders.invalid(
        'handover_block_reason',
        'null or a known reporting block reason',
      );
    }
    if (incidentBlockReason != null &&
        !_knownBlockReasons.contains(incidentBlockReason)) {
      throw DeliveryDtoReaders.invalid(
        'incident_block_reason',
        'null or a known reporting block reason',
      );
    }

    final rawItems = json['items'];
    if (rawItems is! List) {
      throw DeliveryDtoReaders.invalid('items', 'an array of objects');
    }
    final items = <ReportItemDto>[];
    final itemIds = <String>{};
    for (final rawItem in rawItems) {
      if (rawItem is! Map) {
        throw DeliveryDtoReaders.invalid('items', 'an array of objects');
      }
      final itemJson = _asStringMap(rawItem, 'items');
      final item = ReportItemDto.fromJson(itemJson);
      if (!itemIds.add(item.orderItemId.toLowerCase())) {
        throw DeliveryDtoReaders.invalid('items', 'unique order item UUIDs');
      }
      items.add(item);
    }

    return ReportingContextDto(
      taskId: actualTaskId,
      taskStatus: taskStatus,
      orderStatus: orderStatus,
      canHandover: canHandover,
      canIncident: canIncident,
      handoverReported: handoverReported,
      handoverBlockReason: handoverBlockReason,
      incidentBlockReason: incidentBlockReason,
      items: items,
    );
  }

  final String taskId;
  final String taskStatus;
  final String? orderStatus;
  final bool canHandover;
  final bool canIncident;
  final bool handoverReported;
  final String? handoverBlockReason;
  final String? incidentBlockReason;
  final List<ReportItemDto> items;

  ReportingContext toDomain() {
    final status = DeliveryTaskStatus.fromValue(taskStatus);
    final domainItems = List<ReportItem>.unmodifiable(
      items.map((item) => item.toDomain()),
    );
    return ReportingContext(
      taskId: taskId,
      // The read RPC is deliberately outbound-scoped and has no task-kind
      // field.  Keep the fixed domain kind explicit rather than inventing a
      // kind from a UI/request parameter.
      kind: DeliveryTaskKind.outbound,
      status: status,
      orderStatus: orderStatus,
      canHandover: canHandover,
      canIncident: canIncident,
      handoverReported: handoverReported,
      handoverBlockReason: handoverBlockReason,
      incidentBlockReason: incidentBlockReason,
      items: domainItems,
    );
  }

  static const _knownOrderStatuses = <String>{
    'pending_confirmation',
    'preparing',
    'awaiting_pickup',
    'delivering',
    'awaiting_redelivery',
    'awaiting_store_return',
    'delivered',
    'cancelled',
    'rejected',
    'undeliverable_returned',
  };

  static const _knownBlockReasons = <String>{
    'STATE_CONFLICT',
    'CUSTODY_UNRESOLVED',
    'ITEMS_MISMATCH',
  };

  static bool _readRequiredBool(Map<String, dynamic> json, String key) {
    if (!json.containsKey(key) || json[key] is! bool) {
      throw DeliveryDtoReaders.invalid(key, 'a boolean');
    }
    return json[key] as bool;
  }

  static Map<String, dynamic> _asStringMap(Object raw, String key) {
    try {
      return Map<String, dynamic>.from(raw as Map);
    } on TypeError {
      throw DeliveryDtoReaders.invalid(key, 'an object with string keys');
    }
  }

  static void _checkKeys(
    Map<String, dynamic> json,
    Set<String> allowed,
    String key,
  ) {
    if (json.keys.any((entry) => !allowed.contains(entry))) {
      throw DeliveryDtoReaders.invalid(
        key,
        'only the approved reporting projection fields',
      );
    }
  }

  static bool _sameUuid(String left, String right) =>
      left.toLowerCase() == right.toLowerCase();
}

/// Strict command receipt returned by either P07.4 report RPC.
final class ReportingAckDto {
  const ReportingAckDto({
    required this.taskId,
    required this.orderId,
    required this.operation,
    required this.requestId,
    required this.eventId,
    required this.reportedAt,
    required this.taskStatus,
    required this.orderStatus,
  });

  static const responseKeys = <String>{
    'task_id',
    'order_id',
    'operation',
    'request_id',
    'event_id',
    'reported_at',
    'task_status',
    'order_status',
  };

  factory ReportingAckDto.fromJson(
    Map<String, dynamic> json, {
    required ReportingCommand command,
  }) {
    _checkKeys(json, responseKeys, 'reporting acknowledgement');
    final taskId = DeliveryDtoReaders.readRequiredUuid(json, 'task_id');
    final requestId = DeliveryDtoReaders.readRequiredUuid(json, 'request_id');
    if (!_sameUuid(taskId, command.taskId)) {
      throw DeliveryDtoReaders.invalid(
        'task_id',
        'the task UUID from the command',
      );
    }
    if (!_sameUuid(requestId, command.requestId)) {
      throw DeliveryDtoReaders.invalid(
        'request_id',
        'the request UUID from the command',
      );
    }

    final operation = DeliveryDtoReaders.readRequiredString(
      json,
      'operation',
      nonBlank: false,
    );
    if (operation != command.operation.rpcName) {
      throw DeliveryDtoReaders.invalid('operation', command.operation.rpcName);
    }

    final taskStatus = DeliveryDtoReaders.readRequiredString(
      json,
      'task_status',
      nonBlank: false,
    );
    final orderStatus = DeliveryDtoReaders.readRequiredString(
      json,
      'order_status',
      nonBlank: false,
    );
    _validateAckState(command.operation, taskStatus, orderStatus);

    final reportedAt = DeliveryDtoReaders.readNullableTimestamp(
      json,
      'reported_at',
    );
    if (reportedAt == null || !reportedAt.isUtc) {
      throw DeliveryDtoReaders.invalid(
        'reported_at',
        'a required UTC RFC3339 timestamp',
      );
    }

    return ReportingAckDto(
      taskId: taskId,
      orderId: DeliveryDtoReaders.readRequiredUuid(json, 'order_id'),
      operation: operation,
      requestId: requestId,
      eventId: DeliveryDtoReaders.readRequiredUuid(json, 'event_id'),
      reportedAt: reportedAt,
      taskStatus: taskStatus,
      orderStatus: orderStatus,
    );
  }

  final String taskId;
  final String orderId;
  final String operation;
  final String requestId;
  final String eventId;
  final DateTime reportedAt;
  final String taskStatus;
  final String orderStatus;

  ReportingAck toDomain() => ReportingAck(
    taskId: taskId,
    orderId: orderId,
    operation: operation,
    requestId: requestId,
    eventId: eventId,
    reportedAt: reportedAt,
    taskStatus: taskStatus,
    orderStatus: orderStatus,
  );

  static void _validateAckState(
    ReportingOperation operation,
    String taskStatus,
    String orderStatus,
  ) {
    try {
      DeliveryTaskStatus.fromValue(taskStatus);
    } on FormatException {
      throw DeliveryDtoReaders.invalid('task_status', 'a known task status');
    }
    if (!_knownOrderStatuses.contains(orderStatus)) {
      throw DeliveryDtoReaders.invalid('order_status', 'a known order status');
    }

    final allowed = switch (operation) {
      ReportingOperation.handover =>
        taskStatus == 'failed' || taskStatus == 'cancelled'
            ? orderStatus == 'awaiting_store_return'
            : false,
      ReportingOperation.incident =>
        (taskStatus == 'accepted' ||
                taskStatus == 'in_transit' ||
                taskStatus == 'failed' ||
                taskStatus == 'cancelled') &&
            (orderStatus == 'awaiting_pickup' ||
                orderStatus == 'delivering' ||
                orderStatus == 'awaiting_redelivery' ||
                orderStatus == 'awaiting_store_return'),
    };
    if (!allowed) {
      throw DeliveryDtoReaders.invalid(
        'status',
        'a state allowed for the reporting operation',
      );
    }
  }

  static const _knownOrderStatuses = <String>{
    'pending_confirmation',
    'preparing',
    'awaiting_pickup',
    'delivering',
    'awaiting_redelivery',
    'awaiting_store_return',
    'delivered',
    'cancelled',
    'rejected',
    'undeliverable_returned',
  };

  static void _checkKeys(
    Map<String, dynamic> json,
    Set<String> allowed,
    String key,
  ) {
    if (json.keys.any((entry) => !allowed.contains(entry))) {
      throw DeliveryDtoReaders.invalid(
        key,
        'only the approved command receipt fields',
      );
    }
  }

  static bool _sameUuid(String left, String right) =>
      left.toLowerCase() == right.toLowerCase();
}

// Feature-qualified aliases keep this DTO convenient for consumers that use
// the filename vocabulary while preserving the short domain contract names.
typedef DeliveryReportingContextDto = ReportingContextDto;
typedef DeliveryReportingItemDto = ReportItemDto;
typedef DeliveryReportingAckDto = ReportingAckDto;
