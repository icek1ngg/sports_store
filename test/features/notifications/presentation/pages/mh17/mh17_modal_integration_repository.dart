import '../../widgets/mh17/notification_context_test_providers.dart';

import 'package:sports_store/features/notifications/data/models/notification_dto.dart';
import 'package:sports_store/features/notifications/domain/models/notification_item.dart';
import 'package:sports_store/features/notifications/domain/repositories/notification_repository.dart';

import '../../../../../fixtures/order_notification_fixtures.dart';

export '../../widgets/mh17/notification_context_test_providers.dart';

export 'package:sports_store/features/notifications/presentation/pages/notifications_page.dart';
export 'package:sports_store/features/notifications/presentation/widgets/notification_tile.dart';
export 'package:sports_store/core/state/read_retry_policy.dart';

NotificationItem contextPageRow(
  SessionScope scope,
  String label, {
  bool read = true,
}) => NotificationDto.fromJson({
  ...fixtureNotificationJson(subjectType: 'notification_only'),
  'recipient_id': scope.userId,
  'subject_id': fixtureEventId,
  'read_at': read ? '2026-10-22T01:00:00Z' : null,
  'title': 'Thông báo riêng $label',
  'body': 'Nội dung riêng $label',
}).domain;
NotificationPage contextPage(
  SessionScope scope,
  String label, {
  bool read = true,
  bool empty = false,
}) => NotificationPage(
  items: empty ? const [] : [contextPageRow(scope, label, read: read)],
  nextCursor: null,
  unreadCount: null,
  asOf: DateTime.utc(2026, 10, 22),
);

class ModalPageRepository implements NotificationRepository {
  ModalPageRepository(this.liveScope);
  final SessionScope Function() liveScope;
  Future<NotificationPage> Function(NotificationQuery)? pageHandler;
  Future<int> Function()? countHandler;
  bool denyList = false, denyCount = false, read = true;
  String label = 'A';
  int pageCalls = 0, countCalls = 0, markCalls = 0;
  @override
  Future<NotificationPage> getPage(NotificationQuery query) async {
    pageCalls++;
    if (denyList) {
      throw const AppFailure(code: AppFailure.forbiddenOrUnavailable);
    }
    return pageHandler?.call(query) ??
        contextPage(
          liveScope(),
          label,
          read: read,
          empty: query.filter == NotificationFilter.unread && read,
        );
  }

  @override
  Future<int> getUnreadCount() async {
    countCalls++;
    if (denyCount) {
      throw const AppFailure(code: AppFailure.forbiddenOrUnavailable);
    }
    return countHandler?.call() ?? 41;
  }

  @override
  Future<NotificationItem> markRead(String id) async {
    markCalls++;
    read = true;
    return contextPageRow(liveScope(), label);
  }
}
