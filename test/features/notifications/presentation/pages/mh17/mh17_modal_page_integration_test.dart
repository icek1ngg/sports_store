import 'mh17_modal_integration_support.dart';

void main() {
  late PageModalRig rig;
  setUp(() => rig = PageModalRig());

  testWidgets(
    'real Page opens approved context owner and Close releases handle',
    (tester) async {
      await rig.mount(tester);
      await rig.open(tester);
      final handle = rig.handle(tester);
      expect(handle.isRevoked, false);
      expect(find.byType(Mh17NotificationContextSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Mh17NotificationContextSheet),
          matching: find.text('Nội dung riêng A'),
        ),
        findsOneWidget,
      );
      expect(rig.repository.markCalls, 0);
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
      expect(handle.isRevoked, true);
      expect(find.byType(Mh17NotificationContextModal), findsNothing);
      expect(find.byType(NotificationsPage), findsOneWidget);
      await rig.cleanup(tester);
    },
  );

  testWidgets('system Back preserves Page and releases route context', (
    tester,
  ) async {
    await rig.mount(tester);
    await rig.open(tester);
    final handle = rig.handle(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(handle.isRevoked, true);
    expect(rig.navigator.currentState!.canPop(), false);
    expect(find.byType(NotificationsPage), findsOneWidget);
    await rig.cleanup(tester);
  });

  for (final reason in [
    'account',
    'generation',
    'logout',
    'role',
    'blocked cache',
  ]) {
    testWidgets(
      'real Page $reason hides context on first loss frame without pop',
      (tester) async {
        await rig.mount(tester);
        await rig.open(tester);
        if (reason == 'blocked cache') {
          rig.container.read(epochCacheProvider).blockSession();
          expect(rig.handle(tester).isRevoked, true);
        } else {
          rig.repository.label = 'B';
          rig.change(
            SessionScope(
              userId: reason == 'logout'
                  ? null
                  : reason == 'account'
                  ? otherContextOwner
                  : contextOwner,
              role: reason == 'logout'
                  ? null
                  : reason == 'role'
                  ? 'unknown'
                  : 'customer',
              generation: 2,
            ),
          );
        }
        await tester.pump();
        rig.hidden(tester);
        await tester.pumpAndSettle();
        rig.hidden(tester);
        await rig.cleanup(tester);
      },
    );
  }

  testWidgets(
    'same-owner cache replacement revokes modal while legacy feed retains disabled stale rows',
    (tester) async {
      await rig.mount(tester);
      await rig.open(tester);
      final pending = Completer<NotificationPage>();
      rig.repository.pageHandler = (_) => pending.future;
      rig.container.invalidate(epochCacheProvider);
      await tester.pump();
      rig.modalHidden(tester);
      final oldTile = tester.widget<NotificationTile>(
        find.byType(NotificationTile, skipOffstage: false),
      );
      expect(oldTile.notification.recipientId, contextOwner);
      expect(oldTile.onTap, isNull);
      expect(oldTile.onMarkRead, isNull);
      pending.complete(contextPage(contextScope, 'B'));
      await tester.pumpAndSettle();
      rig.modalHidden(tester);
      expect(find.text('Nội dung riêng A', skipOffstage: false), findsNothing);
      await rig.cleanup(tester);
    },
  );

  for (final list in [true, false]) {
    testWidgets(
      'parent ${list ? 'list' : 'count'} denial immediately revokes and recovery cannot resurrect handle',
      (tester) async {
        await rig.mount(tester);
        await rig.open(tester);
        Future<void> refresh;
        if (list) {
          rig.repository.denyList = true;
          refresh = rig.container
              .read(
                notificationPageFoundationProvider(NotificationQuery())
                    .notifier,
              )
              .refresh();
        } else {
          rig.repository.denyCount = true;
          refresh = rig.container
              .read(unreadCountFoundationProvider.notifier)
              .refresh();
        }
        await refresh;
        expect(
          rig.handle(tester).isRevoked,
          true,
        ); // No render needed for cell revocation.
        await tester.pump();
        rig.hidden(tester);
        rig.repository.denyList = false;
        rig.repository.denyCount = false;
        rig.container.invalidate(
          notificationPageFoundationProvider(NotificationQuery()),
        );
        rig.container.invalidate(unreadCountFoundationProvider);
        await tester.pumpAndSettle();
        rig.hidden(tester);
        await rig.cleanup(tester);
      },
    );
  }

  testWidgets('same-owner stale refresh keeps authorized modal content', (
    tester,
  ) async {
    await rig.mount(tester);
    await rig.open(tester);
    final handle = rig.handle(tester);
    rig.container.read(epochCacheProvider).invalidatePrefix('notifications/');
    await tester.pump();
    expect(handle.isRevoked, false);
    await rig.refresh(tester);
    expect(handle.isRevoked, false);
    expect(
      find.descendant(
        of: find.byType(Mh17NotificationContextSheet),
        matching: find.text('Nội dung riêng A'),
      ),
      findsOneWidget,
    );
    await rig.cleanup(tester);
  });

  testWidgets(
    'unread acknowledgement removes row but keeps current-owner informational context',
    (tester) async {
      rig.repository.read = false;
      await rig.mount(tester);
      await tester.tap(find.text('Chưa đọc'));
      await tester.pumpAndSettle();
      await rig.open(tester);
      expect(rig.repository.markCalls, 1);
      expect(rig.handle(tester).isRevoked, false);
      expect(find.byType(Mh17NotificationContextSheet), findsOneWidget);
      expect(
        rig.container
            .read(epochCacheProvider)
            .read<int>('notifications/count')!
            .data,
        41,
      );
      await rig.cleanup(tester);
    },
  );
}
