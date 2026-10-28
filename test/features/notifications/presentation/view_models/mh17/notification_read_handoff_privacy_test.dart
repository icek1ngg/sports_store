import 'notification_read_handoff_support.dart';

import 'package:sports_store/features/notifications/domain/models/notification_item.dart';

void main() {
  late HandoffRig rig;
  setUp(() => rig = HandoffRig());
  tearDown(() => rig.dispose());

  for (final scope in [
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
    const SessionScope(
      userId: '30000000-0000-4000-8000-000000000001',
      role: 'manager',
      generation: 1,
    ),
    const SessionScope(
      userId: '30000000-0000-4000-8000-000000000001',
      role: 'unknown',
      generation: 1,
    ),
    const SessionScope(
      userId: '30000000-0000-4000-8000-000000000001',
      role: 'customer',
      generation: 1,
      roleResolved: false,
    ),
    const SessionScope.unresolved(),
  ]) {
    test(
      'opt-in clears incompatible owner ${scope.userId}/${scope.role}/${scope.generation}/${scope.roleResolved}',
      () {
        rig.seed();
        final query = rig.query;
        final oldHead = rig.head;
        rig.scope = scope;
        rig.replaceCache();
        expect(
          rig.reads.synchronize(
            rig.live,
            preserveSameOwnerStaleDisplay: true,
            query: query,
          ),
          false,
        );
        expect(rig.reads.items, isEmpty);
        expect(rig.reads.nextCursor, isNull);
        expect(rig.accept(oldHead, readPage(2)), false);
        expect(rig.reads.canInteract(rig.ports, query), false);
      },
    );
  }

  for (final query in <NotificationQuery?>[
    null,
    NotificationQuery(filter: NotificationFilter.unread),
    NotificationQuery(limit: 21),
    NotificationQuery(cursor: 'wrong-cursor'),
  ]) {
    test('missing/incompatible query clears display: $query', () {
      rig.seed();
      rig.replaceCache();
      expect(
        rig.reads.synchronize(
          rig.live,
          preserveSameOwnerStaleDisplay: true,
          query: query,
        ),
        false,
      );
      expect(rig.reads.items, isEmpty);
      expect(rig.reads.nextCursor, isNull);
      expect(rig.reads.canInteract(rig.ports, rig.query), false);
    });
  }

  test(
    'existing denial prevents opt-in retention across cache replacement',
    () {
      rig.seed();
      rig.count = const ReadSnapshot(
        failure: AppFailure(code: AppFailure.unauthenticated),
      );
      expect(rig.observeCount(), false);
      expect(rig.reads.accessFailure, isNotNull);
      final query = rig.query;
      rig.replaceCache();
      expect(
        rig.reads.synchronize(
          rig.live,
          preserveSameOwnerStaleDisplay: true,
          query: query,
        ),
        false,
      );
      expect(rig.reads.items, isEmpty);
      expect(rig.reads.accessFailure, isNotNull);
    },
  );

  test('lease-only rotation does not authorize display transfer', () {
    rig.seed();
    rig.bridge.revokeAccess();
    expect(
      rig.reads.synchronize(
        rig.live,
        preserveSameOwnerStaleDisplay: true,
        query: rig.query,
      ),
      true,
    );
    expect(rig.reads.items, isEmpty);
    expect(rig.reads.canInteract(rig.ports, rig.query), false);
  });

  test('invalid lease rejects handoff even with matching scope/cache', () {
    rig.seed();
    final query = rig.query;
    rig.replaceCache();
    final live = rig.live;
    final invalid = (scope: live.scope, cache: live.cache, lease: Object());
    expect(
      rig.reads.synchronize(
        invalid,
        preserveSameOwnerStaleDisplay: true,
        query: query,
      ),
      false,
    );
    expect(rig.reads.items, isEmpty);
  });

  test('foreign recipient cannot cross the explicit display handoff', () {
    final source = readPage(1).items.single;
    final foreign = NotificationItem(
      id: source.id,
      recipientId: '30000000-0000-4000-8000-000000000002',
      eventId: source.eventId,
      subjectType: source.subjectType,
      subjectId: source.subjectId,
      title: source.title,
      body: source.body,
      readAt: source.readAt,
      createdAt: source.createdAt,
    );
    // Simulate a caller that supplied an incorrectly authorized accepted page.
    // The new transfer must not trust that earlier authorization assumption.
    rig.accept(
      rig.head,
      NotificationPage(
        items: [foreign],
        nextCursor: null,
        unreadCount: 1,
        asOf: DateTime.utc(2026, 10, 22),
      ),
    );
    expect(rig.handoff(), false);
    expect(rig.reads.items, isEmpty);
  });

  for (final silent in [false, true]) {
    test(
      'same-object blocked/disposed cache clears handoff rows: silent=$silent',
      () {
        rig.seed();
        rig.handoff();
        if (silent) {
          rig.cache.dispose(); // No listener notification.
        } else {
          rig.cache.blockSession();
        }
        expect(rig.reads.canInteract(rig.ports, rig.query), false);
        expect(rig.reads.items, isEmpty);
        expect(rig.reads.nextCursor, isNull);
      },
    );
  }

  test('new blocked cache cannot receive opt-in display', () {
    rig.seed();
    final query = rig.query;
    rig.replaceCache();
    rig.cache.blockSession();
    expect(
      rig.reads.synchronize(
        rig.live,
        preserveSameOwnerStaleDisplay: true,
        query: query,
      ),
      false,
    );
    expect(rig.reads.items, isEmpty);
  });

  test('stale current-owner head retains display without granting actions', () {
    rig.seed();
    rig.handoff();
    rig.accept(rig.head, readPage(2));
    rig.putCount(10);
    rig.observeCount();
    rig.cache.invalidate(NotificationSnapshotProjection.resourceKey(rig.query));
    expect(rig.reads.items.single.title, 'Thông báo 2');
    expect(rig.reads.canInteract(rig.ports, rig.query), false);
    expect(rig.reads.beginLoadMore(rig.ports, rig.query), isNull);
  });

  test('count getter owner switch fails closed before publishing action', () {
    rig.seed();
    rig.handoff();
    rig.accept(rig.head, readPage(2));
    rig.putCount(10);
    rig.observeCount();
    final original = rig.ports;
    final racing = (
      current: original.current,
      page: original.page,
      count: () {
        final oldCount = rig.count;
        rig.scope = const SessionScope.unresolved();
        rig.replaceCache();
        return oldCount;
      },
      refreshPage: original.refreshPage,
      refreshCount: original.refreshCount,
      invalidateInteractions: original.invalidateInteractions,
    );
    expect(rig.reads.canInteract(racing, rig.query), false);
    expect(rig.reads.items, isEmpty);
  });

  test('disposal clears retained display and rejects old callbacks', () {
    rig.seed();
    rig.handoff();
    final head = rig.head;
    rig.reads.dispose();
    expect(rig.reads.items, isEmpty);
    expect(rig.accept(head, readPage(2)), false);
    expect(rig.reads.canInteract(rig.ports, rig.query), false);
    expect(
      rig.reads.synchronize(
        rig.live,
        preserveSameOwnerStaleDisplay: true,
        query: rig.query,
      ),
      false,
    );
  });

  test('existing synchronous reset callback remains authoritative', () {
    final original = ReadRig();
    try {
      original.accept(original.head(), readPage(1));
      final oldCache = original.cache;
      original.cache = EpochCache(original.scope);
      final live = original.namespace; // Bridge signals reset before opt-in.
      expect(
        original.coordinator.synchronize(
          live,
          preserveSameOwnerStaleDisplay: true,
          query: original.coordinator.headQuery,
        ),
        false,
      );
      expect(original.coordinator.items, isEmpty);
      oldCache.dispose();
    } finally {
      original.dispose();
    }
  });
}
