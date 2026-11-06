import 'read_coordinator_test_support.dart';

void main() {
  late ReadRig rig;
  setUp(() => rig = ReadRig());
  tearDown(() => rig.dispose());

  void deny([String code = AppFailure.unauthenticated]) {
    final snapshot = rig.countSnapshot = ReadSnapshot<int>(
      failure: AppFailure(code: code),
    );
    rig.coordinator.observeCount(rig.namespace, snapshot, rig.ports);
  }

  Future<void> recover() async {
    rig.onPageRefresh = (query) {
      rig.put(query, readPage(2));
      return Future.value();
    };
    rig.onCountRefresh = () {
      rig.putCount(7);
      return Future.value();
    };
    await rig.coordinator.refresh(rig.ports);
  }

  test(
    'reset and lease renewal cannot adopt cached rows until explicit recovery',
    () async {
      deny();
      rig.put(rig.coordinator.headQuery, readPage(1));
      rig.putCount(7);
      rig.coordinator.reset();
      rig.session.revokeAccess();
      final ticket = rig.head();
      expect(rig.accept(ticket, readPage(1)), false);
      expect(rig.coordinator.accessFailure, isNotNull);
      expect(rig.coordinator.items, isEmpty);
      await recover();
      expect(rig.coordinator.accessFailure, isNull);
      expect(rig.coordinator.items.single.title, 'Thông báo 2');
    },
  );

  for (final kind in ['account', 'generation', 'cache']) {
    test('actual $kind replacement clears previous owner denial receipt', () {
      deny();
      final oldCache = rig.cache;
      rig.scope = switch (kind) {
        'account' => const SessionScope(
          userId: '30000000-0000-4000-8000-000000000002',
          role: 'customer',
          generation: 1,
        ),
        'generation' => const SessionScope(
          userId: '30000000-0000-4000-8000-000000000001',
          role: 'customer',
          generation: 2,
        ),
        _ => rig.scope,
      };
      rig.cache = EpochCache(rig.scope);
      rig.coordinator.synchronize(rig.namespace);
      expect(rig.coordinator.accessFailure, isNull);
      expect(rig.coordinator.items, isEmpty);
      oldCache.dispose();
    });
  }

  test(
    'new denial reason is observed while same-owner latch remains idempotent',
    () {
      deny();
      final revision = rig.coordinator.revision;
      deny(AppFailure.forbiddenOrUnavailable);
      expect(
        rig.coordinator.accessFailure!.code,
        AppFailure.forbiddenOrUnavailable,
      );
      expect(rig.coordinator.revision, revision);
      expect(rig.invalidations, 1);
    },
  );

  test('new denial after legitimate recovery invalidates once again', () async {
    deny();
    await recover();
    expect(rig.coordinator.accessFailure, isNull);
    final revision = rig.coordinator.revision;
    deny(AppFailure.forbiddenOrUnavailable);
    expect(rig.coordinator.revision, greaterThan(revision));
    expect(rig.invalidations, 2);
    expect(rig.coordinator.items, isEmpty);
  });

  test('scope and cache mismatch does not erase a same-owner denial', () {
    deny();
    final mismatched = (
      scope: const SessionScope.unresolved(),
      cache: rig.cache,
      lease: rig.namespace.lease,
    );
    expect(rig.coordinator.synchronize(mismatched), false);
    expect(rig.coordinator.accessFailure, isNotNull);
    expect(rig.coordinator.synchronize(rig.namespace), true);
    expect(rig.coordinator.accessFailure, isNotNull);
  });

  for (final lease in [null, Object()]) {
    test(
      'unvalidated readable namespace cannot erase denial with lease $lease',
      () {
        deny();
        const other = SessionScope(
          userId: '30000000-0000-4000-8000-000000000002',
          role: 'customer',
          generation: 1,
        );
        final cache = EpochCache(other);
        expect(
          rig.coordinator.synchronize((
            scope: other,
            cache: cache,
            lease: lease,
          )),
          false,
        );
        expect(rig.coordinator.synchronize(rig.namespace), true);
        expect(rig.coordinator.accessFailure, isNotNull);
        cache.dispose();
      },
    );
  }

  test('logout revokes private feed and intents without clearing unvalidated denial receipt', () {
    final ticket = rig.head();
    deny();
    final oldCache = rig.cache;
    rig.scope = const SessionScope.unresolved();
    rig.cache = EpochCache(rig.scope);
    expect(rig.coordinator.synchronize(rig.namespace), false);
    expect(rig.coordinator.items, isEmpty);
    expect(rig.coordinator.nextCursor, isNull);
    expect(
      rig.coordinator.acceptPage(
        ticket,
        rig.coordinator.headQuery,
        const ReadSnapshot(),
        rig.ports,
      ),
      false,
    );
    expect(rig.pageReads, 0);
    expect(rig.coordinator.accessFailure, isNotNull);
    oldCache.dispose();
  });
}
