/// The projection source for an item shown to a shipper.
enum DeliveryItemSource {
  orderSnapshot('order_snapshot'),
  returnPlan('return_plan'),
  unavailableRedeliveryPlan('unavailable_redelivery_plan'),
  unavailable('unavailable');

  const DeliveryItemSource(this.value);

  final String value;

  static DeliveryItemSource fromValue(String value) {
    for (final source in values) {
      if (source.value == value) {
        return source;
      }
    }
    throw FormatException('Unknown delivery item source: $value');
  }
}

/// An immutable item in a delivery task projection.
class DeliveryTaskItem {
  DeliveryTaskItem({
    required this.itemId,
    required this.itemSource,
    required this.productName,
    this.variantLabel,
    Map<String, dynamic>? attributes,
    required this.quantity,
    this.quantityCollected,
    this.unitPriceVnd,
    this.lineTotalVnd,
    this.imageUrl,
  }) : attributes = attributes == null ? null : _freezeJsonMap(attributes);

  final String itemId;
  final DeliveryItemSource itemSource;
  final String productName;
  final String? variantLabel;
  final Map<String, dynamic>? attributes;
  final int quantity;
  final int? quantityCollected;
  final int? unitPriceVnd;
  final int? lineTotalVnd;
  final String? imageUrl;

  @override
  bool operator ==(Object other) {
    return other is DeliveryTaskItem &&
        itemId == other.itemId &&
        itemSource == other.itemSource &&
        productName == other.productName &&
        variantLabel == other.variantLabel &&
        _jsonEquals(attributes, other.attributes) &&
        quantity == other.quantity &&
        quantityCollected == other.quantityCollected &&
        unitPriceVnd == other.unitPriceVnd &&
        lineTotalVnd == other.lineTotalVnd &&
        imageUrl == other.imageUrl;
  }

  @override
  int get hashCode => Object.hash(
    itemId,
    itemSource,
    productName,
    variantLabel,
    _jsonHash(attributes),
    quantity,
    quantityCollected,
    unitPriceVnd,
    lineTotalVnd,
    imageUrl,
  );
}

Map<String, dynamic> _freezeJsonMap(Map<String, dynamic> value) {
  final frozen = <String, dynamic>{};
  for (final entry in value.entries) {
    frozen[entry.key] = _freezeJsonValue(entry.value);
  }
  return Map.unmodifiable(frozen);
}

dynamic _freezeJsonValue(Object? value) {
  if (value is Map) {
    final frozen = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw ArgumentError('JSON object keys must be strings');
      }
      frozen[entry.key as String] = _freezeJsonValue(entry.value);
    }
    return Map.unmodifiable(frozen);
  }
  if (value is List) {
    return List.unmodifiable(
      value.map<Object?>((item) => _freezeJsonValue(item)),
    );
  }
  return value;
}

bool _jsonEquals(Object? left, Object? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left is Map && right is Map) {
    if (left.length != right.length) {
      return false;
    }
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_jsonEquals(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (!_jsonEquals(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}

int _jsonHash(Object? value) {
  if (value is Map) {
    final entries =
        value.entries
            .map((entry) => Object.hash(entry.key, _jsonHash(entry.value)))
            .toList()
          ..sort();
    return Object.hashAll(entries);
  }
  if (value is List) {
    return Object.hashAll(value.map(_jsonHash));
  }
  return value.hashCode;
}
