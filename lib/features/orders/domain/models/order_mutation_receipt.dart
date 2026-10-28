import 'model_validators.dart';
import 'order.dart';
import 'order_status.dart';

class OrderMutationReceipt {
  OrderMutationReceipt({
    required this.operation,
    required String requestId,
    required String eventId,
    required this.order,
    required DateTime committedAt,
    required this.replayed,
    required this.currentOrder,
  }) : requestId = validateUuidValue(requestId, field: 'requestId'),
       eventId = validateUuidValue(eventId, field: 'eventId'),
       committedAt = validateUtc(committedAt, field: 'committedAt') {
    if (currentOrder != null) {
      throw InvalidDomainArgumentException(
        'currentOrder is reserved and must be null in v1.2 receipts.',
      );
    }
  }

  final OrderOperation operation;
  final String requestId;
  final String eventId;
  final Order order;
  final DateTime committedAt;
  final bool replayed;
  final Order? currentOrder;

  Map<String, Object?> toMap() => {
    'operation': operation.wireValue,
    'request_id': requestId,
    'event_id': eventId,
    'order': order.toMap(),
    'committed_at': committedAt.toIso8601String(),
    'replayed': replayed,
    'current_order': currentOrder?.toMap(),
  };
}
