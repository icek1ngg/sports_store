import '../../../../core/errors/unsupported_data_exception.dart';

enum NotificationFilter {
  all('all'),
  unread('unread');

  const NotificationFilter(this.wireValue);

  final String wireValue;

  static NotificationFilter parse(Object? raw) {
    for (final value in values) {
      if (value.wireValue == raw) return value;
    }
    throw UnsupportedDataException.unknownEnum(
      path: 'filter',
      enumName: 'NotificationFilter',
      rawValue: raw,
    );
  }
}

class NotificationQuery {
  NotificationQuery({
    this.filter = NotificationFilter.all,
    this.limit = 20,
    String? cursor,
  }) : cursor = _validateCursor(cursor) {
    if (limit < 1 || limit > 100) {
      throw ArgumentError('Notification limit must be between 1 and 100.');
    }
  }

  final NotificationFilter filter;
  final int limit;
  final String? cursor;

  Map<String, Object?> toQueryParameters() => {
    'filter': filter.wireValue,
    'limit': limit,
    'cursor': cursor,
  };

  static String? _validateCursor(String? cursor) {
    if (cursor == null || cursor.isEmpty) return null;
    if (cursor.length > 2048) {
      throw ArgumentError('Notification cursor must be at most 2048 chars.');
    }
    return cursor;
  }

  @override
  bool operator ==(Object other) {
    return other is NotificationQuery &&
        other.filter == filter &&
        other.limit == limit &&
        other.cursor == cursor;
  }

  @override
  int get hashCode => Object.hash(filter, limit, cursor);
}
