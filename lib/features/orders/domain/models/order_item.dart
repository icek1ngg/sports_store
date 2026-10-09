import 'model_validators.dart';

class OrderItem {
  OrderItem({
    required String id,
    required String orderId,
    required String productId,
    required String variantId,
    required String productName,
    required String variantLabel,
    required Map<String, Object?> attributes,
    required int unitPriceVnd,
    required int quantity,
    required int lineTotalVnd,
    required DateTime createdAt,
  }) : id = validateUuidValue(id),
       orderId = validateUuidValue(orderId, field: 'orderId'),
       productId = validateUuidValue(productId, field: 'productId'),
       variantId = validateUuidValue(variantId, field: 'variantId'),
       productName = validateNonBlank(productName, field: 'productName'),
       variantLabel = validateNonBlank(variantLabel, field: 'variantLabel'),
       attributes = freezeObject(attributes),
       unitPriceVnd = validateNonNegativeInt(
         unitPriceVnd,
         field: 'unitPriceVnd',
       ),
       quantity = validatePositiveInt(quantity, field: 'quantity'),
       lineTotalVnd = validateNonNegativeInt(
         lineTotalVnd,
         field: 'lineTotalVnd',
       ),
       createdAt = validateUtc(createdAt, field: 'createdAt') {
    if (lineTotalVnd != unitPriceVnd * quantity) {
      throw InvalidDomainArgumentException(
        'lineTotalVnd must equal unitPriceVnd * quantity.',
      );
    }
  }

  final String id;
  final String orderId;
  final String productId;
  final String variantId;
  final String productName;
  final String variantLabel;
  final Map<String, Object?> attributes;
  final int unitPriceVnd;
  final int quantity;
  final int lineTotalVnd;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'order_id': orderId,
    'product_id': productId,
    'variant_id': variantId,
    'product_name': productName,
    'variant_label': variantLabel,
    'attributes': attributes,
    'unit_price_vnd': unitPriceVnd,
    'quantity': quantity,
    'line_total_vnd': lineTotalVnd,
    'created_at': createdAt.toIso8601String(),
  };

  @override
  bool operator ==(Object other) {
    return other is OrderItem &&
        other.id == id &&
        other.orderId == orderId &&
        other.productId == productId &&
        other.variantId == variantId &&
        other.productName == productName &&
        other.variantLabel == variantLabel &&
        other.attributes.toString() == attributes.toString() &&
        other.unitPriceVnd == unitPriceVnd &&
        other.quantity == quantity &&
        other.lineTotalVnd == lineTotalVnd &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    orderId,
    productId,
    variantId,
    productName,
    variantLabel,
    attributes.toString(),
    unitPriceVnd,
    quantity,
    lineTotalVnd,
    createdAt,
  );
}
