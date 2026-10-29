import '../../domain/models/delivery_task.dart';
import '../../domain/models/outbound_failure_command.dart';
import '../../domain/models/return_pickup_command.dart';
import 'dto_readers.dart';

/// Strict receipt DTO for the return-pickup shipper writes.
///
/// This DTO accepts only the exact JSON keys emitted by the P08.1 migration.
/// It is a command receipt, not a task/request/table projection: no fallback
/// read is performed and no private return, order, video or bank data can
/// cross this boundary.
final class ReturnPickupCommandAckDto {
  const ReturnPickupCommandAckDto({
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

  static const collectResponseKeys = <String>{
    'task_id',
    'return_request_id',
    'order_id',
    'operation',
    'task_status',
    'return_status',
    'accepted_at',
    'started_at',
    'occurred_at',
    'event_id',
    'request_id',
  };

  static const failResponseKeys = <String>{
    'task_id',
    'return_request_id',
    'order_id',
    'operation',
    'task_status',
    'return_status',
    'reason_code',
    'description',
    'failed_at',
    'occurred_at',
    'event_id',
    'request_id',
  };

  static const handoverResponseKeys = <String>{
    'task_id',
    'return_request_id',
    'order_id',
    'operation',
    'task_status',
    'return_status',
    'reported_at',
    'occurred_at',
    'event_id',
    'request_id',
  };

  /// Union of approved receipt keys, useful to schema tests.  The factory
  /// still selects the operation-specific exact set above.
  static const responseKeys = <String>{
    'task_id',
    'return_request_id',
    'order_id',
    'operation',
    'task_status',
    'return_status',
    'accepted_at',
    'started_at',
    'reported_at',
    'occurred_at',
    'reason_code',
    'description',
    'failed_at',
    'event_id',
    'request_id',
  };

  /// Decode one exact server receipt and guard it against the local command
  /// snapshot.  Missing nullable fields are rejected just like extra fields;
  /// the migration's nullable `description` is accepted only when its key is
  /// present with a null value.
  factory ReturnPickupCommandAckDto.fromJson(
    Map<String, dynamic> json, {
    required ReturnPickupCommand command,
  }) {
    if (!command.isValid) {
      throw DeliveryDtoReaders.invalid('command', 'a valid pickup command');
    }

    final allowed = switch (command.operation) {
      ReturnPickupOperation.collect => collectResponseKeys,
      ReturnPickupOperation.handover => handoverResponseKeys,
      ReturnPickupOperation.fail => failResponseKeys,
    };
    _checkExactKeys(json, allowed, 'pickup acknowledgement');

    final taskId = DeliveryDtoReaders.readRequiredUuid(json, 'task_id');
    _checkSameUuid(taskId, command.taskId, 'task_id');
    final returnRequestId = DeliveryDtoReaders.readRequiredUuid(
      json,
      'return_request_id',
    );
    _checkSameUuid(
      returnRequestId,
      command.returnRequestId,
      'return_request_id',
    );
    final orderId = DeliveryDtoReaders.readRequiredUuid(json, 'order_id');
    _checkSameUuid(orderId, command.orderId, 'order_id');
    final requestId = DeliveryDtoReaders.readRequiredUuid(json, 'request_id');
    _checkSameUuid(requestId, command.requestId, 'request_id');

    final operationText = DeliveryDtoReaders.readRequiredString(
      json,
      'operation',
      nonBlank: false,
    );
    final operation = ReturnPickupOperation.fromValue(operationText);
    if (operation != command.operation) {
      throw DeliveryDtoReaders.invalid(
        'operation',
        'the operation from the command',
      );
    }

    final taskStatus = DeliveryDtoReaders.readRequiredString(
      json,
      'task_status',
      nonBlank: false,
    );
    try {
      DeliveryTaskStatus.fromValue(taskStatus);
    } on FormatException {
      throw DeliveryDtoReaders.invalid('task_status', 'a known task status');
    }
    final returnStatus = DeliveryDtoReaders.readRequiredString(
      json,
      'return_status',
      nonBlank: false,
    );

    final eventId = DeliveryDtoReaders.readRequiredUuid(json, 'event_id');
    final occurredAt = _requiredUtcTimestamp(json, 'occurred_at');

    DateTime? acceptedAt;
    DateTime? startedAt;
    DateTime? reportedAt;
    DateTime? failedAt;
    OutboundFailureReason? reason;
    String? description;

    switch (operation) {
      case ReturnPickupOperation.collect:
        if (taskStatus != 'in_transit' ||
            returnStatus != 'returning_to_store') {
          throw DeliveryDtoReaders.invalid(
            'status',
            'in_transit and returning_to_store for collection',
          );
        }
        acceptedAt = _requiredUtcTimestamp(json, 'accepted_at');
        startedAt = _requiredUtcTimestamp(json, 'started_at');
        if (acceptedAt != startedAt || acceptedAt != occurredAt) {
          throw DeliveryDtoReaders.invalid(
            'timestamps',
            'one server timestamp for accepted, started and occurred',
          );
        }
      case ReturnPickupOperation.handover:
        if (taskStatus != 'in_transit' ||
            returnStatus != 'returning_to_store') {
          throw DeliveryDtoReaders.invalid(
            'status',
            'in_transit and returning_to_store for handover',
          );
        }
        reportedAt = _requiredUtcTimestamp(json, 'reported_at');
        if (reportedAt != occurredAt) {
          throw DeliveryDtoReaders.invalid(
            'timestamps',
            'one server timestamp for reported and occurred',
          );
        }
      case ReturnPickupOperation.fail:
        if (taskStatus != 'failed' ||
            returnStatus != 'awaiting_return_pickup') {
          throw DeliveryDtoReaders.invalid(
            'status',
            'failed and awaiting_return_pickup for failure',
          );
        }
        final reasonText = DeliveryDtoReaders.readRequiredString(
          json,
          'reason_code',
          nonBlank: false,
        );
        try {
          reason = OutboundFailureReason.fromValue(reasonText);
        } on FormatException {
          throw DeliveryDtoReaders.invalid(
            'reason_code',
            'a known pickup failure reason',
          );
        }
        if (reason != command.reason) {
          throw DeliveryDtoReaders.invalid(
            'reason_code',
            'the reason from the command',
          );
        }
        // The migration permits NULL for all reasons except `other`, and the
        // key is required in the approved response shape.
        description = DeliveryDtoReaders.readNullableString(
          json,
          'description',
        );
        if (description != command.trimmedDescription ||
            (reason == OutboundFailureReason.other && description == null)) {
          throw DeliveryDtoReaders.invalid(
            'description',
            'null or the trimmed description from the command',
          );
        }
        failedAt = _requiredUtcTimestamp(json, 'failed_at');
        if (failedAt != occurredAt) {
          throw DeliveryDtoReaders.invalid(
            'timestamps',
            'one server timestamp for failed and occurred',
          );
        }
    }

    return ReturnPickupCommandAckDto(
      taskId: taskId,
      returnRequestId: returnRequestId,
      orderId: orderId,
      operation: operation,
      taskStatus: taskStatus,
      returnStatus: returnStatus,
      eventId: eventId,
      requestId: requestId,
      occurredAt: occurredAt,
      acceptedAt: acceptedAt,
      startedAt: startedAt,
      reportedAt: reportedAt,
      failedAt: failedAt,
      reason: reason,
      description: description,
    );
  }

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

  /// Alias used by callers that call a return request a return ID.
  String get returnId => returnRequestId;

  String get requestKey => requestId;

  String? get reasonCode => reason?.value;

  String? get reasonDescription => description;

  ReturnPickupAck toDomain() => ReturnPickupAck(
    taskId: taskId,
    returnRequestId: returnRequestId,
    orderId: orderId,
    operation: operation,
    taskStatus: taskStatus,
    returnStatus: returnStatus,
    eventId: eventId,
    requestId: requestId,
    occurredAt: occurredAt,
    acceptedAt: acceptedAt,
    startedAt: startedAt,
    reportedAt: reportedAt,
    failedAt: failedAt,
    reason: reason,
    description: description,
  );

  static DateTime _requiredUtcTimestamp(Map<String, dynamic> json, String key) {
    final value = DeliveryDtoReaders.readNullableTimestamp(json, key);
    if (value == null || !value.isUtc) {
      throw DeliveryDtoReaders.invalid(key, 'a required UTC RFC3339 timestamp');
    }
    return value;
  }

  static void _checkExactKeys(
    Map<String, dynamic> json,
    Set<String> allowed,
    String key,
  ) {
    if (json.length != allowed.length ||
        json.keys.any((entry) => !allowed.contains(entry))) {
      throw DeliveryDtoReaders.invalid(
        key,
        'exactly the approved receipt fields',
      );
    }
  }

  static void _checkSameUuid(String value, String expected, String key) {
    if (value.toLowerCase() != expected.toLowerCase()) {
      throw DeliveryDtoReaders.invalid(key, 'the UUID from the command');
    }
  }
}

/// Name used by feature wiring that does not include `Command` in DTO names.
typedef ReturnPickupAckDto = ReturnPickupCommandAckDto;
