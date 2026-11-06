import 'read_coordinator_test_support.dart';

void main() {
  late ReadRig rig;
  setUp(() => rig = ReadRig());
  tearDown(() => rig.dispose());

  test('head/tail stable merge replaces duplicate projection in place', () {
    rig.accept(rig.head(), readPage(1));
    final first = rig.coordinator.beginLoadMore(
      rig.ports,
      rig.coordinator.headQuery,
    )!;
    expect(first.cursor, 'next');
    expect(rig.accept(first, readPage(2, cursor: 'second')), true);
    final second = rig.coordinator.beginLoadMore(
      rig.ports,
      NotificationQuery(cursor: 'next'),
    )!;
    expect(rig.accept(second, readPage(1, read: true, cursor: null)), true);
    expect(rig.coordinator.items.map((i) => i.title), [
      'Thông báo 1',
      'Thông báo 2',
    ]);
    expect(rig.coordinator.items.first.isRead, true);
    expect(rig.coordinator.nextCursor, isNull);
    expect(rig.pageReads, 0); // Intents alone never issue canonical reads.
  });

  test('old tail cannot restore rows after head refresh', () async {
    rig.accept(rig.head(), readPage(1));
    final tail = rig.coordinator.beginLoadMore(
      rig.ports,
      rig.coordinator.headQuery,
    )!;
    rig.onPageRefresh = (query) {
      rig.put(query, readPage(3));
      return Future.value();
    };
    await rig.coordinator.refresh(rig.ports);
    expect(rig.accept(tail, readPage(2)), false);
    expect(rig.coordinator.items.single.title, 'Thông báo 3');
  });

  test('tail failure preserves rows and retry uses same cursor with newer requestId', () {
    rig.accept(rig.head(), readPage(1));
    final tail = rig.coordinator.beginLoadMore(
      rig.ports,
      rig.coordinator.headQuery,
    )!;
    final query = NotificationQuery(cursor: tail.cursor);
    final failure = rig.pages[query] = const ReadSnapshot(
      failure: AppFailure(code: AppFailure.network),
    );
    expect(rig.coordinator.acceptPage(tail, query, failure, rig.ports), false);
    expect(rig.coordinator.needsLoadMoreRetry, true);
    expect(rig.coordinator.isLoadingMore, false);
    expect(rig.coordinator.items.single.title, 'Thông báo 1');
    final retry = rig.coordinator.beginLoadMore(rig.ports, query, retry: true)!;
    expect(retry.cursor, tail.cursor);
    expect(retry.requestId, greaterThan(tail.requestId!));
    expect(rig.accept(tail, readPage(2)), false);
    expect(rig.accept(retry, readPage(2)), true);
  });

  test(
    'repeated cursor terminates through existing FeedCoordinator policy',
    () {
      rig.accept(rig.head(), readPage(1));
      final tail = rig.coordinator.beginLoadMore(
        rig.ports,
        rig.coordinator.headQuery,
      )!;
      rig.accept(tail, readPage(2, cursor: tail.cursor));
      expect(rig.coordinator.nextCursor, isNull);
      expect(
        rig.coordinator.beginLoadMore(
          rig.ports,
          NotificationQuery(cursor: tail.cursor),
        ),
        isNull,
      );
    },
  );

  test('stale head blocks tail request and tail acceptance', () {
    rig.accept(rig.head(), readPage(1));
    final tail = rig.coordinator.beginLoadMore(
      rig.ports,
      rig.coordinator.headQuery,
    )!;
    final key = NotificationSnapshotProjection.resourceKey(
      rig.coordinator.headQuery,
    );
    // No bridge signal here: stale is still checked at acceptance.
    rig.forwardResources = false;
    rig.cache.invalidate(key);
    expect(rig.accept(tail, readPage(2)), false);
    expect(rig.coordinator.items.single.title, 'Thông báo 1');
  });

  test(
    'raw empty cursor intent is preserved; normalized query cannot accept it',
    () {
      rig.accept(rig.head(), readPage(1, cursor: ''));
      final tail = rig.coordinator.beginLoadMore(
        rig.ports,
        rig.coordinator.headQuery,
      )!;
      expect(tail.cursor, '');
      final normalized = NotificationQuery(cursor: tail.cursor);
      expect(normalized.cursor, isNull); // Existing F02, not fixed here.
      expect(
        rig.coordinator.acceptPage(
          tail,
          normalized,
          rig.put(normalized, readPage(2)),
          rig.ports,
        ),
        false,
      );
      expect(rig.pageReads, 0);
    },
  );

  test(
    'raw oversized intent remains unmodified and domain query still rejects it',
    () {
      final raw = 'x' * 2049;
      rig.accept(rig.head(), readPage(1, cursor: raw));
      final tail = rig.coordinator.beginLoadMore(
        rig.ports,
        rig.coordinator.headQuery,
      )!;
      expect(tail.cursor, raw);
      expect(() => NotificationQuery(cursor: tail.cursor), throwsArgumentError);
      expect(rig.pageReads, 0);
    },
  );

  test('REGRESSION invalid_cursor recovery must wait until provider listener unwinds', () async {
    rig.accept(rig.head(), readPage(1));
    final tail = rig.coordinator.beginLoadMore(
      rig.ports,
      rig.coordinator.headQuery,
    )!;
    final query = NotificationQuery(cursor: tail.cursor);
    final failed = rig.pages[query] = const ReadSnapshot<NotificationPage>(
      failure: AppFailure(code: AppFailure.invalidCursor),
    );
    var insideListener = true;
    var reenteredListener = false;
    rig.onPageRefresh = (head) {
      reenteredListener = insideListener;
      rig.put(head, readPage(3));
      return Future.value();
    };
    rig.coordinator.acceptPage(tail, query, failed, rig.ports);
    insideListener = false;
    expect(reenteredListener, false);
    await Future<void>.delayed(Duration.zero);
    expect(rig.coordinator.cursor, isNull);
    expect(rig.coordinator.needsLoadMoreRetry, false);
  });
}
