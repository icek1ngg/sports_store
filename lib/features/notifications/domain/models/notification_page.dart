import '../../../../core/errors/unsupported_data_exception.dart';
import 'notification_item.dart';

class NotificationPage {
  NotificationPage({
    required List<NotificationItem> items,
    required this.nextCursor,
    required this.unreadCount,
    required this.asOf,
  }) : items = List<NotificationItem>.unmodifiable(items) {
    if (unreadCount != null && unreadCount! < 0) {
      throw UnsupportedDataException.invalid(
        path: 'unreadCount',
        rawValue: unreadCount,
        expected: 'null or non-negative integer',
      );
    }
    if (asOf != null && !asOf!.isUtc) {
      throw UnsupportedDataException.invalid(
        path: 'asOf',
        rawValue: asOf,
        expected: 'null or UTC timestamp',
      );
    }
  }

  final List<NotificationItem> items;
  final String? nextCursor;
  final int? unreadCount;
  final DateTime? asOf;

  NotificationPage copyWith({
    List<NotificationItem>? items,
    Object? nextCursor = _unset,
    Object? unreadCount = _unset,
    Object? asOf = _unset,
  }) {
    return NotificationPage(
      items: items ?? this.items,
      nextCursor: identical(nextCursor, _unset)
          ? this.nextCursor
          : nextCursor as String?,
      unreadCount: identical(unreadCount, _unset)
          ? this.unreadCount
          : unreadCount as int?,
      asOf: identical(asOf, _unset) ? this.asOf : asOf as DateTime?,
    );
  }
}

const _unset = Object();
