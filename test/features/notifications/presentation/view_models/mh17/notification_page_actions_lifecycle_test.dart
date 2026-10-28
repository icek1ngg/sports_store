import 'notification_actions_test_support.dart';

void main() {
  late ActionRig rig;
  setUp(() => rig = ActionRig());
  tearDown(() => rig.dispose());

  void loseOwner(String reason) {
    switch (reason) {
      case 'account':
      case 'generation':
        rig.container
            .read(actionScope.notifier)
            .change(
              SessionScope(
                userId: reason == 'account'
                    ? '20000000-0000-4000-8000-000000000002'
                    : fixtureCustomerId,
                role: 'customer',
                generation: reason == 'generation' ? 2 : 1,
              ),
            );
      case 'cache replacement':
        rig.container.invalidate(epochCacheProvider);
      case 'cache block':
        rig.cache.blockSession();
      case 'lease revocation':
        rig.session.revokeAccess();
      case 'inactive':
        rig.active = false;
      case 'disposed':
        rig.actions.dispose();
    }
  }

  for (final reason in [
    'account',
    'generation',
    'cache replacement',
    'cache block',
    'lease revocation',
    'inactive',
    'disposed',
  ]) {
    test('late resolver cannot navigate or publish after $reason', () async {
      final item = actionItem(read: true);
      final ns = rig.seed(item);
      final gate = Completer<NotificationTargetDecision>();
      rig.resolver.handler = (_) => gate.future;
      final opening = rig.actions.open(item, ns, rig.ports);
      expect(rig.resolver.calls, [item.id]);
      loseOwner(reason);
      await settleAction();
      gate.complete(availableActionOrder);
      expect(await opening, false);
      expect(rig.navigations, isEmpty);
      expect(rig.messages, isEmpty);
      expect(rig.contexts, isEmpty);
    });
  }

  for (final reason in [
    'account',
    'generation',
    'cache replacement',
    'cache block',
    'disposed',
  ]) {
    test(
      'late canonical acknowledgement cannot publish after $reason',
      () async {
        final item = actionItem();
        final ns = rig.seed(item);
        final gate = Completer<NotificationItem>();
        rig.repository.handler = (_) => gate.future;
        final reading = rig.actions.markRead(item, ns, rig.ports);
        loseOwner(reason);
        await settleAction();
        gate.complete(actionItem(read: true));
        expect(await reading, false);
        expect(rig.messages, isEmpty);
        expect(rig.navigations, isEmpty);
      },
    );
  }

  test(
    'same-owner cache invalidation does not cancel already authorized open',
    () async {
      final item = actionItem(read: true);
      final ns = rig.seed(item);
      final gate = Completer<NotificationTargetDecision>();
      rig.resolver.handler = (_) => gate.future;
      final opening = rig.actions.open(item, ns, rig.ports);
      rig.cache.invalidate(
        NotificationSnapshotProjection.resourceKey(rig.reads.headQuery),
      );
      gate.complete(availableActionOrder);
      expect(await opening, true);
      expect(rig.navigations, [availableActionOrder]);
      expect(await rig.actions.open(item, ns, rig.ports), false);
      expect(rig.resolver.calls, [item.id]);
    },
  );

  test(
    'navigation callback removed during resolution stays unavailable',
    () async {
      final item = actionItem(read: true);
      final ns = rig.seed(item);
      final gate = Completer<NotificationTargetDecision>();
      rig.resolver.handler = (_) => gate.future;
      final opening = rig.actions.open(item, ns, rig.ports);
      rig.hasNavigation = false;
      gate.complete(availableActionOrder);
      expect(await opening, false);
      expect(rig.navigations, isEmpty);
      expect(rig.messages, hasLength(1));
    },
  );

  test('foreign informational payload never reaches context port', () async {
    final ns = rig.seed(actionItem(read: true));
    final foreign = actionItem(
      type: 'notification_only',
      read: true,
      recipient: '20000000-0000-4000-8000-000000000002',
    );
    expect(await rig.actions.open(foreign, ns, rig.ports), false);
    expect(rig.contexts, isEmpty);
    expect(rig.repository.calls, isEmpty);
    expect(rig.resolver.calls, isEmpty);
  });

  test(
    'failure-state getter revoking lease cannot publish a message',
    () async {
      final item = actionItem();
      final ns = rig.seed(item);
      rig.repository.handler = (_) =>
          Future.error(const AppFailure(code: AppFailure.network));
      final base = rig.ports;
      final ports = (
        isActive: base.isActive,
        reads: base.reads,
        query: base.query,
        interaction: base.interaction,
        state: () {
          final state = base.state();
          rig.session.revokeAccess();
          return state;
        },
        navigation: base.navigation,
        message: base.message,
        context: base.context,
      );
      expect(await rig.actions.markRead(item, ns, ports), false);
      expect(rig.messages, isEmpty);
    },
  );

  for (final reason in ['account', 'disposed']) {
    test('navigation result cannot publish success after $reason', () async {
      final item = actionItem(read: true);
      final ns = rig.seed(item);
      final gate = Completer<bool>();
      rig.onNavigate = (_) => gate.future;
      final opening = rig.actions.open(item, ns, rig.ports);
      await settleAction();
      expect(rig.navigations, [availableActionOrder]);
      loseOwner(reason);
      gate.complete(true);
      expect(await opening, false);
      expect(rig.messages, isEmpty);
    });
  }

  test(
    'old informational callback cannot forward private body after logout',
    () async {
      final item = actionItem(type: 'notification_only');
      final ns = rig.seed(item);
      rig.container
          .read(actionScope.notifier)
          .change(const SessionScope.unresolved());
      await settleAction();
      expect(await rig.actions.open(item, ns, rig.ports), false);
      expect(rig.contexts, isEmpty);
      expect(rig.repository.calls, isEmpty);
    },
  );
}
