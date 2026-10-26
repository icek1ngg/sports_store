import 'cod_collection.dart';

/// Server-side filters for the role-scoped `list_cod_collections` read.
///
/// The caller identity is never part of this object. A shipper filter is
/// checked against the authenticated identity by the repository and again by
/// the database function.
final class CodCollectionQuery {
  factory CodCollectionQuery({
    String? shipperId,
    String? orderId,
    Iterable<CodStatus>? statuses,
    int limit = 20,
    String? cursor,
  }) {
    if (limit < 1 || limit > maxPageSize) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 100');
    }
    final normalizedShipper = _normalizeUuid(shipperId, 'shipperId');
    final normalizedOrder = _normalizeUuid(orderId, 'orderId');
    final normalizedCursor = cursor;
    if (normalizedCursor != null &&
        (normalizedCursor.isEmpty ||
            normalizedCursor != normalizedCursor.trim() ||
            normalizedCursor.runes.length > maxCursorLength)) {
      throw ArgumentError.value(
        cursor,
        'cursor',
        'must be a bounded opaque cursor',
      );
    }
    final statusSet = <CodStatus>{...?statuses};
    if (statusSet.length > CodStatus.values.length) {
      throw ArgumentError.value(
        statuses,
        'statuses',
        'contains an invalid value',
      );
    }
    final normalizedStatuses = statusSet.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return CodCollectionQuery._(
      shipperId: normalizedShipper,
      orderId: normalizedOrder,
      statuses: List.unmodifiable(normalizedStatuses),
      limit: limit,
      cursor: normalizedCursor,
    );
  }

  const CodCollectionQuery._({
    required this.shipperId,
    required this.orderId,
    required this.statuses,
    required this.limit,
    required this.cursor,
  });

  static const maxPageSize = 100;
  static const maxCursorLength = 4096;

  final String? shipperId;
  final String? orderId;
  final List<CodStatus> statuses;
  final int limit;
  final String? cursor;

  Map<String, dynamic> toRpcParams() => <String, dynamic>{
    'p_shipper_id': shipperId,
    'p_order_id': orderId,
    'p_statuses': statuses.isEmpty
        ? null
        : statuses.map((status) => status.value).toList(growable: false),
    'p_limit': limit,
    'p_cursor': cursor,
  };

  @override
  bool operator ==(Object other) =>
      other is CodCollectionQuery &&
      shipperId == other.shipperId &&
      orderId == other.orderId &&
      _listEquals(statuses, other.statuses) &&
      limit == other.limit &&
      cursor == other.cursor;

  @override
  int get hashCode =>
      Object.hash(shipperId, orderId, Object.hashAll(statuses), limit, cursor);
}

String? _normalizeUuid(String? value, String key) {
  if (value == null) return null;
  final normalized = value.trim();
  if (!_uuidPattern.hasMatch(normalized)) {
    throw ArgumentError.value(value, key, 'must be a UUID');
  }
  return normalized;
}

bool _listEquals(List<Object> a, List<Object> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
