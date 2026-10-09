import 'model_validators.dart';
import 'order_status.dart';

class Order {
  Order({
    required String id,
    required String customerId,
    required String requestId,
    required this.status,
    required String recipientName,
    required String recipientPhone,
    required String addressDetail,
    required double latitude,
    required double longitude,
    required int subtotalVnd,
    required int deliveryFeeVnd,
    required int totalCodVnd,
    required this.deliveryAttemptCount,
    required DateTime placedAt,
    required DateTime? confirmedAt,
    required this.source,
    required String? confirmedBy,
    required DateTime? deliveredAt,
    required this.cancelReason,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : id = validateUuidValue(id),
       customerId = validateUuidValue(customerId, field: 'customerId'),
       requestId = validateUuidValue(requestId, field: 'requestId'),
       recipientName = validateNonBlank(recipientName, field: 'recipientName'),
       recipientPhone = validateNonBlank(
         recipientPhone,
         field: 'recipientPhone',
       ),
       addressDetail = validateNonBlank(addressDetail, field: 'addressDetail'),
       latitude = validateCoordinate(
         latitude,
         field: 'latitude',
         min: -90,
         max: 90,
       ),
       longitude = validateCoordinate(
         longitude,
         field: 'longitude',
         min: -180,
         max: 180,
       ),
       subtotalVnd = validateNonNegativeInt(subtotalVnd, field: 'subtotalVnd'),
       deliveryFeeVnd = validateNonNegativeInt(
         deliveryFeeVnd,
         field: 'deliveryFeeVnd',
       ),
       totalCodVnd = validateNonNegativeInt(totalCodVnd, field: 'totalCodVnd'),
       placedAt = validateUtc(placedAt, field: 'placedAt'),
       confirmedAt = confirmedAt == null
           ? null
           : validateUtc(confirmedAt, field: 'confirmedAt'),
       confirmedBy = confirmedBy == null
           ? null
           : validateUuidValue(confirmedBy, field: 'confirmedBy'),
       deliveredAt = deliveredAt == null
           ? null
           : validateUtc(deliveredAt, field: 'deliveredAt'),
       createdAt = validateUtc(createdAt, field: 'createdAt'),
       updatedAt = validateUtc(updatedAt, field: 'updatedAt') {
    if (deliveryFeeVnd != 30000) {
      throw InvalidDomainArgumentException('deliveryFeeVnd must equal 30000.');
    }
    if (totalCodVnd != subtotalVnd + deliveryFeeVnd) {
      throw InvalidDomainArgumentException(
        'totalCodVnd must equal subtotalVnd + deliveryFeeVnd.',
      );
    }
    if (deliveryAttemptCount < 0 || deliveryAttemptCount > 2) {
      throw InvalidDomainArgumentException(
        'deliveryAttemptCount must be between 0 and 2.',
      );
    }
    final reason = cancelReason;
    if (reason != null && reason.trim().isEmpty) {
      throw InvalidDomainArgumentException('cancelReason must not be blank.');
    }
  }

  final String id;
  final String customerId;
  final String requestId;
  final OrderStatus status;
  final String recipientName;
  final String recipientPhone;
  final String addressDetail;
  final double latitude;
  final double longitude;
  final int subtotalVnd;
  final int deliveryFeeVnd;
  final int totalCodVnd;
  final int deliveryAttemptCount;
  final DateTime placedAt;
  final DateTime? confirmedAt;
  final OrderConfirmationSource? source;
  final String? confirmedBy;
  final DateTime? deliveredAt;
  final String? cancelReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'customer_id': customerId,
    'request_id': requestId,
    'status': status.wireValue,
    'recipient_name': recipientName,
    'recipient_phone': recipientPhone,
    'address_detail': addressDetail,
    'latitude': latitude,
    'longitude': longitude,
    'subtotal_vnd': subtotalVnd,
    'delivery_fee_vnd': deliveryFeeVnd,
    'total_cod_vnd': totalCodVnd,
    'delivery_attempt_count': deliveryAttemptCount,
    'placed_at': placedAt.toIso8601String(),
    'confirmed_at': confirmedAt?.toIso8601String(),
    'source': source?.wireValue,
    'confirmed_by': confirmedBy,
    'delivered_at': deliveredAt?.toIso8601String(),
    'cancel_reason': cancelReason,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  @override
  bool operator ==(Object other) {
    return other is Order &&
        other.id == id &&
        other.customerId == customerId &&
        other.requestId == requestId &&
        other.status == status &&
        other.recipientName == recipientName &&
        other.recipientPhone == recipientPhone &&
        other.addressDetail == addressDetail &&
        other.latitude == latitude &&
        other.longitude == longitude &&
        other.subtotalVnd == subtotalVnd &&
        other.deliveryFeeVnd == deliveryFeeVnd &&
        other.totalCodVnd == totalCodVnd &&
        other.deliveryAttemptCount == deliveryAttemptCount &&
        other.placedAt == placedAt &&
        other.confirmedAt == confirmedAt &&
        other.source == source &&
        other.confirmedBy == confirmedBy &&
        other.deliveredAt == deliveredAt &&
        other.cancelReason == cancelReason &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    customerId,
    requestId,
    status,
    recipientName,
    recipientPhone,
    addressDetail,
    latitude,
    longitude,
    subtotalVnd,
    deliveryFeeVnd,
    totalCodVnd,
    deliveryAttemptCount,
    placedAt,
    confirmedAt,
    source,
    confirmedBy,
    deliveredAt,
    cancelReason,
    createdAt,
    updatedAt,
  ]);
}
