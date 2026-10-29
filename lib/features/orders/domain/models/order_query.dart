import 'model_validators.dart';
import 'order_status.dart';

class OrderQuery {
  OrderQuery({
    String? search,
    Iterable<OrderStatus> statuses = const <OrderStatus>[],
    String? cursor,
    int limit = 20,
  }) : search = _normalizeSearch(search),
       statuses = _normalizeStatuses(statuses),
       cursor = _normalizeCursor(cursor),
       limit = _validateLimit(limit);

  final String? search;
  final List<OrderStatus> statuses;
  final String? cursor;
  final int limit;

  static String? _normalizeSearch(String? value) {
    final trimmed = value == null ? null : contractTrim(value);
    if (trimmed == null || trimmed.isEmpty) return null;
    if (trimmed.runes.length > 200) {
      throw InvalidDomainArgumentException(
        'search must contain at most 200 Unicode scalar values.',
      );
    }
    return trimmed;
  }

  static List<OrderStatus> _normalizeStatuses(Iterable<OrderStatus> input) {
    final unique = input.toSet().toList()
      ..sort((a, b) => a.wireValue.compareTo(b.wireValue));
    return List<OrderStatus>.unmodifiable(unique);
  }

  static String? _normalizeCursor(String? value) {
    if (value == null || value.isEmpty) return null;
    if (value.length > 2048) {
      throw InvalidDomainArgumentException(
        'cursor must be at most 2048 chars.',
      );
    }
    return value;
  }

  static int _validateLimit(int value) {
    if (value < 1 || value > 100) {
      throw InvalidDomainArgumentException('limit must be between 1 and 100.');
    }
    return value;
  }

  Map<String, Object?> toRpcParams() => {
    'p_search': search,
    'p_statuses': statuses.map((status) => status.wireValue).toList(),
    'p_limit': limit,
    'p_cursor': cursor,
  };

  @override
  bool operator ==(Object other) {
    return other is OrderQuery &&
        other.search == search &&
        other.cursor == cursor &&
        other.limit == limit &&
        _sameStatuses(other.statuses, statuses);
  }

  @override
  int get hashCode =>
      Object.hash(search, cursor, limit, Object.hashAll(statuses));

  OrderQuery copyWith({
    Object? search = _unset,
    Iterable<OrderStatus>? statuses,
    Object? cursor = _unset,
    int? limit,
  }) {
    return OrderQuery(
      search: identical(search, _unset) ? this.search : search as String?,
      statuses: statuses ?? this.statuses,
      cursor: identical(cursor, _unset) ? this.cursor : cursor as String?,
      limit: limit ?? this.limit,
    );
  }
}

bool _sameStatuses(List<OrderStatus> left, List<OrderStatus> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

const _unset = Object();
