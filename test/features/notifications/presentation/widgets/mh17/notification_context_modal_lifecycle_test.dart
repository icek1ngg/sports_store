import 'notification_context_test_support.dart';

void main() {
  late ContextRig rig;
  setUp(() => rig = ContextRig());

  for (final scenario in [
    'account',
    'generation',
    'logout',
    'role',
    'cache replacement',
    'cache block',
  ]) {
    testWidgets(
      '$scenario revokes private content while retaining modal route',
      (tester) async {
        rig.create();
        await rig.mount(tester);
        await rig.open(tester);
        final original = rig.container.read(epochCacheProvider);
        switch (scenario) {
          case 'account':
            rig.change(
              const SessionScope(
                userId: otherContextOwner,
                role: 'customer',
                generation: 2,
              ),
            );
          case 'generation':
            rig.change(
              const SessionScope(
                userId: contextOwner,
                role: 'customer',
                generation: 2,
              ),
            );
          case 'logout':
            rig.change(
              const SessionScope(userId: null, role: null, generation: 2),
            );
          case 'role':
            rig.change(
              const SessionScope(
                userId: contextOwner,
                role: 'unknown',
                generation: 2,
              ),
            );
          case 'cache replacement':
            rig.container.invalidate(epochCacheProvider);
          case 'cache block':
            original.blockSession();
            expect(rig.handle!.isRevoked, true);
        }
        await tester.pump();
        expectPrivateHidden(rig);
        await tester.pumpAndSettle();
        expectPrivateHidden(rig);
        await rig.cleanup(tester);
      },
    );
  }

  for (final list in [false, true]) {
    testWidgets(
      '${list ? 'list' : 'count'} denial irreversibly revokes context',
      (tester) async {
        rig.create();
        await rig.mount(tester);
        await rig.open(tester);
        if (list) {
          rig.repository.denyList = true;
          final refresh = rig.container
              .read(
                notificationPageFoundationProvider(rig.handle!.query).notifier,
              )
              .refresh();
          await tester.pumpAndSettle();
          await refresh;
        } else {
          rig.repository.denyCount = true;
          final refresh = rig.container
              .read(unreadCountFoundationProvider.notifier)
              .refresh();
          await tester.pumpAndSettle();
          await refresh;
        }
        await tester.pump();
        expectPrivateHidden(rig);
        rig.repository.denyList = false;
        rig.repository.denyCount = false;
        rig.container.invalidate(unreadCountFoundationProvider);
        rig.container.invalidate(
          notificationPageFoundationProvider(rig.handle!.query),
        );
        await tester.pumpAndSettle();
        expectPrivateHidden(rig);
        await rig.cleanup(tester);
      },
    );
  }

  testWidgets(
    'host disposal leaves route independently guarded on later account switch',
    (tester) async {
      rig.create();
      await rig.mount(tester);
      await rig.open(tester);
      rig.hostVisible.value = false;
      await tester.pump();
      expect(rig.hostDisposed, true);
      expect(rig.handle!.isRevoked, false);
      expect(find.text('Nội dung riêng A'), findsOneWidget);
      rig.change(
        const SessionScope(
          userId: otherContextOwner,
          role: 'customer',
          generation: 2,
        ),
      );
      await tester.pump();
      expectPrivateHidden(rig);
      await rig.cleanup(tester);
    },
  );

  testWidgets(
    'owner stale refresh and canonical invalidation do not revoke allowed content',
    (tester) async {
      rig.create();
      await rig.mount(tester);
      await rig.open(tester);
      rig.container.read(epochCacheProvider).invalidatePrefix('notifications/');
      await tester.pump();
      expect(rig.handle!.isRevoked, false);
      expect(find.text('Nội dung riêng A'), findsOneWidget);
      final refresh = rig.container
          .read(notificationPageFoundationProvider(rig.handle!.query).notifier)
          .refresh();
      await tester.pumpAndSettle();
      await refresh;
      expect(rig.handle!.isRevoked, false);
      expect(find.text('Nội dung riêng A'), findsOneWidget);
      expect(rig.repository.markCalls, 0);
      await rig.cleanup(tester);
    },
  );

  testWidgets(
    'late old head cannot restore revoked body after account switch',
    (tester) async {
      rig.create();
      await rig.mount(tester);
      await rig.open(tester);
      final pending = rig.repository.pendingPage =
          Completer<NotificationPage>();
      final refresh = rig.container
          .read(notificationPageFoundationProvider(rig.handle!.query).notifier)
          .refresh();
      await tester.pump();
      rig.change(
        const SessionScope(
          userId: otherContextOwner,
          role: 'customer',
          generation: 2,
        ),
      );
      await tester.pump();
      expectPrivateHidden(rig);
      pending.complete(emptyContextPage());
      await tester.pumpAndSettle();
      await refresh;
      expectPrivateHidden(rig);
      await rig.cleanup(tester);
    },
  );

  testWidgets(
    'block before first modal frame with no cache event fails live render check',
    (tester) async {
      rig.create();
      final cache = rig.container.read(epochCacheProvider);
      cache.blockSession(); // No resource keys: EpochCache emits no callback here.
      expect(cache.canRead, false);
      await rig.mount(tester);
      await rig.open(tester);
      expectPrivateHidden(rig);
      await rig.cleanup(tester);
    },
  );

  testWidgets(
    'released route ignores late foundation response and cache callbacks',
    (tester) async {
      rig.create();
      await rig.mount(tester);
      await rig.open(tester);
      final pending = rig.repository.pendingPage =
          Completer<NotificationPage>();
      final refresh = rig.container
          .read(notificationPageFoundationProvider(rig.handle!.query).notifier)
          .refresh();
      await tester.pump();
      rig.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      pending.complete(emptyContextPage());
      await tester.pumpAndSettle();
      await refresh;
      rig.container.read(epochCacheProvider).blockSession();
      await tester.pump();
      expect(rig.handle!.isRevoked, true);
      expect(tester.takeException(), isNull);
      expect(find.byType(Mh17NotificationContextModal), findsNothing);
      await rig.cleanup(tester);
    },
  );

  testWidgets(
    'scope lost after push but before first modal frame never renders body',
    (tester) async {
      rig.create();
      await rig.mount(tester);
      await tester.tap(find.text('Open context'));
      rig.change(
        const SessionScope(
          userId: otherContextOwner,
          role: 'customer',
          generation: 2,
        ),
      );
      await tester.pump();
      expectPrivateHidden(rig);
      await tester.pumpAndSettle();
      expectPrivateHidden(rig);
      await rig.cleanup(tester);
    },
  );

  testWidgets('rebuilds keep one guard set and no extra canonical operations', (
    tester,
  ) async {
    rig.create();
    await rig.mount(tester);
    await rig.open(tester);
    final element = tester.element(find.byType(Mh17NotificationContextModal));
    for (var i = 0; i < 4; i++) {
      element.markNeedsBuild();
      await tester.pump();
    }
    expect(rig.repository.pageCalls, 1);
    expect(rig.repository.countCalls, 1);
    expect(rig.repository.markCalls, 0);
    expect(rig.handle!.isRevoked, false);
    rig.container.read(epochCacheProvider).blockSession();
    expect(rig.handle!.isRevoked, true);
    await tester.pump();
    expectPrivateHidden(rig);
    await rig.cleanup(tester);
  });

  testWidgets(
    'silent unreadable cache is checked again before private rebuild',
    (tester) async {
      rig.create();
      await rig.mount(tester);
      await rig.open(tester);
      rig.container
          .read(epochCacheProvider)
          .dispose(); // No invalidation callback.
      tester
          .element(find.byType(Mh17NotificationContextModal))
          .markNeedsBuild();
      await tester.pump();
      expectPrivateHidden(rig);
      expect(tester.takeException(), isNull);
      await rig.cleanup(tester);
    },
  );
}
