import '../../../../core/errors/unsupported_data_exception.dart';
import '../../../../core/errors/wire_parsing.dart';

/// Allowlisted notification subject types.  Unknown raw values remain visible
/// through [rawValue] and [isSupported] so an inbox tile can be rendered as a
/// generic item without inventing a route or a business state.
class NotificationSubjectType {
  const NotificationSubjectType._(this.rawValue, this.isSupported);

  static const order = NotificationSubjectType._('order', true);
  static const deliveryTask = NotificationSubjectType._('delivery_task', true);
  static const cod = NotificationSubjectType._('cod', true);
  static const returnRequest = NotificationSubjectType._(
    'return_request',
    true,
  );
  static const conversation = NotificationSubjectType._('conversation', true);
  static const notificationOnly = NotificationSubjectType._(
    'notification_only',
    true,
  );

  factory NotificationSubjectType.fromWire(
    Object? raw, {
    String path = 'subject_type',
  }) {
    if (raw is! String || raw.trim().isEmpty) {
      throw UnsupportedDataException.invalid(
        path: path,
        rawValue: raw,
        expected: 'allowlisted subject_type string',
      );
    }
    const known = <NotificationSubjectType>[
      order,
      deliveryTask,
      cod,
      returnRequest,
      conversation,
      notificationOnly,
    ];
    for (final value in known) {
      if (value.rawValue == raw) return value;
    }
    // Raw inbox rows may outlive a newer producer.  Preserve the value and
    // make target resolution fail closed.
    return NotificationSubjectType._(raw, false);
  }

  static NotificationSubjectType parse(
    Object? raw, {
    String path = 'subject_type',
  }) => NotificationSubjectType.fromWire(raw, path: path);

  final String rawValue;
  final bool isSupported;

  bool get isUnknown => !isSupported;

  @override
  String toString() => rawValue;

  @override
  bool operator ==(Object other) {
    return other is NotificationSubjectType &&
        other.rawValue == rawValue &&
        other.isSupported == isSupported;
  }

  @override
  int get hashCode => Object.hash(rawValue, isSupported);
}

class NotificationItem {
  NotificationItem({
    required String id,
    required String recipientId,
    required String eventId,
    required this.subjectType,
    required String subjectId,
    required String title,
    required String body,
    required DateTime? readAt,
    required DateTime createdAt,
  }) : id = _uuid(id, 'id'),
       recipientId = _uuid(recipientId, 'recipientId'),
       eventId = _uuid(eventId, 'eventId'),
       subjectId = _uuid(subjectId, 'subjectId'),
       title = _text(title, 'title'),
       body = _text(body, 'body'),
       readAt = readAt == null ? null : _utc(readAt, 'readAt'),
       createdAt = _utc(createdAt, 'createdAt');

  final String id;
  final String recipientId;
  final String eventId;
  final NotificationSubjectType subjectType;
  final String subjectId;
  final String title;
  final String body;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isRead => readAt != null;
  String get rawSubjectType => subjectType.rawValue;

  Map<String, Object?> toMap() => {
    'id': id,
    'recipient_id': recipientId,
    'event_id': eventId,
    'subject_type': subjectType.rawValue,
    'subject_id': subjectId,
    'title': title,
    'body': body,
    'read_at': readAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
  };

  static String _uuid(String value, String field) {
    final map = <String, Object?>{field: value};
    return requiredUuid(map, field);
  }

  static String _text(String value, String field) {
    if (value.trim().isEmpty) {
      throw InvalidDomainArgumentException('$field must not be blank.');
    }
    return value;
  }

  static DateTime _utc(DateTime value, String field) {
    if (!value.isUtc) {
      throw InvalidDomainArgumentException('$field must be UTC.');
    }
    return value;
  }
}
