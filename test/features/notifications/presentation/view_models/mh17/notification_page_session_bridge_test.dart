import 'session_bridge_test_support.dart';

void main() {
  late ProviderContainer container;
  late BridgeProbe probe;
  late EpochCache cache;
  setUp(() {
    container = bridgeContainer();
    probe = BridgeProbe();
    cache = container.read(epochCacheProvider);
  });
  tearDown(() {
    container.read(epochCacheProvider).dispose();
    cache.dispose();
    container.dispose();
  });

  testWidgets('immediate attach signals before first harness render', (
    tester,
  ) async {
    probe.marker = 'old private marker';
    await tester.pumpWidget(bridgeHost(container, probe));
    expect(probe.events.first, 'namespace');
    expect(probe.events.last, 'render:empty');
    expect(find.text('old private marker'), findsNothing);
    expect(probe.bridge.captureLease(bridgeOwner, cache), isNotNull);
  });

  testWidgets('initial unresolved scope has no lease', (tester) async {
    container
        .read(controlledScope.notifier)
        .change(const SessionScope.unresolved());
    await tester.pumpWidget(bridgeHost(container, probe));
    expect(
      probe.bridge.captureLease(
        const SessionScope.unresolved(),
        container.read(epochCacheProvider),
      ),
      isNull,
    );
    expect(probe.events.last, 'render:empty');
  });

  testWidgets('stable scope and rebuild do not duplicate subscriptions', (
    tester,
  ) async {
    await tester.pumpWidget(bridgeHost(container, probe));
    final lease = probe.bridge.captureLease(bridgeOwner, cache);
    final changes = probe.changes;
    for (var i = 0; i < 3; i++) {
      await tester.pumpWidget(bridgeHost(container, probe));
    }
    container
        .read(controlledScope.notifier)
        .change(
          const SessionScope(
            userId: '30000000-0000-4000-8000-000000000001',
            role: 'customer',
            generation: 1,
          ),
        );
    await tester.pump();
    expect(probe.changes, changes);
    expect(probe.bridge.isCurrent(lease, bridgeOwner, cache), true);
    cache.invalidate('notifications/count');
    expect(
      probe.events.where((e) => e == 'resource:notifications/count').length,
      1,
    );
  });

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
    const SessionScope(userId: null, role: null, generation: 2),
    const SessionScope(
      userId: '30000000-0000-4000-8000-000000000001',
      role: 'unknown',
      generation: 1,
    ),
    const SessionScope.unresolved(),
  ]) {
    testWidgets(
      'namespace transition clears owner marker before render: ${next.userId}/${next.role}/${next.generation}',
      (tester) async {
        await tester.pumpWidget(bridgeHost(container, probe));
        final lease = probe.bridge.captureLease(bridgeOwner, cache);
        probe.events.clear();
        probe.marker = 'private A';
        container.read(controlledScope.notifier).change(next);
        await tester.pump();
        final live = container.read(epochCacheProvider);
        expect(
          probe.events.indexOf('namespace'),
          lessThan(probe.events.indexOf('render:empty')),
        );
        expect(probe.marker, isNull);
        expect(probe.bridge.isCurrent(lease, next, live), false);
        expect(
          probe.bridge.captureLease(next, live) != null,
          next.canReadPrivateData,
        );
        cache.invalidate('old-cache-event');
        expect(probe.events, isNot(contains('resource:old-cache-event')));
        expect(find.text('private A'), findsNothing);
      },
    );
  }

  testWidgets('cache replacement rejects old lease and detaches old listener', (
    tester,
  ) async {
    await tester.pumpWidget(bridgeHost(container, probe));
    final lease = probe.bridge.captureLease(bridgeOwner, cache);
    final replacement = EpochCache(bridgeOwner);
    container.read(controlledCache.notifier).replace(replacement);
    await tester.pump();
    expect(probe.bridge.isCurrent(lease, bridgeOwner, replacement), false);
    probe.events.clear();
    cache.invalidate('old');
    replacement.invalidate('new');
    expect(probe.events, ['resource:new']);
  });

  testWidgets(
    'same-object block signals namespace loss before resource event synchronously',
    (tester) async {
      await tester.pumpWidget(bridgeHost(container, probe));
      cache.begin('notifications/count');
      final lease = probe.bridge.captureLease(bridgeOwner, cache);
      probe.events.clear();
      probe.marker = 'private';
      cache.blockSession();
      expect(probe.marker, isNull); // No pump: clear is synchronous.
      expect(probe.events, ['namespace', 'resource:notifications/count']);
      expect(probe.bridge.isCurrent(lease, bridgeOwner, cache), false);
    },
  );

  testWidgets(
    'ordinary repeated invalidations preserve lease and forward every event',
    (tester) async {
      await tester.pumpWidget(bridgeHost(container, probe));
      final lease = probe.bridge.captureLease(bridgeOwner, cache);
      final changes = probe.changes;
      probe.events.clear();
      cache.invalidate('notifications/list/all/20/null');
      cache.invalidate('notifications/list/all/20/null');
      expect(
        probe.events,
        List.filled(2, 'resource:notifications/list/all/20/null'),
      );
      expect(probe.changes, changes);
      expect(probe.bridge.isCurrent(lease, bridgeOwner, cache), true);
    },
  );

  testWidgets(
    'widget disposal closes subscriptions and canonical cache remains usable',
    (tester) async {
      await tester.pumpWidget(bridgeHost(container, probe));
      final lease = probe.bridge.captureLease(bridgeOwner, cache);
      await tester.pumpWidget(const SizedBox());
      final length = probe.events.length;
      cache.invalidate('late');
      container
          .read(controlledScope.notifier)
          .change(const SessionScope.unresolved());
      container.read(controlledCache.notifier).replace(EpochCache(bridgeOwner));
      await tester.pump();
      expect(probe.events.length, length);
      expect(cache.canRead, true);
      expect(probe.bridge.isCurrent(lease, bridgeOwner, cache), false);
      probe.bridge.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'copied cache callback arriving after bridge disposal is ignored',
    (tester) async {
      final cancel = cache.listen((_) => probe.bridge.dispose());
      await tester.pumpWidget(bridgeHost(container, probe));
      probe.events.clear();
      cache.invalidate(
        'late-copy',
      ); // EpochCache iterates a copied listener list.
      expect(probe.events, isEmpty);
      cancel();
    },
  );

  testWidgets(
    'dispose inside immediate notification prevents remaining registration',
    (tester) async {
      probe.disposeImmediately = true;
      await tester.pumpWidget(bridgeHost(container, probe));
      expect(probe.changes, 1);
      final length = probe.events.length;
      cache.invalidate('late');
      container
          .read(controlledScope.notifier)
          .change(const SessionScope.unresolved());
      await tester.pump();
      expect(probe.changes, 1);
      expect(probe.events.skip(length).every((e) => e == 'render:empty'), true);
      expect(probe.bridge.captureLease(bridgeOwner, cache), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dispose during immediate cache callback closes both handles', (
    tester,
  ) async {
    probe.disposeAtChange = 2;
    await tester.pumpWidget(bridgeHost(container, probe));
    expect(probe.changes, 2);
    cache.invalidate('late-cache');
    container
        .read(controlledScope.notifier)
        .change(const SessionScope.unresolved());
    await tester.pump();
    expect(probe.changes, 2);
    expect(probe.events.where((e) => e.startsWith('resource:')), isEmpty);
    expect(probe.bridge.captureLease(bridgeOwner, cache), isNull);
    expect(tester.takeException(), isNull);
  });
}
