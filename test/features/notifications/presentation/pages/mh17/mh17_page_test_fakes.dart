import 'dart:async';

import 'package:sports_store/features/notifications/domain/models/notification_item.dart';
import 'package:sports_store/features/notifications/domain/models/notification_page.dart';
import 'package:sports_store/features/notifications/domain/models/notification_query.dart';
import 'package:sports_store/features/notifications/domain/models/notification_target.dart';
import 'package:sports_store/features/notifications/domain/repositories/notification_repository.dart';

class PageNotifications implements NotificationRepository {
  final requests =
      <({NotificationQuery query, Completer<NotificationPage> result})>[];
  final countRequests = <Completer<int>>[];
  Future<NotificationItem> Function(String id)? markReadHandler;

  @override
  Future<NotificationPage> getPage(NotificationQuery query) {
    final result = Completer<NotificationPage>();
    requests.add((query: query, result: result));
    return result.future;
  }

  @override
  Future<int> getUnreadCount() {
    final result = Completer<int>();
    countRequests.add(result);
    return result.future;
  }

  @override
  Future<NotificationItem> markRead(String notificationId) {
    final handler = markReadHandler;
    if (handler == null) {
      return Future<NotificationItem>.error(
        StateError('not used in page tests'),
      );
    }
    return handler(notificationId);
  }
}

class PageTargetResolver implements NotificationTargetResolver {
  PageTargetResolver(this.decision);

  final NotificationTargetDecision decision;
  final calls = <String>[];

  @override
  Future<NotificationTargetDecision> resolve(String notificationId) async {
    calls.add(notificationId);
    return decision;
  }
}
