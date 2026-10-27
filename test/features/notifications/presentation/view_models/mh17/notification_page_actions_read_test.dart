import 'notification_actions_test_support.dart';

void main() {
  late ActionRig rig;
  setUp(() => rig = ActionRig());
  tearDown(() => rig.dispose());

  test('available read invokes only VM mark-read and canonical ack', () async {
    final item = actionItem();
    final ns = rig.seed(item);
    final revision = rig.reads.revision;
    expect(await rig.actions.markRead(item, ns, rig.ports), true);
    expect(rig.repository.calls, [item.id]);
    expect(rig.resolver.calls, isEmpty);
    expect(rig.navigations, isEmpty);
    expect(rig.messages, isEmpty);
    expect(rig.reads.revision, greaterThan(revision));
    expect(item.readAt, isNull);
    expect(rig.cache.read<int>('notifications/count')!.data, 41);
  });

  test('pending read shares one canonical request without optimistic row/count update', () async {
    final item = actionItem();
    final ns = rig.seed(item);
    final gate = Completer<NotificationItem>();
    rig.repository.handler = (_) => gate.future;
    final first = rig.actions.markRead(item, ns, rig.ports);
    final second = rig.actions.markRead(item, ns, rig.ports);
    expect(rig.repository.calls, [item.id]);
    expect(
      rig.container
          .read(notificationInteractionViewModelProvider)
          .isReadPending(item.id),
      true,
    );
    expect(rig.reads.items.single.readAt, isNull);
    expect(rig.cache.read<int>('notifications/count')!.data, 41);
    gate.complete(actionItem(read: true));
    expect(await first, true);
    expect(await second, true);
  });

  test(
    'invalid acknowledgement cannot report success or change local projection',
    () async {
      final item = actionItem();
      final ns = rig.seed(item);
      final revision = rig.reads.revision;
      rig.repository.handler = (_) async => item; // Missing canonical readAt.
      expect(await rig.actions.markRead(item, ns, rig.ports), false);
      expect(rig.reads.revision, revision);
      expect(rig.reads.items.single.isRead, false);
      expect(rig.messages.single, contains('Dữ liệu'));
      expect(rig.cache.read<int>('notifications/count')!.data, 41);
    },
  );

  test(
    'read failure uses existing safe failure message and preserves exact count',
    () async {
      final item = actionItem();
      final ns = rig.seed(item);
      rig.repository.handler = (_) =>
          Future.error(const AppFailure(code: AppFailure.network));
      expect(await rig.actions.markRead(item, ns, rig.ports), false);
      expect(rig.messages.single, contains('Không thể kết nối'));
      expect(rig.navigations, isEmpty);
      expect(rig.cache.read<int>('notifications/count')!.data, 41);
    },
  );

  for (final reason in ['stale', 'expired', 'inactive', 'disposed', 'denied']) {
    test('$reason entry cannot invoke protected read', () async {
      final item = actionItem();
      final ns = rig.seed(item);
      switch (reason) {
        case 'stale':
          rig.cache.invalidate(
            NotificationSnapshotProjection.resourceKey(rig.reads.headQuery),
          );
        case 'expired':
          rig.cache.blockSession();
        case 'inactive':
          rig.active = false;
        case 'disposed':
          rig.actions.dispose();
        case 'denied':
          final denied = const ReadSnapshot<int>(
            failure: AppFailure(code: AppFailure.forbiddenOrUnavailable),
          );
          final base = rig.readPorts;
          rig.reads.observeCount(ns, denied, (
            current: base.current,
            page: base.page,
            count: () => denied,
            refreshPage: base.refreshPage,
            refreshCount: base.refreshCount,
            invalidateInteractions: base.invalidateInteractions,
          ));
      }
      expect(await rig.actions.markRead(item, ns, rig.ports), false);
      expect(rig.repository.calls, isEmpty);
      expect(rig.messages, isEmpty);
    });
  }

  for (final kind in ['account', 'generation', 'cache']) {
    test(
      'captured read callback fails closed after $kind replacement',
      () async {
        final item = actionItem();
        final old = rig.seed(item);
        if (kind == 'cache') {
          rig.container.invalidate(epochCacheProvider);
        } else {
          rig.container
              .read(actionScope.notifier)
              .change(
                SessionScope(
                  userId: kind == 'account'
                      ? '20000000-0000-4000-8000-000000000002'
                      : fixtureCustomerId,
                  role: 'customer',
                  generation: kind == 'generation' ? 2 : 1,
                ),
              );
        }
        await settleAction();
        expect(await rig.actions.markRead(item, old, rig.ports), false);
        expect(rig.repository.calls, isEmpty);
      },
    );
  }

  test(
    'disposed adapter does not read ports or publish after pending ack',
    () async {
      final item = actionItem();
      final ns = rig.seed(item);
      final gate = Completer<NotificationItem>();
      rig.repository.handler = (_) => gate.future;
      final base = rig.ports;
      var adapterReads = 0;
      final NotificationActionPorts ports = (
        isActive: base.isActive,
        reads: (
          current: () {
            adapterReads++;
            return rig.namespace;
          },
          page: base.reads.page,
          count: base.reads.count,
          refreshPage: base.reads.refreshPage,
          refreshCount: base.reads.refreshCount,
          invalidateInteractions: base.reads.invalidateInteractions,
        ),
        query: base.query,
        interaction: base.interaction,
        state: base.state,
        navigation: base.navigation,
        message: base.message,
        context: base.context,
      );
      final pending = rig.actions.markRead(item, ns, ports);
      rig.actions.dispose();
      final currentReads = adapterReads;
      final stateReads = rig.stateReads;
      gate.complete(actionItem(read: true));
      expect(await pending, false);
      expect(adapterReads, currentReads);
      expect(rig.stateReads, stateReads);
      expect(rig.messages, isEmpty);
    },
  );
}
