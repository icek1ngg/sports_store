import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/state/epoch_cache.dart';
import '../../../../core/state/foundation_providers.dart';
import '../../../../core/state/session_scope.dart';
import '../../domain/models/notification_item.dart';

final notificationReadInvalidationProvider =
    Provider<NotificationReadInvalidation>(
      (ref) => NotificationReadInvalidation(ref.watch(epochCacheProvider)),
    );

/// Phase 1 acknowledgement hook. It does not send PATCH or infer read success.
class NotificationReadInvalidation {
  NotificationReadInvalidation(this.cache);
  final EpochCache cache;

  bool acknowledge(
    NotificationItem canonicalRow, {
    required String expectedNotificationId,
    required SessionScope submittedScope,
  }) {
    if (!cache.canRead ||
        cache.scope != submittedScope ||
        canonicalRow.recipientId != cache.scope.userId ||
        canonicalRow.id != expectedNotificationId ||
        !canonicalRow.isRead) {
      return false;
    }
    cache.invalidatePrefix('notifications/');
    return true;
  }
}
