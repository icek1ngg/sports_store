import 'dart:async';

import 'package:sports_store/core/state/epoch_cache.dart';
import 'package:sports_store/core/state/read_snapshot.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/notifications/domain/models/notification_item.dart';
import 'package:sports_store/features/notifications/domain/models/notification_page.dart';
import 'package:sports_store/features/notifications/domain/models/notification_query.dart';
import 'package:sports_store/features/notifications/presentation/view_models/mh17/notification_page_read_coordinator.dart';
import 'package:sports_store/features/notifications/presentation/view_models/mh17/notification_page_session_bridge.dart';
import 'package:sports_store/features/notifications/presentation/view_models/mh17/notification_snapshot_projection.dart';

export 'dart:async';

export 'package:flutter_test/flutter_test.dart';
export 'package:sports_store/core/errors/app_failure.dart';
export 'package:sports_store/core/state/epoch_cache.dart';
export 'package:sports_store/core/state/read_snapshot.dart';
export 'package:sports_store/core/state/session_scope.dart';
export 'package:sports_store/features/notifications/domain/models/notification_page.dart';
export 'package:sports_store/features/notifications/domain/models/notification_query.dart';
export 'package:sports_store/features/notifications/presentation/view_models/mh17/notification_page_read_coordinator.dart';
export 'package:sports_store/features/notifications/presentation/view_models/mh17/notification_snapshot_projection.dart';

const readOwner = SessionScope(
  userId: '30000000-0000-4000-8000-000000000001',
  role: 'customer',
  generation: 1,
);

NotificationPage readPage(
  int number, {
  String? cursor = 'next',
  bool read = false,
}) {
  final suffix = number.toString().padLeft(12, '0');
  final event = '20000000-0000-4000-8000-$suffix';
  return NotificationPage(
    items: [
      NotificationItem(
        id: '10000000-0000-4000-8000-$suffix',
        recipientId: readOwner.userId!,
        eventId: event,
        subjectType: NotificationSubjectType.notificationOnly,
        subjectId: event,
        title: 'Thông báo $number',
        body: 'Nội dung canonical',
        createdAt: DateTime.utc(2026, 10, 22, 1),
        readAt: read ? DateTime.utc(2026, 10, 22, 2) : null,
      ),
    ],
    nextCursor: cursor,
    unreadCount: 99,
    asOf: DateTime.utc(2026, 10, 22, 3),
  );
}

class ReadRig {
  ReadRig() {
    session = NotificationPageSessionBridge(
      onNamespaceChanged: () => coordinator.reset(),
      onResourceInvalidated: (key) {
        if (forwardResources) coordinator.onResourceInvalidated(key, ports);
      },
    );
    coordinator = NotificationPageReadCoordinator(session: session);
    namespace; // Establish the bridge before any read-round is requested.
  }
  late final NotificationPageSessionBridge session;
  late final NotificationPageReadCoordinator coordinator;
  SessionScope scope = readOwner;
  EpochCache cache = EpochCache(readOwner);
  final pages = <NotificationQuery, ReadSnapshot<NotificationPage>>{};
  ReadSnapshot<int>? countSnapshot;
  Future<void> Function(NotificationQuery)? onPageRefresh;
  Future<void> Function()? onCountRefresh;
  int pageReads = 0, countReads = 0, invalidations = 0, currentReads = 0;
  bool forwardResources = true;
  NotificationReadNamespace get namespace =>
      (scope: scope, cache: cache, lease: session.captureLease(scope, cache));
  NotificationReadPorts get ports => (
    current: () {
      currentReads++;
      return namespace;
    },
    page: (query) => pages[query],
    count: () => countSnapshot,
    refreshPage: (query) {
      pageReads++;
      return onPageRefresh?.call(query) ?? Future.value();
    },
    refreshCount: () {
      countReads++;
      return onCountRefresh?.call() ?? Future.value();
    },
    invalidateInteractions: () => invalidations++,
  );
  NotificationReadIntent head() => coordinator.headIntent(namespace)!;
  ReadSnapshot<NotificationPage> put(
    NotificationQuery query,
    NotificationPage page,
  ) {
    final key = NotificationSnapshotProjection.resourceKey(query);
    cache.accept(cache.begin(key), page);
    return pages[query] = ReadSnapshot(data: page);
  }

  bool accept(NotificationReadIntent ticket, NotificationPage page) {
    final query = NotificationQuery(
      filter: coordinator.filter,
      cursor: ticket.cursor,
    );
    return coordinator.acceptPage(ticket, query, put(query, page), ports);
  }

  void putCount(int count) {
    cache.accept(cache.begin('notifications/count'), count);
    countSnapshot = ReadSnapshot(data: count);
  }

  void dispose() {
    coordinator.dispose();
    session.dispose();
    cache.dispose();
  }
}
