import 'dart:convert';

import '../../../cart/domain/models/cart_item.dart';

const _safeIntegerMaximum = 9007199254740991;

/// One variant/quantity sent to the placement RPC.
class PlacementItem {
  PlacementItem({required String variantId, required int quantity})
    : variantId = _normalizeUuid(variantId, field: 'variant_id'),
      quantity = _validateQuantity(quantity);

  final String variantId;
  final int quantity;

  Map<String, Object?> toJson() => {
    'variant_id': variantId,
    'quantity': quantity,
  };

  @override
  bool operator ==(Object other) =>
      other is PlacementItem &&
      other.variantId == variantId &&
      other.quantity == quantity;

  @override
  int get hashCode => Object.hash(variantId, quantity);
}

/// The exact normalized payload used by place_order and durable retry.
class PlacementRequest {
  PlacementRequest({
    required String requestId,
    required List<PlacementItem> items,
    required String recipientName,
    required String recipientPhone,
    required String addressDetail,
    required double latitude,
    required double longitude,
  }) : requestId = _normalizeUuid(requestId, field: 'request_id'),
       items = _normalizeItems(items),
       recipientName = _normalizeText(recipientName, field: 'recipient_name'),
       recipientPhone = _normalizeText(
         recipientPhone,
         field: 'recipient_phone',
       ),
       addressDetail = _normalizeText(addressDetail, field: 'address_detail'),
       latitude = _validateCoordinate(latitude, 'latitude', -90, 90),
       longitude = _validateCoordinate(longitude, 'longitude', -180, 180) {
    if (this.items.isEmpty) {
      throw const FormatException('items must not be empty');
    }
  }

  factory PlacementRequest.fromCart({
    required String requestId,
    required List<CartItem> items,
    required String recipientName,
    required String recipientPhone,
    required String addressDetail,
    required double latitude,
    required double longitude,
  }) {
    if (items.isEmpty || items.any((item) => !item.canCheckout)) {
      throw const FormatException('cart contains unavailable items');
    }
    return PlacementRequest(
      requestId: requestId,
      items: [
        for (final item in items)
          PlacementItem(variantId: item.variantId, quantity: item.quantity),
      ],
      recipientName: recipientName,
      recipientPhone: recipientPhone,
      addressDetail: addressDetail,
      latitude: latitude,
      longitude: longitude,
    );
  }

  factory PlacementRequest.fromJson(Map<String, Object?> json) {
    final rawItems = json['items'];
    if (rawItems is! List) throw const FormatException('items is invalid');
    final items = <PlacementItem>[];
    for (final raw in rawItems) {
      if (raw is! Map) throw const FormatException('item is invalid');
      final map = Map<String, Object?>.from(raw);
      final quantity = map['quantity'];
      if (quantity is! int) throw const FormatException('quantity is invalid');
      items.add(
        PlacementItem(
          variantId: _requiredString(map, 'variant_id'),
          quantity: quantity,
        ),
      );
    }
    return PlacementRequest(
      requestId: _requiredStringAny(json, const ['request_id', 'requestId']),
      items: items,
      recipientName: _requiredStringAny(json, const [
        'recipient_name',
        'recipientName',
      ]),
      recipientPhone: _requiredStringAny(json, const [
        'recipient_phone',
        'recipientPhone',
      ]),
      addressDetail: _requiredStringAny(json, const [
        'address_detail',
        'addressDetail',
      ]),
      latitude: _requiredDoubleAny(json, const ['latitude']),
      longitude: _requiredDoubleAny(json, const ['longitude']),
    );
  }

  final String requestId;
  final List<PlacementItem> items;
  final String recipientName;
  final String recipientPhone;
  final String addressDetail;
  final double latitude;
  final double longitude;

  /// RPC argument names are deliberately kept identical to the agreed
  /// function signature. No client price, customer ID or total is included.
  Map<String, Object?> toRpcParams() => {
    'p_request_id': requestId,
    'p_items': items.map((item) => item.toJson()).toList(growable: false),
    'p_recipient_name': recipientName,
    'p_recipient_phone': recipientPhone,
    'p_address_detail': addressDetail,
    'p_latitude': latitude,
    'p_longitude': longitude,
  };

  /// Persistence shape is intentionally limited to the exact request
  /// payload. It contains no access token, password, session or user profile.
  Map<String, Object?> toJson() => {
    'request_id': requestId,
    'items': items.map((item) => item.toJson()).toList(growable: false),
    'recipient_name': recipientName,
    'recipient_phone': recipientPhone,
    'address_detail': addressDetail,
    'latitude': latitude,
    'longitude': longitude,
  };

  String get fingerprint => jsonEncode(toJson());

  PlacementRequest copyWith({
    String? requestId,
    List<PlacementItem>? items,
    String? recipientName,
    String? recipientPhone,
    String? addressDetail,
    double? latitude,
    double? longitude,
  }) => PlacementRequest(
    requestId: requestId ?? this.requestId,
    items: items ?? this.items,
    recipientName: recipientName ?? this.recipientName,
    recipientPhone: recipientPhone ?? this.recipientPhone,
    addressDetail: addressDetail ?? this.addressDetail,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
  );
}

String _normalizeUuid(String value, {required String field}) {
  final normalized = value.trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
      .hasMatch(normalized)) {
    throw FormatException('$field must be a UUID');
  }
  return normalized;
}

String _normalizeText(String value, {required String field}) {
  final normalized = _contractTrim(value);
  if (normalized.isEmpty) throw FormatException('$field must not be blank');
  return normalized;
}

String _contractTrim(String value) {
  final runes = value.runes.toList(growable: false);
  var start = 0;
  var end = runes.length;
  while (start < end && _contractWhitespace.contains(runes[start])) {
    start++;
  }
  while (end > start && _contractWhitespace.contains(runes[end - 1])) {
    end--;
  }
  return String.fromCharCodes(runes.sublist(start, end));
}

const _contractWhitespace = <int>{
  0x0009,
  0x000A,
  0x000B,
  0x000C,
  0x000D,
  0x0020,
  0x0085,
  0x00A0,
  0x1680,
  0x2000,
  0x2001,
  0x2002,
  0x2003,
  0x2004,
  0x2005,
  0x2006,
  0x2007,
  0x2008,
  0x2009,
  0x200A,
  0x2028,
  0x2029,
  0x202F,
  0x205F,
  0x3000,
};

List<PlacementItem> _normalizeItems(List<PlacementItem> input) {
  final items = List<PlacementItem>.from(input);
  items.sort((a, b) => a.variantId.compareTo(b.variantId));
  for (var index = 1; index < items.length; index++) {
    if (items[index - 1].variantId == items[index].variantId) {
      throw const FormatException('items must not contain duplicate variants');
    }
  }
  return List<PlacementItem>.unmodifiable(items);
}

int _validateQuantity(int value) {
  if (value < 1 || value > _safeIntegerMaximum) {
    throw const FormatException('quantity must be positive');
  }
  return value;
}

double _validateCoordinate(double value, String field, double min, double max) {
  if (!value.isFinite || value < min || value > max) {
    throw FormatException('$field is outside its valid range');
  }
  return value;
}

String _requiredString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String) throw FormatException('$key is invalid');
  return value;
}

String _requiredStringAny(Map<String, Object?> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is String) return value;
  }
  throw FormatException('${keys.first} is invalid');
}

double _requiredDoubleAny(Map<String, Object?> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is num) return value.toDouble();
  }
  throw FormatException('${keys.first} is invalid');
}
