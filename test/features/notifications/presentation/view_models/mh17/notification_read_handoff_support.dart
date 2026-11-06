import 'package:sports_store/features/notifications/presentation/view_models/mh17/notification_page_session_bridge.dart';

import 'read_coordinator_test_support.dart';
export 'read_coordinator_test_support.dart';

/// Explicit namespace handoff owner; no callback preemptively resets its rows.
class HandoffRig {
  HandoffRig() {
    bridge = NotificationPageSessionBridge(
      onNamespaceChanged: () {},
      onResourceInvalidated: (_) {},
    );
    reads = NotificationPageReadCoordinator(session: bridge);
  }
  late final NotificationPageSessionBridge bridge;
  late final NotificationPageReadCoordinator reads;
  SessionScope scope = readOwner;
  EpochCache cache = EpochCache(readOwner);
  final retiredCaches = <EpochCache>[];
  final pages = <NotificationQuery, ReadSnapshot<NotificationPage>>{};
  ReadSnapshot<int>? count;
  int refreshes = 0, invalidations = 0;
  NotificationReadNamespace get live =>
      (scope: scope, cache: cache, lease: bridge.captureLease(scope, cache));
  NotificationReadPorts get ports => (
    current: () => live,
    page: (query) => pages[query],
    count: () => count,
    refreshPage: (_) async {
      refreshes++;
    },
    refreshCount: () async {
      refreshes++;
    },
    invalidateInteractions: () => invalidations++,
  );
  NotificationQuery get query =>
      NotificationQuery(filter: reads.filter, cursor: reads.cursor);
  NotificationReadIntent get head => reads.headIntent(live)!;
  ReadSnapshot<NotificationPage> put(
    NotificationQuery query,
    NotificationPage page,
  ) {
    cache.accept(
      cache.begin(NotificationSnapshotProjection.resourceKey(query)),
      page,
    );
    return pages[query] = ReadSnapshot(data: page);
  }

  bool accept(NotificationReadIntent intent, NotificationPage page) {
    final query = NotificationQuery(
      filter: reads.filter,
      cursor: intent.cursor,
    );
    return reads.acceptPage(intent, query, put(query, page), ports);
  }

  void putCount(int value) {
    cache.accept(cache.begin('notifications/count'), value);
    count = ReadSnapshot(data: value);
  }

  bool observeCount() => reads.observeCount(live, count!, ports);
  void replaceCache({bool disposeOld = true}) {
    retiredCaches.add(cache);
    if (disposeOld) cache.dispose();
    cache = EpochCache(scope);
    pages.clear();
    count = null;
  }

  bool handoff({NotificationQuery? previousQuery}) {
    final submitted = previousQuery ?? query;
    replaceCache();
    return reads.synchronize(
      live,
      preserveSameOwnerStaleDisplay: true,
      query: submitted,
    );
  }

  void seed() {
    expect(accept(head, readPage(1)), true);
    putCount(1207);
    expect(reads.canInteract(ports, query), true);
  }

  void dispose() {
    reads.dispose();
    bridge.dispose();
    cache.dispose();
    for (final cache in retiredCaches) {
      cache.dispose();
    }
  }
}
