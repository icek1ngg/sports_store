import '../../domain/models/outbound_retry_command.dart';
import 'dto_readers.dart';

/// Strict receipt returned by `retry_outbound_delivery_task`.
final class OutboundRetryAckDto {
  const OutboundRetryAckDto({
    required this.taskId,
    required this.failedTaskId,
    required this.retryTaskId,
    required this.orderId,
    required this.operation,
    required this.decision,
    required this.taskStatus,
    required this.orderStatus,
    required this.attemptNumber,
    required this.deliveryAttemptCount,
    required this.holderId,
    required this.acceptedAt,
    required this.startedAt,
    required this.eventId,
    required this.requestId,
  });

  static const responseKeys = <String>{
    'task_id',
    'failed_task_id',
    'retry_task_id',
    'order_id',
    'operation',
    'decision',
    'task_status',
    'order_status',
    'attempt_number',
    'delivery_attempt_count',
    'holder_id',
    'accepted_at',
    'started_at',
    'event_id',
    'request_id',
  };

  factory OutboundRetryAckDto.fromJson(
    Map<String, dynamic> json, {
    required OutboundRetryCommand command,
  }) {
    if (json.keys.any((key) => !responseKeys.contains(key))) {
      throw DeliveryDtoReaders.invalid(
        'acknowledgement',
        'only the approved retry receipt fields',
      );
    }

    final taskId = DeliveryDtoReaders.readRequiredUuid(json, 'task_id');
    final failedTaskId = DeliveryDtoReaders.readRequiredUuid(
      json,
      'failed_task_id',
    );
    final retryTaskId = DeliveryDtoReaders.readRequiredUuid(
      json,
      'retry_task_id',
    );
    if (!_sameUuid(failedTaskId, command.taskId)) {
      throw DeliveryDtoReaders.invalid(
        'failed_task_id',
        'the failed task UUID from the command',
      );
    }
    if (!_sameUuid(taskId, retryTaskId)) {
      throw DeliveryDtoReaders.invalid('task_id', 'the retry task UUID');
    }

    final orderId = DeliveryDtoReaders.readRequiredUuid(json, 'order_id');
    final operation = DeliveryDtoReaders.readRequiredString(
      json,
      'operation',
      nonBlank: false,
    );
    final decision = DeliveryDtoReaders.readRequiredString(
      json,
      'decision',
      nonBlank: false,
    );
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
    if (operation != 'decide_outbound_retry' || decision != 'retry') {
      throw DeliveryDtoReaders.invalid(
        'operation',
        'decide_outbound_retry with retry decision',
      );
    }
    if (taskStatus != 'assigned' || orderStatus != 'awaiting_pickup') {
      throw DeliveryDtoReaders.invalid(
        'status',
        'an assigned retry task and awaiting_pickup order',
      );
    }

    final attemptNumber = DeliveryDtoReaders.readRequiredInteger(
      json,
      'attempt_number',
    );
    final deliveryAttemptCount = DeliveryDtoReaders.readRequiredInteger(
      json,
      'delivery_attempt_count',
    );
    if (attemptNumber != 2 || deliveryAttemptCount != 1) {
      throw DeliveryDtoReaders.invalid(
        'attempt_number',
        'attempt 2 with one completed outbound attempt',
      );
    }

    final holderId = DeliveryDtoReaders.readRequiredUuid(json, 'holder_id');
    if (!json.containsKey('accepted_at') || !json.containsKey('started_at')) {
      throw DeliveryDtoReaders.invalid(
        'timestamps',
        'accepted_at and started_at keys',
      );
    }
    final acceptedAt = DeliveryDtoReaders.readNullableTimestamp(
      json,
      'accepted_at',
    );
    final startedAt = DeliveryDtoReaders.readNullableTimestamp(
      json,
      'started_at',
    );
    if (acceptedAt != null || startedAt != null) {
      throw DeliveryDtoReaders.invalid(
        'timestamps',
        'null accepted_at and started_at for an unaccepted retry task',
      );
    }

    final requestId = DeliveryDtoReaders.readRequiredUuid(json, 'request_id');
    if (!_sameUuid(requestId, command.requestId)) {
      throw DeliveryDtoReaders.invalid(
        'request_id',
        'the request UUID from the command',
      );
    }

    return OutboundRetryAckDto(
      taskId: taskId,
      failedTaskId: failedTaskId,
      retryTaskId: retryTaskId,
      orderId: orderId,
      operation: operation,
      decision: decision,
      taskStatus: taskStatus,
      orderStatus: orderStatus,
      attemptNumber: attemptNumber,
      deliveryAttemptCount: deliveryAttemptCount,
      holderId: holderId,
      acceptedAt: acceptedAt,
      startedAt: startedAt,
      eventId: DeliveryDtoReaders.readRequiredUuid(json, 'event_id'),
      requestId: requestId,
    );
  }

  final String taskId;
  final String failedTaskId;
  final String retryTaskId;
  final String orderId;
  final String operation;
  final String decision;
  final String taskStatus;
  final String orderStatus;
  final int attemptNumber;
  final int deliveryAttemptCount;
  final String holderId;
  final DateTime? acceptedAt;
  final DateTime? startedAt;
  final String eventId;
  final String requestId;

  OutboundRetryAck toDomain() => OutboundRetryAck(
    failedTaskId: failedTaskId,
    retryTaskId: retryTaskId,
    requestId: requestId,
  );

  static bool _sameUuid(String left, String right) =>
      left.toLowerCase() == right.toLowerCase();
}
