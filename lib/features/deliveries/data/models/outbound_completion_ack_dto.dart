import '../../domain/models/outbound_completion_command.dart';
import '../models/dto_readers.dart';

/// Strict receipt returned by complete_outbound_delivery.
final class OutboundCompletionAckDto {
  const OutboundCompletionAckDto({
    required this.requestId,
    required this.taskId,
    required this.orderId,
    required this.eventId,
    required this.attemptNumber,
    required this.deliveryAttemptCount,
    required this.status,
    required this.orderStatus,
    required this.collectedAmountVnd,
    required this.committedAt,
  });

  final String requestId;
  final String taskId;
  final String orderId;
  final String eventId;
  final int attemptNumber;
  final int deliveryAttemptCount;
  final String status;
  final String orderStatus;
  final int collectedAmountVnd;
  final DateTime committedAt;

  factory OutboundCompletionAckDto.fromJson(
    Map<String, dynamic> json, {
    required OutboundCompletionCommand command,
  }) {
    const responseKeys = <String>{
      'task_id',
      'order_id',
      'operation',
      'task_status',
      'order_status',
      'attempt_number',
      'delivery_attempt_count',
      'collected_amount_vnd',
      'completed_at',
      'event_id',
      'request_id',
    };
    if (json.keys.any((key) => !responseKeys.contains(key))) {
      throw const FormatException('Unexpected completion ACK field');
    }
    String string(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Invalid completion ACK $key');
      }
      return value;
    }

    final requestId = string('request_id');
    final taskId = string('task_id');
    final orderId = string('order_id');
    final eventId = string('event_id');
    DeliveryDtoReaders.checkUuid(requestId, 'request_id');
    DeliveryDtoReaders.checkUuid(taskId, 'task_id');
    DeliveryDtoReaders.checkUuid(orderId, 'order_id');
    DeliveryDtoReaders.checkUuid(eventId, 'event_id');
    if (requestId.toLowerCase() != command.requestId.toLowerCase() ||
        taskId.toLowerCase() != command.taskId.toLowerCase()) {
      throw const FormatException('Completion ACK identity mismatch');
    }
    final attempt = json['attempt_number'];
    final amount = json['collected_amount_vnd'];
    if (attempt is! num ||
        attempt % 1 != 0 ||
        attempt < 1 ||
        attempt > 2 ||
        amount is! num ||
        amount % 1 != 0 ||
        amount <= 0) {
      throw const FormatException('Invalid completion ACK counters');
    }
    final operation = string('operation');
    final taskStatus = string('task_status');
    final orderStatus = string('order_status');
    final deliveryAttemptCount = json['delivery_attempt_count'];
    if (operation != 'complete' ||
        taskStatus != 'delivered' ||
        orderStatus != 'delivered' ||
        deliveryAttemptCount is! num ||
        deliveryAttemptCount % 1 != 0 ||
        deliveryAttemptCount.toInt() != attempt.toInt() ||
        amount.toInt() != command.reportedCollectedAmountVnd) {
      throw const FormatException('Completion ACK is not delivered');
    }
    final committedAt = DeliveryDtoReaders.readNullableTimestamp(
      json,
      'completed_at',
    );
    if (committedAt == null || !committedAt.isUtc) {
      throw const FormatException('Invalid completion ACK timestamp');
    }
    return OutboundCompletionAckDto(
      requestId: requestId,
      taskId: taskId,
      orderId: orderId,
      eventId: eventId,
      attemptNumber: attempt.toInt(),
      deliveryAttemptCount: deliveryAttemptCount.toInt(),
      status: taskStatus,
      orderStatus: orderStatus,
      collectedAmountVnd: amount.toInt(),
      committedAt: committedAt,
    );
  }
}
