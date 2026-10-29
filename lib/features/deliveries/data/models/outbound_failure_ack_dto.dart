import '../../domain/models/outbound_failure_command.dart';
import 'dto_readers.dart';

/// Strict command receipt returned by `fail_delivery_task`.
///
/// This DTO is deliberately not a task projection.  The failure RPC commits a
/// result and returns an acknowledgement; callers must perform an
/// authoritative task read before rendering the new task/order state.
final class OutboundFailureAckDto {
  const OutboundFailureAckDto({
    required this.taskId,
    required this.orderId,
    required this.operation,
    required this.taskStatus,
    required this.orderStatus,
    required this.attemptNumber,
    required this.deliveryAttemptCount,
    required this.failureReasonCode,
    required this.failureReasonDescription,
    required this.failedAt,
    required this.eventId,
    required this.requestId,
  });

  static const responseKeys = <String>{
    'task_id',
    'order_id',
    'operation',
    'task_status',
    'order_status',
    'attempt_number',
    'delivery_attempt_count',
    'failure_reason_code',
    'failure_reason_description',
    'failed_at',
    'event_id',
    'request_id',
  };

  /// Decode one server acknowledgement and reject every unapproved or
  /// inconsistent field before it can reach presentation code.
  factory OutboundFailureAckDto.fromJson(
    Map<String, dynamic> json, {
    required OutboundFailureCommand command,
  }) {
    if (json.keys.any((key) => !responseKeys.contains(key))) {
      throw DeliveryDtoReaders.invalid(
        'acknowledgement',
        'only the approved failure receipt fields',
      );
    }

    final taskId = DeliveryDtoReaders.readRequiredUuid(json, 'task_id');
    if (!_sameUuid(taskId, command.taskId)) {
      throw DeliveryDtoReaders.invalid(
        'task_id',
        'the task UUID from the command',
      );
    }

    final orderId = DeliveryDtoReaders.readRequiredUuid(json, 'order_id');
    final requestId = DeliveryDtoReaders.readRequiredUuid(json, 'request_id');
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
    if (operation != 'fail') {
      throw DeliveryDtoReaders.invalid(
        'operation',
        'fail for a failure acknowledgement',
      );
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
    if (taskStatus != 'failed') {
      throw DeliveryDtoReaders.invalid('task_status', 'failed');
    }

    final attemptNumber = DeliveryDtoReaders.readRequiredInteger(
      json,
      'attempt_number',
    );
    if (attemptNumber != command.attemptNumber ||
        attemptNumber < 1 ||
        attemptNumber > 2) {
      throw DeliveryDtoReaders.invalid(
        'attempt_number',
        'the attempt number from the command (1 or 2)',
      );
    }

    final deliveryAttemptCount = DeliveryDtoReaders.readRequiredInteger(
      json,
      'delivery_attempt_count',
    );
    if (deliveryAttemptCount != attemptNumber) {
      throw DeliveryDtoReaders.invalid(
        'delivery_attempt_count',
        'the failed attempt number',
      );
    }

    final expectedOrderStatus = attemptNumber == 1
        ? 'awaiting_redelivery'
        : 'awaiting_store_return';
    if (orderStatus != expectedOrderStatus) {
      throw DeliveryDtoReaders.invalid('order_status', expectedOrderStatus);
    }

    final failureReasonCode = DeliveryDtoReaders.readRequiredString(
      json,
      'failure_reason_code',
      nonBlank: false,
    );
    if (failureReasonCode != command.reason.value) {
      throw DeliveryDtoReaders.invalid(
        'failure_reason_code',
        'the reason code from the command',
      );
    }

    // The key is part of the approved response even when the value is null;
    // accepting a missing key would turn a truncated response into a success.
    if (!json.containsKey('failure_reason_description')) {
      throw DeliveryDtoReaders.invalid(
        'failure_reason_description',
        'null or the trimmed description from the command',
      );
    }
    final failureReasonDescription = DeliveryDtoReaders.readNullableString(
      json,
      'failure_reason_description',
    );
    final expectedDescription = command.trimmedDescription;
    if (failureReasonDescription != expectedDescription ||
        (command.reason == OutboundFailureReason.other &&
            failureReasonDescription == null)) {
      throw DeliveryDtoReaders.invalid(
        'failure_reason_description',
        'null or the trimmed description from the command',
      );
    }

    final failedAt = DeliveryDtoReaders.readNullableTimestamp(
      json,
      'failed_at',
    );
    if (failedAt == null || !failedAt.isUtc) {
      throw DeliveryDtoReaders.invalid(
        'failed_at',
        'a required UTC RFC3339 timestamp',
      );
    }

    return OutboundFailureAckDto(
      taskId: taskId,
      orderId: orderId,
      operation: operation,
      taskStatus: taskStatus,
      orderStatus: orderStatus,
      attemptNumber: attemptNumber,
      deliveryAttemptCount: deliveryAttemptCount,
      failureReasonCode: failureReasonCode,
      failureReasonDescription: failureReasonDescription,
      failedAt: failedAt,
      eventId: DeliveryDtoReaders.readRequiredUuid(json, 'event_id'),
      requestId: requestId,
    );
  }

  final String taskId;
  final String orderId;
  final String operation;
  final String taskStatus;
  final String orderStatus;
  final int attemptNumber;
  final int deliveryAttemptCount;
  final String failureReasonCode;
  final String? failureReasonDescription;
  final DateTime failedAt;
  final String eventId;
  final String requestId;

  /// Aliases keep the data boundary readable for callers that use the shorter
  /// reason terminology while retaining the exact server field names above.
  String get reasonCode => failureReasonCode;

  String? get description => failureReasonDescription;

  OutboundFailureAck toDomain() => OutboundFailureAck(
    taskId: taskId,
    requestId: requestId,
    attemptNumber: attemptNumber,
    disposition: OutboundFailureDisposition.forAttempt(attemptNumber),
  );

  static bool _sameUuid(String left, String right) =>
      left.toLowerCase() == right.toLowerCase();
}
