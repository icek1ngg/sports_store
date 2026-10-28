import 'model_validators.dart';
import 'order_status.dart';

class CodSummary {
  CodSummary({
    required String orderId,
    required String? shipperId,
    required this.status,
    required int expectedAmountVnd,
    required int collectedAmountVnd,
    required int receivedAmountVnd,
    required DateTime? collectedAt,
    required String? collectedBy,
    required DateTime? handedOverAt,
    required DateTime? receivedAt,
    required String? receivedBy,
  }) : orderId = validateUuidValue(orderId, field: 'orderId'),
       shipperId = shipperId == null
           ? null
           : validateUuidValue(shipperId, field: 'shipperId'),
       expectedAmountVnd = validateNonNegativeInt(
         expectedAmountVnd,
         field: 'expectedAmountVnd',
       ),
       collectedAmountVnd = validateNonNegativeInt(
         collectedAmountVnd,
         field: 'collectedAmountVnd',
       ),
       receivedAmountVnd = validateNonNegativeInt(
         receivedAmountVnd,
         field: 'receivedAmountVnd',
       ),
       collectedAt = collectedAt == null
           ? null
           : validateUtc(collectedAt, field: 'collectedAt'),
       collectedBy = collectedBy == null
           ? null
           : validateUuidValue(collectedBy, field: 'collectedBy'),
       handedOverAt = handedOverAt == null
           ? null
           : validateUtc(handedOverAt, field: 'handedOverAt'),
       receivedAt = receivedAt == null
           ? null
           : validateUtc(receivedAt, field: 'receivedAt'),
       receivedBy = receivedBy == null
           ? null
           : validateUuidValue(receivedBy, field: 'receivedBy') {
    if (expectedAmountVnd <= 0) {
      throw InvalidDomainArgumentException(
        'expectedAmountVnd must be positive.',
      );
    }
    if (collectedAmountVnd > expectedAmountVnd ||
        receivedAmountVnd > collectedAmountVnd) {
      throw InvalidDomainArgumentException(
        'COD amounts cannot exceed their preceding obligation.',
      );
    }
    if (status == CodStatus.uncollected && collectedAmountVnd != 0) {
      throw InvalidDomainArgumentException(
        'Uncollected COD must have collectedAmountVnd=0.',
      );
    }
    if (status != CodStatus.uncollected &&
        collectedAmountVnd != expectedAmountVnd) {
      throw InvalidDomainArgumentException(
        'Collected COD must equal the expected amount.',
      );
    }
    if (status != CodStatus.received && receivedAmountVnd != 0) {
      throw InvalidDomainArgumentException(
        'COD before store receipt must have receivedAmountVnd=0.',
      );
    }
    if (status == CodStatus.received &&
        receivedAmountVnd != expectedAmountVnd) {
      throw InvalidDomainArgumentException(
        'Received COD must equal the expected amount.',
      );
    }
  }

  final String orderId;
  final String? shipperId;
  final CodStatus status;
  final int expectedAmountVnd;
  final int collectedAmountVnd;
  final int receivedAmountVnd;
  final DateTime? collectedAt;
  final String? collectedBy;
  final DateTime? handedOverAt;
  final DateTime? receivedAt;
  final String? receivedBy;

  Map<String, Object?> toMap() => {
    'order_id': orderId,
    'shipper_id': shipperId,
    'status': status.wireValue,
    'expected_amount_vnd': expectedAmountVnd,
    'collected_amount_vnd': collectedAmountVnd,
    'received_amount_vnd': receivedAmountVnd,
    'collected_at': collectedAt?.toIso8601String(),
    'collected_by': collectedBy,
    'handed_over_at': handedOverAt?.toIso8601String(),
    'received_at': receivedAt?.toIso8601String(),
    'received_by': receivedBy,
  };
}
