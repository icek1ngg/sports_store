import 'notification_context_test_support.dart';

void main() {
  late ContextRig rig;
  setUp(() => rig = ContextRig());

  testWidgets(
    'authorized context reuses sheet, safe area and Close releases route',
    (tester) async {
      rig.create();
      await rig.mount(tester);
      await rig.open(tester);
      expect(find.text('Thông báo riêng A'), findsOneWidget);
      expect(find.text('Nội dung riêng A'), findsOneWidget);
      expect(find.byType(Mh17NotificationContextSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Mh17NotificationContextSheet),
          matching: find.byType(SafeArea),
        ),
        findsOneWidget,
      );
      expect(rig.repository.markCalls, 0);
      expect(rig.repository.pageCalls, 1);
      expect(rig.repository.countCalls, 1);
      expect(
        tester.getSize(find.widgetWithText(TextButton, 'Đóng')).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
      expect(rig.completed, true);
      expect(rig.handle!.isRevoked, true);
      expect(find.byType(Mh17NotificationContextModal), findsNothing);
      await rig.cleanup(tester);
    },
  );

  testWidgets('system Back releases content without adding a route', (
    tester,
  ) async {
    rig.create();
    await rig.mount(tester);
    await rig.open(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(rig.completed, true);
    expect(rig.handle!.isRevoked, true);
    expect(rig.navigator.currentState!.canPop(), false);
    await rig.cleanup(tester);
  });

  for (final scenario in ['unresolved', 'foreign recipient', 'unknown role']) {
    testWidgets(
      '$scenario never renders private sheet on initial route frame',
      (tester) async {
        if (scenario == 'unresolved') {
          rig.change(const SessionScope.unresolved());
        }
        if (scenario == 'unknown role') {
          rig.change(
            const SessionScope(
              userId: contextOwner,
              role: 'admin',
              generation: 1,
            ),
          );
        }
        rig.create(
          recipient: scenario == 'foreign recipient'
              ? otherContextOwner
              : contextOwner,
        );
        await rig.mount(tester);
        await rig.open(tester);
        expectPrivateHidden(rig);
        expect(find.byType(Mh17NotificationContextSheet), findsNothing);
        await rig.cleanup(tester);
      },
    );
  }

  testWidgets(
    'explicit repeated revoke and release stay safe with route mounted',
    (tester) async {
      rig.create();
      await rig.mount(tester);
      await rig.open(tester);
      rig.handle!.revoke();
      rig.handle!.revoke();
      rig.handle!.release();
      rig.handle!.release();
      expect(rig.handle!.isRevoked, true);
      await tester.pump();
      expectPrivateHidden(rig);
      expect(tester.takeException(), isNull);
      rig.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await rig.cleanup(tester);
    },
  );

  testWidgets(
    'long content at 320dp text2 scrolls to reachable Close without overflow',
    (tester) async {
      final longBody = List.filled(
        70,
        'Thông tin được phép hiển thị.',
      ).join(' ');
      rig.create(title: List.filled(10, 'Tiêu đề').join(' '), body: longBody);
      await rig.mount(tester, width: 320, scale: 2);
      await rig.open(tester);
      expect(find.text(longBody), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Đóng'),
        300,
        scrollable: find.descendant(
          of: find.byType(Mh17NotificationContextSheet),
          matching: find.byType(Scrollable),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
      expect(rig.completed, true);
      await rig.cleanup(tester);
    },
  );

  testWidgets('captured Close after route disposal cannot pop another route', (
    tester,
  ) async {
    rig.create();
    await rig.mount(tester);
    await rig.open(tester);
    final close = tester
        .widget<Mh17NotificationContextSheet>(
          find.byType(Mh17NotificationContextSheet),
        )
        .onClose!;
    close();
    await tester.pumpAndSettle();
    rig.navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('New route')),
      ),
    );
    await tester.pumpAndSettle();
    close();
    await tester.pump();
    expect(find.text('New route'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await rig.cleanup(tester);
  });
}
