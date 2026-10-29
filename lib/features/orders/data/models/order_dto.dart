import '../../../../core/errors/unsupported_data_exception.dart';
import '../../../../core/errors/wire_parsing.dart';
import '../../domain/models/order.dart';
import '../../domain/models/order_item.dart';
import '../../domain/models/order_status.dart';

// Canonical base projections integrated from the Orders owner's phase-2 branch.
// Keep these classes in Orders when integrating its remaining projections.
/// Data-layer mapper for the canonical 21-key `OrderDto` wire object.
class OrderDto {
  OrderDto(this.value);

  factory OrderDto.fromJson(Map<String, Object?> json) {
    return _mapDomainError(
      'order',
      () => OrderDto(
        Order(
          id: requiredUuid(json, 'id'),
          customerId: requiredUuid(json, 'customer_id'),
          requestId: requiredUuid(json, 'request_id'),
          status: OrderStatus.parse(requiredField(json, 'status')),
          recipientName: requiredString(json, 'recipient_name', nonBlank: true),
          recipientPhone: requiredString(
            json,
            'recipient_phone',
            nonBlank: true,
          ),
          addressDetail: requiredString(json, 'address_detail', nonBlank: true),
          latitude: requiredFiniteDouble(json, 'latitude', min: -90, max: 90),
          longitude: requiredFiniteDouble(
            json,
            'longitude',
            min: -180,
            max: 180,
          ),
          subtotalVnd: requiredInt(json, 'subtotal_vnd', min: 0),
          deliveryFeeVnd: requiredInt(json, 'delivery_fee_vnd', min: 0),
          totalCodVnd: requiredInt(json, 'total_cod_vnd', min: 0),
          deliveryAttemptCount: requiredInt(
            json,
            'delivery_attempt_count',
            min: 0,
            max: 2,
          ),
          placedAt: requiredUtcTimestamp(json, 'placed_at'),
          confirmedAt: nullableUtcTimestamp(json, 'confirmed_at'),
          source: _nullableConfirmationSource(json),
          confirmedBy: nullableUuid(json, 'confirmed_by'),
          deliveredAt: nullableUtcTimestamp(json, 'delivered_at'),
          cancelReason: nullableString(json, 'cancel_reason'),
          createdAt: requiredUtcTimestamp(json, 'created_at'),
          updatedAt: requiredUtcTimestamp(json, 'updated_at'),
        ),
      ),
    );
  }

  final Order value;

  Order get domain => value;
  String get id => value.id;
  OrderStatus get status => value.status;

  Map<String, Object?> toJson() => value.toMap();
}

class OrderItemDto {
  OrderItemDto(this.value);

  factory OrderItemDto.fromJson(Map<String, Object?> json) {
    return _mapDomainError(
      'order_item',
      () => OrderItemDto(
        OrderItem(
          id: requiredUuid(json, 'id'),
          orderId: requiredUuid(json, 'order_id'),
          productId: requiredUuid(json, 'product_id'),
          variantId: requiredUuid(json, 'variant_id'),
          productName: requiredString(json, 'product_name', nonBlank: true),
          variantLabel: requiredString(json, 'variant_label', nonBlank: true),
          attributes: requiredObject(json, 'attributes'),
          unitPriceVnd: requiredInt(json, 'unit_price_vnd', min: 0),
          quantity: requiredInt(json, 'quantity', min: 1),
          lineTotalVnd: requiredInt(json, 'line_total_vnd', min: 0),
          createdAt: requiredUtcTimestamp(json, 'created_at'),
        ),
      ),
    );
  }

  final OrderItem value;

  OrderItem get domain => value;

  Map<String, Object?> toJson() => value.toMap();
}

OrderConfirmationSource? _nullableConfirmationSource(
  Map<String, Object?> json,
) {
  final value = requiredField(json, 'source');
  return value == null ? null : OrderConfirmationSource.parse(value);
}

T _mapDomainError<T>(String path, T Function() parser) {
  try {
    return parser();
  } on InvalidDomainArgumentException {
    throw UnsupportedDataException.invalid(
      path: path,
      rawValue: null,
      expected: 'valid domain projection',
    );
  }
}
