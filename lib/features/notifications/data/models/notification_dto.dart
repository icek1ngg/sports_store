import '../../../../core/errors/unsupported_data_exception.dart';
import '../../../../core/errors/wire_parsing.dart';
import '../../domain/models/notification_item.dart';

/// Mapper for the existing nine-column notifications row.  `read_at` is a
/// required nullable key; omission is unsupported because it would make a
/// partial row indistinguishable from an unread row.
class NotificationDto {
  NotificationDto(this.value);

  factory NotificationDto.fromJson(Map<String, Object?> json) {
    return _mapDomainError(
      'notification',
      () => NotificationDto(
        NotificationItem(
          id: requiredUuid(json, 'id'),
          recipientId: requiredUuid(json, 'recipient_id'),
          eventId: requiredUuid(json, 'event_id'),
          subjectType: NotificationSubjectType.fromWire(
            requiredField(json, 'subject_type'),
          ),
          subjectId: requiredUuid(json, 'subject_id'),
          title: requiredString(json, 'title', nonBlank: true),
          body: requiredString(json, 'body', nonBlank: true),
          readAt: nullableUtcTimestamp(json, 'read_at'),
          createdAt: requiredUtcTimestamp(json, 'created_at'),
        ),
      ),
    );
  }

  final NotificationItem value;

  NotificationItem get domain => value;

  Map<String, Object?> toJson() => value.toMap();
}

typedef NotificationItemDto = NotificationDto;

Map<String, Object?> notificationReadSignal({DateTime? clientSignal}) {
  // The server trigger overwrites this value with its own first-read timestamp.
  // The adapter still sends an explicit non-null, offset-bearing signal.
  final value = (clientSignal ?? DateTime.now().toUtc());
  if (!value.isUtc) {
    throw UnsupportedDataException.invalid(
      path: 'read_at',
      rawValue: value,
      expected: 'UTC timestamp',
    );
  }
  return {'read_at': value.toIso8601String()};
}

T _mapDomainError<T>(String path, T Function() parser) {
  try {
    return parser();
  } on InvalidDomainArgumentException {
    throw UnsupportedDataException.invalid(
      path: path,
      rawValue: null,
      expected: 'valid notification projection',
    );
  }
}
