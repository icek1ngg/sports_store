import '../../domain/models/outbound_task_command.dart';
import 'dto_readers.dart';

/// Strict acknowledgement returned by the production accept/start RPCs.
///
/// An acknowledgement is a command receipt, not a task projection. It is
/// accepted only when every identity, transition, counter, and timestamp
/// agrees with the command that was sent. The caller must still perform an
/// authoritative task read before rendering the new state.
final class OutboundTaskCommandAckDto {
  const OutboundTaskCommandAckDto({
    required this.taskId,
    required this.orderId,
    required this.operation,
    required this.taskStatus,
    required this.orderStatus,
    required this.attemptNumber,
    required this.deliveryAttemptCount,
    required this.acceptedAt,
    required this.startedAt,
    required this.dispatchEventId,
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
    'accepted_at',
    'started_at',
    'dispatch_event_id',
    'event_id',
    'request_id',
  };

  /// Decode and validate one server response.
  factory OutboundTaskCommandAckDto.fromJson(
    Map<String, dynamic> json, {
    required OutboundTaskCommand command,
  }) {
    if (json.keys.any((key) => !responseKeys.contains(key))) {
      throw DeliveryDtoReaders.invalid(
        'acknowledgement',
        'only the approved command receipt fields',
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

    final expectedOperation = switch (command.action) {
      OutboundTaskAction.acceptGoods => 'accept',
      OutboundTaskAction.startDelivery => 'start',
    };
    final operation = DeliveryDtoReaders.readRequiredString(
      json,
      'operation',
      nonBlank: false,
    );
    if (operation != expectedOperation) {
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
    final orderStatus = DeliveryDtoReaders.readRequiredString(
      json,
      'order_status',
      nonBlank: false,
    );
    final attemptNumber = DeliveryDtoReaders.readRequiredInteger(
      json,
      'attempt_number',
    );
    final deliveryAttemptCount = DeliveryDtoReaders.readRequiredInteger(
      json,
      'delivery_attempt_count',
    );
    if (attemptNumber < 1 || attemptNumber > 2) {
      throw DeliveryDtoReaders.invalid(
        'attempt_number',
        'an integer between 1 and 2',
      );
    }

    final acceptedAt = _requiredTimestamp(json, 'accepted_at');
    if (!json.containsKey('started_at')) {
      throw DeliveryDtoReaders.invalid(
        'started_at',
        'null or an RFC3339 timestamp with timezone',
      );
    }
    final startedAt = DeliveryDtoReaders.readNullableTimestamp(
      json,
      'started_at',
    );
    final expectedTaskStatus = expectedOperation == 'accept'
        ? 'accepted'
        : 'in_transit';
    final expectedOrderStatus = expectedOperation == 'accept'
        ? 'awaiting_pickup'
        : 'delivering';
    if (taskStatus != expectedTaskStatus ||
        orderStatus != expectedOrderStatus) {
      throw DeliveryDtoReaders.invalid(
        'status',
        'the server transition for $expectedOperation',
      );
    }

    final expectedCount = expectedOperation == 'accept'
        ? attemptNumber - 1
        : attemptNumber;
    if (deliveryAttemptCount != expectedCount) {
      throw DeliveryDtoReaders.invalid(
        'delivery_attempt_count',
        'the count for $expectedOperation and attempt_number',
      );
    }

    if (expectedOperation == 'accept') {
      if (startedAt != null) {
        throw DeliveryDtoReaders.invalid(
          'started_at',
          'null for an accept acknowledgement',
        );
      }
    } else {
      if (startedAt == null || acceptedAt.isAfter(startedAt)) {
        throw DeliveryDtoReaders.invalid(
          'started_at',
          'a timestamp at or after accepted_at',
        );
      }
    }

    return OutboundTaskCommandAckDto(
      taskId: taskId,
      orderId: orderId,
      operation: operation,
      taskStatus: taskStatus,
      orderStatus: orderStatus,
      attemptNumber: attemptNumber,
      deliveryAttemptCount: deliveryAttemptCount,
      acceptedAt: acceptedAt,
      startedAt: startedAt,
      dispatchEventId: DeliveryDtoReaders.readRequiredUuid(
        json,
        'dispatch_event_id',
      ),
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
  final DateTime acceptedAt;
  final DateTime? startedAt;
  final String dispatchEventId;
  final String eventId;
  final String requestId;

  static DateTime _requiredTimestamp(Map<String, dynamic> json, String key) {
    final value = DeliveryDtoReaders.readNullableTimestamp(json, key);
    if (value == null) {
      throw DeliveryDtoReaders.invalid(
        key,
        'an RFC3339 timestamp with timezone',
      );
    }
    return value;
  }

  static bool _sameUuid(String left, String right) =>
      left.toLowerCase() == right.toLowerCase();
}
