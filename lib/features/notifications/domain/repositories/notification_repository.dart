import '../models/notification_item.dart';
import '../models/notification_page.dart';
import '../models/notification_query.dart';
import '../models/notification_target.dart';

/// Recipient-scoped contract for OP-N01..OP-N04.  Implementations must derive
/// recipient_id from the authenticated session and must not accept it from a
/// screen or deep-link payload.
abstract interface class NotificationRepository {
  Future<NotificationPage> getPage(NotificationQuery query);

  Future<int> getUnreadCount();

  Future<NotificationItem> markRead(String notificationId);
}

/// Resolves a persisted notification after rechecking current target access.
/// A resolver must return [NotificationTargetDecision.unavailable] for a
/// revoked, malformed or unknown target rather than routing to cached PII.
abstract interface class NotificationTargetResolver {
  Future<NotificationTargetDecision> resolve(String notificationId);
}

extension NotificationRepositoryAliases on NotificationRepository {
  Future<NotificationPage> listNotifications(NotificationQuery query) =>
      getPage(query);

  Future<NotificationItem> markNotificationRead(String notificationId) =>
      markRead(notificationId);
}
