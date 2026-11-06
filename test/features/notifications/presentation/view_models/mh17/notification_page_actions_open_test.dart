import 'notification_actions_test_support.dart';

void main() {
  late ActionRig rig;
  setUp(() => rig = ActionRig());
  tearDown(() => rig.dispose());

  test('authorized open uses VM typed decision and own ack invalidation does not block navigation', () async {
    final item = actionItem();
    final ns = rig.seed(item);
    expect(await rig.actions.open(item, ns, rig.ports), true);
    await settleAction();
    expect(rig.repository.calls, [item.id]);
    expect(rig.resolver.calls, [item.id]);
    expect(rig.navigations.single, same(availableActionOrder));
    expect(rig.messages, isEmpty);
  });

  test('read failure is independent of authorized target opening', () async {
    final item = actionItem();
    final ns = rig.seed(item);
    rig.repository.handler = (_) =>
        Future.error(const AppFailure(code: AppFailure.network));
    expect(await rig.actions.open(item, ns, rig.ports), true);
    expect(rig.navigations.length, 1);
    expect(rig.messages, isEmpty);
    expect(rig.reads.items.single.readAt, isNull);
  });

  test(
    'typed unavailable target stays unavailable without navigation',
    () async {
      final item = actionItem(read: true);
      final ns = rig.seed(item);
      rig.resolver.decision = const NotificationTargetDecision.unavailable(
        messageKey: 'MSG-63',
      );
      expect(await rig.actions.open(item, ns, rig.ports), false);
      expect(rig.navigations, isEmpty);
      expect(rig.messages.single, 'Mục tiêu thông báo hiện chưa khả dụng.');
    },
  );

  test(
    'wrong typed screen is rejected by real VM, not repaired by Actions',
    () async {
      final item = actionItem(read: true);
      final ns = rig.seed(item);
      rig.resolver.decision = const NotificationTargetDecision(
        available: true,
        screen: NotificationTargetScreen.managerOrder,
        entityId: fixtureOrderId,
        mode: NotificationTargetMode.order,
      );
      expect(await rig.actions.open(item, ns, rig.ports), false);
      expect(rig.navigations, isEmpty);
    },
  );

  test('missing resolver remains unavailable', () async {
    rig.dispose();
    rig = ActionRig(hasResolver: false);
    final item = actionItem(read: true);
    final ns = rig.seed(item);
    expect(await rig.actions.open(item, ns, rig.ports), false);
    expect(rig.navigations, isEmpty);
    expect(rig.messages, hasLength(1));
  });

  test(
    'absent navigation callback does not fabricate successful route',
    () async {
      final item = actionItem(read: true);
      final ns = rig.seed(item);
      rig.hasNavigation = false;
      expect(await rig.actions.open(item, ns, rig.ports), false);
      expect(rig.navigations, isEmpty);
      expect(rig.messages, hasLength(1));
    },
  );

  test('informational context forwarded synchronously without item in async adapter frame', () async {
    final item = actionItem(type: 'notification_only');
    final ns = rig.seed(item);
    final gate = Completer<NotificationItem>();
    rig.repository.handler = (_) => gate.future;
    final pending = rig.actions.open(item, ns, rig.ports);
    expect(rig.contexts, [(item.title, item.body)]);
    expect(rig.resolver.calls, isEmpty);
    expect(
      await pending,
      false,
    ); // Informational context is not navigation success.
    gate.complete(actionItem(type: 'notification_only', read: true));
    await settleAction();
    expect(rig.messages, isEmpty);
  });

  test(
    'unknown subject remains unsupported without inferred route or context',
    () async {
      final item = actionItem(type: 'future_subject', read: true);
      final ns = rig.seed(item);
      expect(await rig.actions.open(item, ns, rig.ports), false);
      expect(rig.navigations, isEmpty);
      expect(rig.contexts, isEmpty);
      expect(rig.messages, hasLength(1));
    },
  );

  test('pending read and three deliberate opens keep VM dedup and F05 multiplicity', () async {
    final item = actionItem();
    final ns = rig.seed(item);
    final gate = Completer<NotificationItem>();
    rig.repository.handler = (_) => gate.future;
    final reading = rig.actions.markRead(item, ns, rig.ports);
    final opens = [
      for (var i = 0; i < 3; i++) rig.actions.open(item, ns, rig.ports),
    ];
    expect(await Future.wait(opens), [true, true, true]);
    expect(rig.repository.calls, [item.id]);
    expect(rig.resolver.calls.length, 3);
    expect(rig.navigations.length, 3);
    expect(rig.cache.read<int>('notifications/count')!.data, 41);
    gate.complete(actionItem(read: true));
    expect(await reading, true);
  });
}
