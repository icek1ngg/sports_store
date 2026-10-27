import 'notification_read_handoff_support.dart';

void main() {
  late HandoffRig rig;
  setUp(() => rig = HandoffRig());
  tearDown(() => rig.dispose());

  test('default cache replacement clears display without callback reset', () {
    rig.seed();
    rig.replaceCache();
    expect(rig.reads.synchronize(rig.live), true);
    expect(rig.reads.items, isEmpty);
    expect(rig.reads.nextCursor, isNull);
  });

  test(
    'opt-in transfers display only and clears all pagination eligibility',
    () {
      rig.seed();
      final accepted = rig.reads.items.single;
      final revision = rig.reads.revision;
      expect(rig.handoff(), true);
      expect(rig.reads.revision, greaterThan(revision));
      expect(rig.reads.items, [accepted]);
      expect(() => rig.reads.items.clear(), throwsUnsupportedError);
      expect(rig.reads.cursor, isNull);
      expect(rig.reads.nextCursor, isNull);
      expect(rig.reads.isLoadingMore, false);
      expect(rig.reads.needsLoadMoreRetry, false);
      expect(rig.reads.canInteract(rig.ports, rig.query), false);
      expect(rig.reads.beginLoadMore(rig.ports, rig.query), isNull);
      expect(
        rig.reads.beginLoadMore(rig.ports, rig.query, retry: true),
        isNull,
      );
      expect(accepted.readAt, isNull);
      expect(rig.count, isNull);
      expect(rig.refreshes, 0);
    },
  );

  for (final countFirst in [false, true]) {
    test(
      'fresh new head AND observed count recover, countFirst=$countFirst',
      () {
        rig.seed();
        rig.handoff();
        if (countFirst) {
          rig.putCount(501);
          expect(rig.observeCount(), true);
          expect(rig.reads.canInteract(rig.ports, rig.query), false);
        }
        expect(rig.accept(rig.head, readPage(2)), true);
        if (!countFirst) {
          rig.putCount(501);
          // Presence in the new cache alone is not a count observation receipt.
          expect(rig.reads.canInteract(rig.ports, rig.query), false);
          expect(rig.observeCount(), true);
        }
        expect(rig.reads.canInteract(rig.ports, rig.query), true);
        expect(rig.reads.items, rig.pages[rig.query]!.data!.items);
        expect(rig.count!.data, 501);
        expect(rig.reads.items.single.readAt, isNull);
        expect(rig.reads.beginLoadMore(rig.ports, rig.query), isNotNull);
      },
    );
  }

  test('stale or unbacked count cannot recover handoff actions', () {
    rig.seed();
    rig.handoff();
    rig.accept(rig.head, readPage(2));
    rig.count = const ReadSnapshot(data: 10);
    expect(rig.observeCount(), false);
    expect(rig.reads.canInteract(rig.ports, rig.query), false);
    rig.putCount(10);
    rig.cache.invalidate('notifications/count');
    expect(rig.observeCount(), true);
    expect(rig.reads.canInteract(rig.ports, rig.query), false);
    rig.putCount(10);
    rig.count = const ReadSnapshot(data: 10, stale: true);
    expect(rig.observeCount(), true);
    expect(rig.reads.canInteract(rig.ports, rig.query), false);
    rig.putCount(10);
    rig.observeCount();
    expect(rig.reads.canInteract(rig.ports, rig.query), true);
  });

  test('old head, old count and tail cannot overwrite handoff namespace', () {
    rig.seed();
    final oldHead = rig.head;
    final oldNamespace = rig.live;
    final oldCount = rig.count!;
    final tail = rig.reads.beginLoadMore(rig.ports, rig.query)!;
    final tailQuery = rig.query;
    final tailSnapshot = rig.put(tailQuery, readPage(3));
    expect(rig.handoff(previousQuery: tailQuery), true);
    expect(rig.reads.items.single.title, 'Thông báo 1');
    expect(
      rig.reads.acceptPage(tail, tailQuery, tailSnapshot, rig.ports),
      false,
    );
    expect(rig.reads.observeCount(oldNamespace, oldCount, rig.ports), false);
    expect(rig.accept(oldHead, readPage(4)), false);
    expect(rig.reads.items.single.title, 'Thông báo 1');
    expect(rig.reads.nextCursor, isNull);
    expect(rig.reads.canInteract(rig.ports, rig.query), false);
  });

  test('failed tail retry intent does not survive handoff', () {
    rig.seed();
    final tail = rig.reads.beginLoadMore(rig.ports, rig.query)!;
    final query = rig.query;
    final error = rig.pages[query] = const ReadSnapshot<NotificationPage>(
      failure: AppFailure(code: AppFailure.network),
    );
    expect(rig.reads.acceptPage(tail, query, error, rig.ports), false);
    expect(rig.reads.needsLoadMoreRetry, true);
    expect(rig.handoff(previousQuery: query), true);
    expect(rig.reads.needsLoadMoreRetry, false);
    expect(rig.reads.beginLoadMore(rig.ports, rig.query, retry: true), isNull);
  });

  test('handoff cancels deferred invalid request cursor recovery', () async {
    rig.seed();
    final tail = rig.reads.beginLoadMore(rig.ports, rig.query)!;
    final query = rig.query;
    final error = rig.pages[query] = const ReadSnapshot<NotificationPage>(
      failure: AppFailure(code: AppFailure.invalidCursor),
    );
    rig.reads.acceptPage(tail, query, error, rig.ports);
    expect(rig.handoff(previousQuery: query), true);
    await Future<void>.value();
    expect(rig.refreshes, 0);
    expect(rig.reads.items.single.title, 'Thông báo 1');
    expect(rig.reads.nextCursor, isNull);
  });

  test('stable namespace opt-in is idempotent and does not rearm', () {
    rig.seed();
    final revision = rig.reads.revision;
    expect(
      rig.reads.synchronize(
        rig.live,
        preserveSameOwnerStaleDisplay: true,
        query: rig.query,
      ),
      true,
    );
    expect(rig.reads.revision, revision);
    expect(rig.reads.canInteract(rig.ports, rig.query), true);
  });

  test('second handoff discards the first handoff recovery receipt', () {
    rig.seed();
    rig.handoff();
    rig.putCount(10);
    rig.observeCount();
    final oldHead = rig.head;
    rig.handoff();
    expect(rig.accept(oldHead, readPage(3)), false);
    rig.accept(rig.head, readPage(2));
    rig.putCount(20);
    expect(rig.reads.canInteract(rig.ports, rig.query), false);
    rig.observeCount();
    expect(rig.reads.canInteract(rig.ports, rig.query), true);
  });

  test(
    'refresh requires a new observed count while handoff is pending',
    () async {
      rig.seed();
      rig.handoff();
      rig.putCount(10);
      rig.observeCount();
      await rig.reads.refresh(rig.ports);
      expect(rig.reads.canInteract(rig.ports, rig.query), false);
      rig.accept(rig.head, readPage(2));
      rig.observeCount();
      expect(rig.reads.canInteract(rig.ports, rig.query), true);
    },
  );

  test('explicit reset or filter change cannot resurrect handoff display', () {
    rig.seed();
    rig.handoff();
    final old = rig.head;
    rig.reads.setFilter(NotificationFilter.unread, rig.live);
    expect(rig.reads.items, isEmpty);
    expect(rig.accept(old, readPage(2)), false);
    rig.reads.reset();
    expect(rig.reads.items, isEmpty);
  });
}
