import 'mh17_modal_integration_support.dart';

void main() {
  late PageModalRig rig;
  setUp(() => rig = PageModalRig());

  testWidgets(
    'parent denial revokes handle before modal mounts even with readable cache',
    (tester) async {
      final observer = ContextPushObserver();
      rig.observer = observer;
      await rig.mount(tester);
      tester.widget<NotificationTile>(find.byType(NotificationTile)).onTap!();
      final handle = observer.handle!;
      expect(handle.isRevoked, false);
      expect(find.byType(Mh17NotificationContextModal), findsNothing);
      rig.repository.denyCount = true;
      await rig.container
          .read(unreadCountFoundationProvider.notifier)
          .refresh();
      expect(rig.container.read(epochCacheProvider).canRead, true);
      expect(
        handle.isRevoked,
        true,
      ); // Parent link, before modal subscriptions exist.
      await tester.pump();
      rig.hidden(tester);
      await tester.pumpAndSettle();
      rig.hidden(tester);
      await rig.cleanup(tester);
    },
  );

  testWidgets(
    'Page-local provider container fails closed instead of attaching route to wrong DI',
    (tester) async {
      rig.pageLocalScope = true;
      await rig.mount(tester);
      await tester.tap(find.text('Thông báo riêng A'));
      await tester.pumpAndSettle();
      expect(find.byType(Mh17NotificationContextModal), findsNothing);
      expect(rig.navigator.currentState!.canPop(), false);
      expect(tester.takeException(), isNull);
      await rig.cleanup(tester);
    },
  );

  for (final reason in ['account', 'count denial', 'blocked cache']) {
    testWidgets(
      'real Page disposal detaches links and surviving route guards $reason',
      (tester) async {
        await rig.mount(tester);
        await rig.open(tester);
        final pageState = tester.state(
          find.byType(NotificationsPage, skipOffstage: false),
        );
        final handle = rig.handle(tester);
        rig.visible.value = false;
        await tester.pump();
        expect(pageState.mounted, false);
        expect(handle.isRevoked, false);
        expect(find.text('Nội dung riêng A'), findsOneWidget);
        if (reason == 'account') {
          rig.repository.label = 'B';
          rig.change(
            const SessionScope(
              userId: otherContextOwner,
              role: 'customer',
              generation: 2,
            ),
          );
        } else if (reason == 'blocked cache') {
          rig.container.read(epochCacheProvider).blockSession();
        } else {
          rig.repository.denyCount = true;
          await rig.container
              .read(unreadCountFoundationProvider.notifier)
              .refresh();
        }
        await tester.pump();
        rig.hidden(tester);
        await tester.pumpAndSettle();
        rig.hidden(tester);
        rig.navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await rig.cleanup(tester);
      },
    );
  }

  testWidgets(
    'late A list/count responses cannot restore private context in B',
    (tester) async {
      await rig.mount(tester);
      await rig.open(tester);
      final oldPage = contextPage(contextScope, 'A');
      final list = Completer<NotificationPage>(), count = Completer<int>();
      rig.repository.pageHandler = (_) => list.future;
      rig.repository.countHandler = () => count.future;
      final pageRead = rig.container
          .read(
            notificationPageFoundationProvider(NotificationQuery()).notifier,
          )
          .refresh();
      final countRead = rig.container
          .read(unreadCountFoundationProvider.notifier)
          .refresh();
      await tester.pump();
      rig.repository.pageHandler = null;
      rig.repository.countHandler = null;
      rig.repository.label = 'B';
      rig.change(
        const SessionScope(
          userId: otherContextOwner,
          role: 'customer',
          generation: 2,
        ),
      );
      await tester.pump();
      rig.hidden(tester);
      list.complete(oldPage);
      count.complete(99);
      await tester.pumpAndSettle();
      await pageRead;
      await countRead;
      rig.hidden(tester);
      expect(find.text('99', skipOffstage: false), findsNothing);
      await rig.cleanup(tester);
    },
  );

  for (final reason in ['account', 'projection refresh', 'Page disposal']) {
    testWidgets(
      'captured notification callback cannot open old context after $reason',
      (tester) async {
        await rig.mount(tester);
        final tap = tester
            .widget<NotificationTile>(find.byType(NotificationTile))
            .onTap!;
        if (reason == 'account') {
          rig.repository.label = 'B';
          rig.change(
            const SessionScope(
              userId: otherContextOwner,
              role: 'customer',
              generation: 2,
            ),
          );
        } else if (reason == 'projection refresh') {
          rig.repository.label = 'A mới';
          await rig.refresh(tester);
        } else {
          rig.visible.value = false;
        }
        await tester.pumpAndSettle();
        tap();
        await tester.pumpAndSettle();
        expect(find.byType(Mh17NotificationContextModal), findsNothing);
        expect(
          find.text('Nội dung riêng A', skipOffstage: false),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await rig.cleanup(tester);
      },
    );
  }

  testWidgets('multiple owner-loss/release callbacks remain safe after Close', (
    tester,
  ) async {
    await rig.mount(tester);
    await rig.open(tester);
    final handle = rig.handle(tester);
    rig.container.read(epochCacheProvider).blockSession();
    await tester.pump();
    rig.hidden(tester);
    rig.container.read(epochCacheProvider).blockSession();
    handle.revoke();
    handle.revoke();
    rig.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    handle.release();
    handle.release();
    rig.visible.value = false;
    await tester.pump();
    expect(handle.isRevoked, true);
    expect(tester.takeException(), isNull);
    await rig.cleanup(tester);
  });

  testWidgets(
    'loss between real Page push and first modal render cannot display old body',
    (tester) async {
      await rig.mount(tester);
      tester.widget<NotificationTile>(find.byType(NotificationTile)).onTap!();
      rig.repository.label = 'B';
      rig.change(
        const SessionScope(
          userId: otherContextOwner,
          role: 'customer',
          generation: 2,
        ),
      );
      await tester.pump();
      rig.hidden(tester);
      await tester.pumpAndSettle();
      rig.hidden(tester);
      await rig.cleanup(tester);
    },
  );
}
