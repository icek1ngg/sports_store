import 'read_coordinator_test_support.dart';

void main() {
  late ReadRig rig;
  setUp(() => rig = ReadRig());
  tearDown(() => rig.dispose());

  ({
    NotificationReadIntent intent,
    NotificationQuery query,
    ReadSnapshot<NotificationPage> failed,
  })
  stage() {
    rig.accept(rig.head(), readPage(1));
    final intent = rig.coordinator.beginLoadMore(
      rig.ports,
      rig.coordinator.headQuery,
    )!;
    final query = NotificationQuery(cursor: intent.cursor);
    final failed = rig.pages[query] = const ReadSnapshot<NotificationPage>(
      failure: AppFailure(code: AppFailure.invalidCursor),
    );
    rig.onPageRefresh = (head) {
      rig.put(head, readPage(3));
      return Future.value();
    };
    return (intent: intent, query: query, failed: failed);
  }

  test(
    'duplicate invalid cursor events schedule exactly one head refresh',
    () async {
      final event = stage();
      rig.coordinator.acceptPage(
        event.intent,
        event.query,
        event.failed,
        rig.ports,
      );
      rig.coordinator.acceptPage(
        event.intent,
        event.query,
        event.failed,
        rig.ports,
      );
      expect(rig.pageReads, 0);
      await Future<void>.delayed(Duration.zero);
      expect(rig.pageReads, 1);
      expect(rig.countReads, 1);
      expect(rig.coordinator.items.single.title, 'Thông báo 3');
    },
  );

  for (final kind in [
    'dispose',
    'reset',
    'filter',
    'logout',
    'generation',
    'cache',
    'block',
    'network',
    'success',
    'denial',
  ]) {
    test(
      'scheduled recovery is rejected after $kind supersedes intent',
      () async {
        final event = stage();
        rig.coordinator.acceptPage(
          event.intent,
          event.query,
          event.failed,
          rig.ports,
        );
        final oldCache = rig.cache;
        switch (kind) {
          case 'dispose':
            rig.coordinator.dispose();
          case 'reset':
            rig.coordinator.reset();
          case 'filter':
            rig.coordinator.setFilter(NotificationFilter.unread, rig.namespace);
          case 'logout':
            rig.scope = const SessionScope.unresolved();
          case 'generation':
            rig.scope = const SessionScope(
              userId: '30000000-0000-4000-8000-000000000001',
              role: 'customer',
              generation: 2,
            );
          case 'cache':
            rig.cache = EpochCache(rig.scope);
          case 'block':
            rig.cache.blockSession();
          case 'network':
            rig.pages[event.query] = const ReadSnapshot(
              failure: AppFailure(code: AppFailure.network),
            );
          case 'success':
            rig.put(event.query, readPage(2));
          case 'denial':
            final denied = rig.countSnapshot = const ReadSnapshot<int>(
              failure: AppFailure(code: AppFailure.unauthenticated),
            );
            rig.coordinator.observeCount(rig.namespace, denied, rig.ports);
        }
        await Future<void>.delayed(Duration.zero);
        expect(rig.pageReads, 0);
        expect(rig.countReads, 0);
        if (!identical(oldCache, rig.cache)) oldCache.dispose();
      },
    );
  }

  test(
    'old retry ticket cannot overwrite a newer scheduled recovery',
    () async {
      final event = stage();
      rig.coordinator.acceptPage(
        event.intent,
        event.query,
        event.failed,
        rig.ports,
      );
      final network = rig.pages[event.query] =
          const ReadSnapshot<NotificationPage>(
            failure: AppFailure(code: AppFailure.network),
          );
      rig.coordinator.acceptPage(event.intent, event.query, network, rig.ports);
      final retry = rig.coordinator.beginLoadMore(
        rig.ports,
        event.query,
        retry: true,
      )!;
      final current = rig.pages[event.query] =
          const ReadSnapshot<NotificationPage>(
            failure: AppFailure(code: AppFailure.invalidCursor),
          );
      rig.coordinator.acceptPage(retry, event.query, current, rig.ports);
      expect(
        rig.coordinator.acceptPage(
          event.intent,
          event.query,
          event.failed,
          rig.ports,
        ),
        false,
      );
      await Future<void>.delayed(Duration.zero);
      expect(rig.pageReads, 1);
      expect(rig.countReads, 1);
    },
  );

  test(
    'rejected duplicate load-more attempt does not obsolete the active request',
    () async {
      final event = stage();
      expect(rig.coordinator.beginLoadMore(rig.ports, event.query), isNull);
      rig.coordinator.acceptPage(
        event.intent,
        event.query,
        event.failed,
        rig.ports,
      );
      await Future<void>.delayed(Duration.zero);
      expect(rig.pageReads, 1);
    },
  );

  test('current accepted tail still recovers background invalid_cursor without retry', () async {
    final event = stage();
    expect(rig.accept(event.intent, readPage(2)), true);
    expect(rig.coordinator.isLoadingMore, false);
    rig.pages[event.query] = event.failed;
    rig.coordinator.acceptPage(
      event.intent,
      event.query,
      event.failed,
      rig.ports,
    );
    expect(rig.pageReads, 0);
    await Future<void>.delayed(Duration.zero);
    expect(rig.pageReads, 1);
    expect(rig.coordinator.needsLoadMoreRetry, false);
  });

  test('explicit newer head refresh cancels queued recovery instead of duplicating IO', () async {
    final event = stage();
    rig.coordinator.acceptPage(
      event.intent,
      event.query,
      event.failed,
      rig.ports,
    );
    await rig.coordinator.refresh(rig.ports);
    await Future<void>.delayed(Duration.zero);
    expect(rig.pageReads, 1);
    expect(rig.countReads, 1);
  });
}
