import '../../domain/models/delivery_task.dart';
import '../../domain/models/outbound_failure_command.dart';
import '../../domain/models/redelivery_command.dart';
import 'dto_readers.dart';

/// Strict receipt decoder for the redelivery command RPCs.
///
/// A receipt is not a task projection.  Every operation has its own exact
/// approved shape and transition checks; malformed or mismatched data is
/// treated as an uncertain acknowledgement by the repository.
final class RedeliveryCommandAckDto {
  const RedeliveryCommandAckDto({
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
    this.completedAt,
    this.closedAt,
    this.failedAt,
    this.reason,
    this.description,
    this.custodyOpen = false,
  });

  static const commonResponseKeys = <String>{
    'task_id',
    'return_request_id',
    'order_id',
    'operation',
    'task_status',
    'return_status',
    'event_id',
    'request_id',
    'occurred_at',
  };

  static const acceptResponseKeys = <String>{
    ...commonResponseKeys,
    'accepted_at',
    'kind',
    'amount_to_collect_vnd',
    'started_at',
  };

  static const startResponseKeys = <String>{
    ...commonResponseKeys,
    'accepted_at',
    'started_at',
    'kind',
    'amount_to_collect_vnd',
  };

  static const completeResponseKeys = <String>{
    ...commonResponseKeys,
    'completed_at',
    'closed_at',
  };

  static const failResponseKeys = <String>{
    ...commonResponseKeys,
    'reason_code',
    'description',
    'failed_at',
    'custody_open',
  };

  factory RedeliveryCommandAckDto.fromJson(
    Map<String, dynamic> json, {
    required RedeliveryCommand command,
  }) {
    if (!command.isValid) {
      throw DeliveryDtoReaders.invalid('command', 'a valid redelivery command');
    }
    final operationText = DeliveryDtoReaders.readRequiredString(
      json,
      'operation',
      nonBlank: false,
    );
    final operation = _operationFor(command, operationText);
    final allowed = switch (operation) {
      RedeliveryOperation.accept => acceptResponseKeys,
      RedeliveryOperation.start => startResponseKeys,
      RedeliveryOperation.complete => completeResponseKeys,
      RedeliveryOperation.fail => failResponseKeys,
    };
    _checkExactKeys(json, allowed, 'redelivery acknowledgement');
    if (operation == RedeliveryOperation.accept ||
        operation == RedeliveryOperation.start) {
      if (json['kind'] != 'redelivery' ||
          json['amount_to_collect_vnd'] != 0 ||
          (operation == RedeliveryOperation.accept &&
              json['started_at'] != null)) {
        throw const FormatException('Invalid free redelivery receipt');
      }
    }

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
    final eventId = DeliveryDtoReaders.readRequiredUuid(json, 'event_id');
    final occurredAt = _requiredUtcTimestamp(json, 'occurred_at');
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

    DateTime? acceptedAt;
    DateTime? startedAt;
    DateTime? completedAt;
    DateTime? closedAt;
    DateTime? failedAt;
    OutboundFailureReason? reason;
    String? description;
    var custodyOpen = false;

    switch (operation) {
      case RedeliveryOperation.accept:
        _expectState(
          taskStatus: taskStatus,
          returnStatus: returnStatus,
          expectedTask: 'accepted',
          expectedReturn: 'awaiting_redelivery',
        );
        acceptedAt = _requiredUtcTimestamp(json, 'accepted_at');
        if (acceptedAt != occurredAt) {
          throw DeliveryDtoReaders.invalid(
            'timestamps',
            'one server timestamp for accepted and occurred',
          );
        }
      case RedeliveryOperation.start:
        _expectState(
          taskStatus: taskStatus,
          returnStatus: returnStatus,
          expectedTask: 'in_transit',
          expectedReturn: 'awaiting_redelivery',
        );
        acceptedAt = _requiredUtcTimestamp(json, 'accepted_at');
        startedAt = _requiredUtcTimestamp(json, 'started_at');
        if (acceptedAt.isAfter(startedAt) || startedAt != occurredAt) {
          throw DeliveryDtoReaders.invalid(
            'timestamps',
            'accepted_at <= started_at and started_at = occurred_at',
          );
        }
      case RedeliveryOperation.complete:
        _expectState(
          taskStatus: taskStatus,
          returnStatus: returnStatus,
          expectedTask: 'delivered',
          expectedReturn: 'rejected_after_inspection',
        );
        completedAt = _requiredUtcTimestamp(json, 'completed_at');
        closedAt = _requiredUtcTimestamp(json, 'closed_at');
        if (completedAt != occurredAt || closedAt != occurredAt) {
          throw DeliveryDtoReaders.invalid(
            'timestamps',
            'one server timestamp for completion, close and occurred',
          );
        }
      case RedeliveryOperation.fail:
        _expectState(
          taskStatus: taskStatus,
          returnStatus: returnStatus,
          expectedTask: 'manager_action_required',
          expectedReturn: 'manager_action_required',
        );
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
            'a known redelivery failure reason',
          );
        }
        if (reason != command.reason) {
          throw DeliveryDtoReaders.invalid(
            'reason_code',
            'the reason from the command',
          );
        }
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
            'one server timestamp for failure and occurred',
          );
        }
        final rawCustody = json['custody_open'];
        if (rawCustody is! bool || !rawCustody) {
          throw DeliveryDtoReaders.invalid(
            'custody_open',
            'true for a failed redelivery',
          );
        }
        custodyOpen = true;
    }

    return RedeliveryCommandAckDto(
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
      completedAt: completedAt,
      closedAt: closedAt,
      failedAt: failedAt,
      reason: reason,
      description: description,
      custodyOpen: custodyOpen,
    );
  }

  final String taskId;
  final String returnRequestId;
  final String orderId;
  final RedeliveryOperation operation;
  final String taskStatus;
  final String returnStatus;
  final String eventId;
  final String requestId;
  final DateTime occurredAt;
  final DateTime? acceptedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? closedAt;
  final DateTime? failedAt;
  final OutboundFailureReason? reason;
  final String? description;
  final bool custodyOpen;

  RedeliveryAck toDomain() => RedeliveryAck(
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
    completedAt: completedAt,
    closedAt: closedAt,
    failedAt: failedAt,
    reason: reason,
    description: description,
    custodyOpen: custodyOpen,
  );

  static RedeliveryOperation _operationFor(
    RedeliveryCommand command,
    String value,
  ) {
    final operation = RedeliveryOperation.fromValue(value);
    if (operation != command.operation) {
      throw DeliveryDtoReaders.invalid(
        'operation',
        'the operation from the command',
      );
    }
    return operation;
  }

  static void _expectState({
    required String taskStatus,
    required String returnStatus,
    required String expectedTask,
    required String expectedReturn,
  }) {
    if (taskStatus != expectedTask || returnStatus != expectedReturn) {
      throw DeliveryDtoReaders.invalid(
        'status',
        '$expectedTask and $expectedReturn for the redelivery transition',
      );
    }
  }

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

typedef RedeliveryAckDto = RedeliveryCommandAckDto;
