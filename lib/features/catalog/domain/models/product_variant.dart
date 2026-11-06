/// A sellable product variant and its currently available stock.
class ProductVariant {
  const ProductVariant({
    required this.id,
    required this.productId,
    required this.sku,
    required this.label,
    required this.attributes,
    required this.priceVnd,
    required this.availableQuantity,
  });

  final String id;
  final String productId;
  final String sku;
  final String label;
  final Map<String, dynamic> attributes;
  final int priceVnd;
  final int availableQuantity;

  bool get isInStock => availableQuantity > 0;

  @override
  bool operator ==(Object other) {
    return other is ProductVariant &&
        id == other.id &&
        productId == other.productId &&
        sku == other.sku &&
        label == other.label &&
        _jsonEquals(attributes, other.attributes) &&
        priceVnd == other.priceVnd &&
        availableQuantity == other.availableQuantity;
  }

  @override
  int get hashCode => Object.hash(
    id,
    productId,
    sku,
    label,
    _jsonHash(attributes),
    priceVnd,
    availableQuantity,
  );
}

bool _jsonEquals(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_jsonEquals(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_jsonEquals(left[index], right[index])) return false;
    }
    return true;
  }
  return left == right;
}

int _jsonHash(Object? value) {
  if (value is Map) {
    final entries =
        value.entries
            .map(
              (entry) => MapEntry(entry.key.toString(), _jsonHash(entry.value)),
            )
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    return Object.hashAll(
      entries.map((entry) => Object.hash(entry.key, entry.value)),
    );
  }
  if (value is List) return Object.hashAll(value.map(_jsonHash));
  return value.hashCode;
}
