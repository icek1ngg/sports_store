import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/errors/unsupported_data_exception.dart';
import 'package:sports_store/features/notifications/data/models/notification_dto.dart';
import 'package:sports_store/features/notifications/domain/models/notification_page.dart';
import 'package:sports_store/features/notifications/domain/models/notification_query.dart';

import '../../../fixtures/order_notification_fixtures.dart';

void main() {
  group('NotificationDto', () {
    test('maps all nine row keys and computes read state', () {
      final unread = NotificationDto.fromJson(fixtureNotificationJson()).domain;
      final read = NotificationDto.fromJson(
        fixtureNotificationJson(readAt: '2026-10-08T03:41:00+07:00'),
      ).domain;

      expect(unread.isRead, isFalse);
      expect(read.isRead, isTrue);
      expect(unread.toMap().containsKey('read_at'), isTrue);
    });

    test('preserves an unknown subject type for a generic safe tile', () {
      final notification = NotificationDto.fromJson(
        fixtureNotificationJson(subjectType: 'future_subject'),
      ).domain;

      expect(notification.subjectType.isSupported, isFalse);
      expect(notification.rawSubjectType, 'future_subject');
    });

    test('rejects omitted nullable read_at key', () {
      final json = fixtureNotificationJson()..remove('read_at');

      expect(
        () => NotificationDto.fromJson(json),
        throwsA(isA<UnsupportedDataException>()),
      );
    });

    test('query and page values are immutable and value comparable', () {
      final query = NotificationQuery(filter: NotificationFilter.unread);
      expect(query, NotificationQuery(filter: NotificationFilter.unread));

      final page = NotificationPage(
        items: [NotificationDto.fromJson(fixtureNotificationJson()).domain],
        nextCursor: null,
        unreadCount: 1,
        asOf: null,
      );
      expect(() => page.items.add(page.items.single), throwsUnsupportedError);
      expect(
        () => NotificationPage(
          items: const [],
          nextCursor: null,
          unreadCount: -1,
          asOf: null,
        ),
        throwsA(isA<UnsupportedDataException>()),
      );
    });
  });
}
