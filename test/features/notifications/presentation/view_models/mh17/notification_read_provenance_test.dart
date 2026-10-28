import 'read_coordinator_test_support.dart';

void main() {
  late ReadRig rig;
  setUp(() => rig = ReadRig());
  tearDown(() => rig.dispose());

  for (final next in [
    const SessionScope(
      userId: '30000000-0000-4000-8000-000000000002',
      role: 'customer',
      generation: 1,
    ),
    const SessionScope(
      userId: '30000000-0000-4000-8000-000000000001',
      role: 'customer',
      generation: 2,
    ),
    const SessionScope.unresolved(),
  ]) {
    test(
      'owner transition clears accepted rows and rejects old head: ${next.userId}/${next.generation}',
      () {
        final old = rig.head();
        rig.accept(old, readPage(1));
        final oldCache = rig.cache;
        rig.scope = next;
        rig.cache = EpochCache(next);
        rig.namespace; // Synchronous SessionBridge signal clears the coordinator.
        expect(rig.coordinator.items, isEmpty);
        expect(rig.coordinator.nextCursor, isNull);
        expect(rig.accept(old, readPage(2)), false);
        oldCache.dispose();
      },
    );
  }

  test('same-scope cache replacement rejects old receipt and revision', () {
    final old = rig.head();
    rig.accept(old, readPage(1));
    final oldCache = rig.cache;
    rig.cache = EpochCache(rig.scope);
    rig.namespace;
    expect(rig.coordinator.items, isEmpty);
    expect(rig.accept(old, readPage(2)), false);
    oldCache.dispose();
  });

  test(
    'same-object blocked cache clears feed even without notification callback',
    () {
      rig.accept(rig.head(), readPage(1));
      // Detach bridge listener from cache: explicit live preflight must still work.
      rig.cache.dispose();
      expect(
        rig.coordinator.canInteract(rig.ports, rig.coordinator.headQuery),
        false,
      );
      expect(rig.coordinator.items, isEmpty);
      expect(rig.coordinator.nextCursor, isNull);
    },
  );

  test(
    'same-object session block synchronously rejects old head and clears rows',
    () {
      final old = rig.head();
      rig.accept(old, readPage(1));
      rig.cache.blockSession();
      expect(rig.coordinator.items, isEmpty);
      expect(
        rig.coordinator.acceptPage(
          old,
          rig.coordinator.headQuery,
          ReadSnapshot(data: readPage(2)),
          rig.ports,
        ),
        false,
      );
    },
  );

  test(
    'matching revision cannot substitute provider/cache snapshot provenance',
    () {
      final ticket = rig.head();
      final old = rig.put(rig.coordinator.headQuery, readPage(1));
      rig.put(rig.coordinator.headQuery, readPage(2));
      expect(
        rig.coordinator.acceptPage(
          ticket,
          rig.coordinator.headQuery,
          old,
          rig.ports,
        ),
        false,
      );
      rig.pages[rig.coordinator.headQuery] = old;
      expect(
        rig.coordinator.acceptPage(
          ticket,
          rig.coordinator.headQuery,
          old,
          rig.ports,
        ),
        false,
      );
      expect(rig.coordinator.items, isEmpty);
    },
  );

  test('current stale snapshot cannot be accepted or enable actions', () {
    final ticket = rig.head();
    final page = readPage(1);
    rig.put(rig.coordinator.headQuery, page);
    final stale = rig.pages[rig.coordinator.headQuery] = ReadSnapshot(
      data: page,
      stale: true,
    );
    expect(
      rig.coordinator.acceptPage(
        ticket,
        rig.coordinator.headQuery,
        stale,
        rig.ports,
      ),
      false,
    );
    expect(
      rig.coordinator.canInteract(rig.ports, rig.coordinator.headQuery),
      false,
    );
  });

  test('cache invalidation retains same-owner display but disables action preflight', () {
    rig.accept(rig.head(), readPage(1));
    rig.cache.invalidate(
      NotificationSnapshotProjection.resourceKey(rig.coordinator.headQuery),
    );
    expect(rig.coordinator.items.single.title, 'Thông báo 1');
    expect(
      rig.coordinator.canInteract(rig.ports, rig.coordinator.headQuery),
      false,
    );
  });

  test('unread count remains exact independent canonical foundation data', () {
    rig.accept(rig.head(), readPage(1));
    rig.putCount(1207);
    expect(
      rig.coordinator.observeCount(
        rig.namespace,
        rig.countSnapshot!,
        rig.ports,
      ),
      true,
    );
    expect(rig.countSnapshot!.data, 1207);
    expect(rig.coordinator.items.length, 1);
    expect(rig.coordinator.items.single.readAt, isNull);
  });

  test('old count response cannot deny or publish into a new cache owner', () {
    final old = rig.namespace;
    final oldCount = ReadSnapshot<int>(
      failure: AppFailure(code: AppFailure.unauthenticated),
    );
    final oldCache = rig.cache;
    rig.cache = EpochCache(rig.scope);
    rig.putCount(9);
    expect(rig.coordinator.observeCount(old, oldCount, rig.ports), false);
    expect(rig.coordinator.accessFailure, isNull);
    expect(rig.invalidations, 0);
    oldCache.dispose();
  });

  test('count access denial clears feed and invalidates interactions once per observed denial', () {
    rig.accept(rig.head(), readPage(1));
    final ns = rig.namespace;
    final denied = rig.countSnapshot = const ReadSnapshot(
      failure: AppFailure(code: AppFailure.forbiddenOrUnavailable),
    );
    expect(rig.coordinator.observeCount(ns, denied, rig.ports), false);
    expect(rig.coordinator.items, isEmpty);
    expect(
      rig.coordinator.accessFailure!.code,
      AppFailure.forbiddenOrUnavailable,
    );
    expect(rig.invalidations, 1);
    expect(
      rig.coordinator.canInteract(rig.ports, rig.coordinator.headQuery),
      false,
    );
  });

  test('denial recovery requires explicit refresh with both canonical fresh resources', () async {
    rig.accept(rig.head(), readPage(1));
    final denied = rig.countSnapshot = const ReadSnapshot<int>(
      failure: AppFailure(code: AppFailure.unauthenticated),
    );
    rig.coordinator.observeCount(rig.namespace, denied, rig.ports);
    rig.onPageRefresh = (query) {
      rig.put(query, readPage(2));
      return Future.value();
    };
    await rig.coordinator.refresh(rig.ports);
    expect(rig.coordinator.accessFailure, isNotNull);
    expect(rig.coordinator.items, isEmpty);
    rig.onCountRefresh = () {
      rig.putCount(4);
      return Future.value();
    };
    await rig.coordinator.refresh(rig.ports);
    expect(rig.coordinator.accessFailure, isNull);
    expect(rig.coordinator.items.single.title, 'Thông báo 2');
  });

  test(
    'disposed owner ignores late completion and never calls live ports again',
    () async {
      final gate = Completer<void>();
      rig.onPageRefresh = (_) => gate.future;
      final pending = rig.coordinator.refresh(rig.ports);
      rig.coordinator.dispose();
      final currentReads = rig.currentReads;
      final ticket = (
        namespace: rig.namespace,
        revision: 999,
        requestId: null,
        cursor: null,
      );
      expect(
        rig.coordinator.acceptPage(
          ticket,
          rig.coordinator.headQuery,
          const ReadSnapshot(),
          rig.ports,
        ),
        false,
      );
      gate.complete();
      await pending;
      expect(rig.currentReads, currentReads);
      expect(rig.coordinator.items, isEmpty);
      expect(rig.coordinator.nextCursor, isNull);
    },
  );

  test(
    'disposal during synchronous page refresh prevents count operation',
    () async {
      rig.onPageRefresh = (_) {
        rig.coordinator.dispose();
        return Future.value();
      };
      await rig.coordinator.refresh(rig.ports);
      expect(rig.pageReads, 1);
      expect(rig.countReads, 0);
    },
  );

  test(
    'REGRESSION lease-only rotation must retain the existing denial latch',
    () {
      rig.accept(rig.head(), readPage(1));
      final denied = rig.countSnapshot = const ReadSnapshot<int>(
        failure: AppFailure(code: AppFailure.unauthenticated),
      );
      rig.coordinator.observeCount(rig.namespace, denied, rig.ports);
      expect(rig.coordinator.accessFailure, isNotNull);
      rig.session.revokeAccess();
      rig.coordinator.synchronize(rig.namespace);
      expect(rig.coordinator.accessFailure, isNotNull);
      expect(
        rig.coordinator.canInteract(rig.ports, rig.coordinator.headQuery),
        false,
      );
    },
  );

  test(
    'REGRESSION repeating the same denial must not rearm or invalidate twice',
    () {
      final ns = rig.namespace;
      final denied = rig.countSnapshot = const ReadSnapshot<int>(
        failure: AppFailure(code: AppFailure.forbiddenOrUnavailable),
      );
      rig.coordinator.observeCount(ns, denied, rig.ports);
      final revision = rig.coordinator.revision;
      rig.coordinator.observeCount(ns, denied, rig.ports);
      expect(rig.coordinator.revision, revision);
      expect(rig.invalidations, 1);
    },
  );

  test(
    'fresh-shaped count backed by stale cache cannot recover access latch',
    () async {
      final denied = rig.countSnapshot = const ReadSnapshot<int>(
        failure: AppFailure(code: AppFailure.unauthenticated),
      );
      rig.coordinator.observeCount(rig.namespace, denied, rig.ports);
      rig.onPageRefresh = (query) {
        rig.put(query, readPage(2));
        return Future.value();
      };
      rig.onCountRefresh = () {
        rig.putCount(4);
        rig.cache.invalidate('notifications/count');
        return Future.value();
      };
      await rig.coordinator.refresh(rig.ports);
      expect(rig.coordinator.accessFailure, isNotNull);
      expect(rig.coordinator.items, isEmpty);
    },
  );
}
