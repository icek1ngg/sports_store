import 'delivery_task.dart';

/// The server-defined buckets used by the MH10 task list.
///
/// The bucket is intentionally separate from [DeliveryTaskStatus].  Failed,
/// cancelled, pending-assignment and manager-action-required tasks remain
/// `ungrouped`; they must not be silently presented as completed work.
enum DeliveryTaskStateGroup {
  waiting('waiting'),
  inTransit('in_transit'),
  completed('completed');

  const DeliveryTaskStateGroup(this.value);

  final String value;

  static DeliveryTaskStateGroup fromValue(String value) {
    for (final group in values) {
      if (group.value == value) return group;
    }
    throw FormatException('Unknown delivery task state group: $value');
  }
}

/// A normalized, validated query for `list_my_delivery_tasks`.
///
/// The object contains only filter and paging values.  The caller identity is
/// obtained by the operational read adapter, never accepted as a parameter.
final class DeliveryTaskQuery {
  factory DeliveryTaskQuery({
    DeliveryTaskKind? kind,
    DeliveryTaskStateGroup? stateGroup,
    String? query,
    int limit = 20,
    String? cursor,
  }) {
    if (limit < 1 || limit > maxPageSize) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 100');
    }

    final normalizedQuery = _normalizeQuery(query);
    final normalizedCursor = _normalizeCursor(cursor);
    return DeliveryTaskQuery._(
      kind: kind,
      stateGroup: stateGroup,
      query: normalizedQuery,
      limit: limit,
      cursor: normalizedCursor,
    );
  }

  const DeliveryTaskQuery._({
    required this.kind,
    required this.stateGroup,
    required this.query,
    required this.limit,
    required this.cursor,
  });

  static const defaultPageSize = 20;
  static const maxPageSize = 100;
  static const maxQueryLength = 200;
  static const maxCursorLength = 4096;

  final DeliveryTaskKind? kind;
  final DeliveryTaskStateGroup? stateGroup;
  final String? query;
  final int limit;
  final String? cursor;

  /// The normalized RPC payload.  Null filter values are deliberate: the
  /// server treats them as no filter while still validating the full request.
  Map<String, dynamic> toRpcParams() => <String, dynamic>{
    'p_kind': kind?.value,
    'p_state_group': stateGroup?.value,
    'p_query': query,
    'p_limit': limit,
    'p_cursor': cursor,
  };

  @override
  bool operator ==(Object other) {
    return other is DeliveryTaskQuery &&
        kind == other.kind &&
        stateGroup == other.stateGroup &&
        query == other.query &&
        limit == other.limit &&
        cursor == other.cursor;
  }

  @override
  int get hashCode => Object.hash(kind, stateGroup, query, limit, cursor);

  static String? _normalizeQuery(String? value) {
    if (value == null) return null;
    final normalized = _trimAscii(value);
    if (normalized.isEmpty) return null;
    if (normalized.runes.length > maxQueryLength) {
      throw ArgumentError.value(
        value,
        'query',
        'must contain at most $maxQueryLength characters',
      );
    }
    return normalized;
  }

  static String? _normalizeCursor(String? value) {
    if (value == null) return null;
    if (value.isEmpty ||
        _trimAscii(value).isEmpty ||
        _trimAscii(value) != value) {
      throw ArgumentError.value(value, 'cursor', 'must be a non-empty token');
    }
    if (value.runes.length > maxCursorLength) {
      throw ArgumentError.value(
        value,
        'cursor',
        'must contain at most $maxCursorLength characters',
      );
    }
    return value;
  }

  // PostgreSQL's btrim contract for this endpoint is ASCII whitespace. Keep
  // client normalization aligned with it; the server still applies its own
  // normalization and authorization checks.
  static String _trimAscii(String value) {
    bool isWhitespace(int codeUnit) {
      return codeUnit == 0x09 ||
          codeUnit == 0x0a ||
          codeUnit == 0x0b ||
          codeUnit == 0x0c ||
          codeUnit == 0x0d ||
          codeUnit == 0x20;
    }

    var start = 0;
    while (start < value.length && isWhitespace(value.codeUnitAt(start))) {
      start++;
    }
    var end = value.length;
    while (end > start && isWhitespace(value.codeUnitAt(end - 1))) {
      end--;
    }
    return value.substring(start, end);
  }
}

/// Counts returned from the full authorized, filtered dataset.
final class DeliveryTaskCounts {
  const DeliveryTaskCounts({
    required this.waiting,
    required this.inTransit,
    required this.completed,
    required this.ungrouped,
  });

  final int waiting;
  final int inTransit;
  final int completed;
  final int ungrouped;

  int get total => waiting + inTransit + completed + ungrouped;

  @override
  bool operator ==(Object other) {
    return other is DeliveryTaskCounts &&
        waiting == other.waiting &&
        inTransit == other.inTransit &&
        completed == other.completed &&
        ungrouped == other.ungrouped;
  }

  @override
  int get hashCode => Object.hash(waiting, inTransit, completed, ungrouped);
}

/// One immutable page returned by the task-list read contract.
final class DeliveryTaskPage {
  DeliveryTaskPage({
    required List<DeliveryTaskSnapshot> items,
    required this.nextCursor,
    required this.filteredTotal,
    required this.counts,
    required this.asOf,
  }) : items = List.unmodifiable(items);

  final List<DeliveryTaskSnapshot> items;
  final String? nextCursor;
  final int filteredTotal;
  final DeliveryTaskCounts counts;
  final DateTime asOf;

  @override
  bool operator ==(Object other) {
    if (other is! DeliveryTaskPage ||
        nextCursor != other.nextCursor ||
        filteredTotal != other.filteredTotal ||
        counts != other.counts ||
        asOf != other.asOf ||
        items.length != other.items.length) {
      return false;
    }
    for (var index = 0; index < items.length; index++) {
      if (items[index] != other.items[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(items),
    nextCursor,
    filteredTotal,
    counts,
    asOf,
  );
}
