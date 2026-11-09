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
    String? productImageUrl,
  }) : id = validateUuidValue(id),
       orderId = validateUuidValue(orderId, field: 'orderId'),
       productId = validateUuidValue(productId, field: 'productId'),
       variantId = validateUuidValue(variantId, field: 'variantId'),
       productName = validateNonBlank(productName, field: 'productName'),
       variantLabel = validateNonBlank(variantLabel, field: 'variantLabel'),
       attributes = freezeObject(attributes),
       productImageUrl = _normalizedProductImageUrl(productImageUrl),
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

  /// Optional product-level image captured when the order was placed. This
  /// does not establish that the photograph depicts this exact variant color.
  final String? productImageUrl;
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
    if (productImageUrl != null) 'product_image_url': productImageUrl,
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
        other.productImageUrl == productImageUrl &&
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
    productImageUrl,
    unitPriceVnd,
    quantity,
    lineTotalVnd,
    createdAt,
  );
}

String? _normalizedProductImageUrl(String? value) {
  final path = value?.trim();
  if (path == null ||
      path.isEmpty ||
      path.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    return null;
  }
  final uri = Uri.tryParse(path);
  if (uri == null) return null;
  if (uri.hasScheme) {
    return uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty
        ? path
        : null;
  }
  // A private Storage object path is resolved by the shared image provider.
  String decoded;
  try {
    decoded = Uri.decodeComponent(path);
  } on FormatException {
    return null;
  }
  if (uri.hasAuthority ||
      uri.hasQuery ||
      uri.hasFragment ||
      path.startsWith('/') ||
      path.contains('\\') ||
      decoded.startsWith('/') ||
      decoded.contains('\\') ||
      decoded.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
      decoded.split('/').any((segment) => segment == '.' || segment == '..')) {
    return null;
  }
  return path;
}
