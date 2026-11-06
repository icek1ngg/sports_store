import 'read_coordinator_test_support.dart';

void main() {
  late ReadRig rig;
  setUp(() => rig = ReadRig());
  tearDown(() => rig.dispose());

  test('initial round is empty and stable across repeated head bindings', () {
    final ticket = rig.head();
    expect(ticket.revision, greaterThan(0));
    expect(rig.coordinator.items, isEmpty);
    expect(rig.coordinator.nextCursor, isNull);
    expect(rig.head(), ticket);
    expect(rig.pageReads, 0);
  });

  test('N01 arms revision before synchronous refresh publication', () async {
    rig.accept(rig.head(), readPage(1));
    final before = rig.coordinator.revision;
    rig.onPageRefresh = (query) {
      expect(rig.coordinator.revision, greaterThan(before));
      final ticket = rig.head();
      final snapshot = rig.put(query, readPage(2));
      expect(
        rig.coordinator.acceptPage(ticket, query, snapshot, rig.ports),
        true,
      );
      return Future.value();
    };
    rig.onCountRefresh = () {
      rig.putCount(401);
      return Future.value();
    };
    await rig.coordinator.refresh(rig.ports);
    expect(rig.coordinator.items.single.title, 'Thông báo 2');
    expect(rig.pageReads, 1);
    expect(rig.countReads, 1);
  });

  test('N04 cached canonical head may be adopted once per armed round', () {
    final ticket = rig.head();
    final snapshot = rig.put(rig.coordinator.headQuery, readPage(1));
    expect(
      rig.coordinator.acceptPage(
        ticket,
        rig.coordinator.headQuery,
        snapshot,
        rig.ports,
      ),
      true,
    );
    expect(
      rig.coordinator.acceptPage(
        ticket,
        rig.coordinator.headQuery,
        snapshot,
        rig.ports,
      ),
      false,
    );
    expect(rig.head().revision, ticket.revision);
    expect(rig.pageReads, 0);
  });

  test(
    'same-owner pending head refresh retains rows but disables actions',
    () async {
      rig.accept(rig.head(), readPage(1));
      final gate = Completer<void>();
      rig.onPageRefresh = (_) => gate.future;
      final pending = rig.coordinator.refresh(rig.ports);
      expect(rig.coordinator.items.single.title, 'Thông báo 1');
      expect(
        rig.coordinator.canInteract(rig.ports, rig.coordinator.headQuery),
        false,
      );
      rig.put(rig.coordinator.headQuery, readPage(2));
      gate.complete();
      await pending;
      expect(rig.coordinator.items.single.title, 'Thông báo 2');
    },
  );

  test('old head intent cannot publish into explicit newer revision', () async {
    final old = rig.head();
    final gate = Completer<void>();
    rig.onPageRefresh = (_) => gate.future;
    final pending = rig.coordinator.refresh(rig.ports);
    expect(rig.accept(old, readPage(1)), false);
    rig.put(rig.coordinator.headQuery, readPage(2));
    gate.complete();
    await pending;
    expect(rig.coordinator.items.single.title, 'Thông báo 2');
  });

  test('filter transition clears rows and rejects old-filter head', () {
    final old = rig.head();
    rig.accept(old, readPage(1));
    rig.coordinator.setFilter(NotificationFilter.unread, rig.namespace);
    expect(rig.coordinator.items, isEmpty);
    expect(rig.coordinator.cursor, isNull);
    final query = NotificationQuery();
    expect(
      rig.coordinator.acceptPage(
        old,
        query,
        rig.put(query, readPage(1)),
        rig.ports,
      ),
      false,
    );
    expect(rig.accept(rig.head(), readPage(2)), true);
  });

  test(
    'N05 invalidation before read Future completion coalesces head round',
    () async {
      rig.accept(rig.head(), readPage(1));
      final submitted = rig.coordinator.revision;
      final read = Completer<bool>();
      final completion = read.future.then(
        (ack) => rig.coordinator.afterCanonicalRead(ack, submitted, rig.ports),
      );
      final key = NotificationSnapshotProjection.resourceKey(
        rig.coordinator.headQuery,
      );
      rig.cache.invalidate(key);
      final armed = rig.coordinator.revision;
      rig.cache.invalidate(key);
      expect(rig.coordinator.revision, armed);
      expect(armed, greaterThan(submitted));
      expect(rig.accept(rig.head(), readPage(2, read: true)), true);
      read.complete(true);
      await completion;
      expect(rig.coordinator.revision, armed);
      expect(rig.coordinator.items.single.isRead, true);
      expect(rig.pageReads, 0);
    },
  );

  test('failed acknowledgement never arms a read round or changes readAt', () {
    rig.accept(rig.head(), readPage(1));
    final revision = rig.coordinator.revision;
    rig.coordinator.afterCanonicalRead(false, revision, rig.ports);
    expect(rig.coordinator.revision, revision);
    expect(rig.coordinator.items.single.readAt, isNull);
    expect(rig.pageReads, 0);
  });

  test(
    'already-read tail resets to cached head without extra backend read',
    () {
      rig.accept(rig.head(), readPage(1, read: true));
      final tail = rig.coordinator.beginLoadMore(
        rig.ports,
        rig.coordinator.headQuery,
      )!;
      rig.accept(tail, readPage(2));
      expect(rig.coordinator.items.length, 2);
      rig.coordinator.afterCanonicalRead(
        true,
        rig.coordinator.revision,
        rig.ports,
      );
      expect(rig.coordinator.items.single.title, 'Thông báo 1');
      expect(rig.coordinator.cursor, isNull);
      expect(rig.pageReads, 0);
      expect(rig.countReads, 0);
    },
  );

  test('self-refresh invalidation does not create a second round', () async {
    rig.accept(rig.head(), readPage(1));
    final before = rig.coordinator.revision;
    rig.onPageRefresh = (query) {
      rig.cache.invalidate(NotificationSnapshotProjection.resourceKey(query));
      rig.put(query, readPage(2));
      return Future.value();
    };
    await rig.coordinator.refresh(rig.ports);
    expect(rig.coordinator.revision, before + 1);
    expect(rig.coordinator.items.single.title, 'Thông báo 2');
  });

  test(
    'two consecutive head refreshes are deterministic and latest replaces tail',
    () async {
      var number = 1;
      rig.onPageRefresh = (query) {
        rig.put(query, readPage(number++));
        return Future.value();
      };
      await rig.coordinator.refresh(rig.ports);
      final first = rig.coordinator.revision;
      await rig.coordinator.refresh(rig.ports);
      expect(rig.coordinator.revision, first + 1);
      expect(rig.coordinator.items.single.title, 'Thông báo 2');
    },
  );
}
