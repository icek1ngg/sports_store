import 'mh17_page_test_support.dart';
import 'mh17_modal_integration_support.dart' as context_test;

import 'package:sports_store/features/notifications/presentation/widgets/mh17/notification_feed.dart';

Future<ProviderContainer> mountReadPage(
  WidgetTester tester,
  PageNotifications repository, {
  NotificationPage? initial,
}) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (final request in repository.requests) {
      if (!request.result.isCompleted) request.result.complete(page([]));
    }
    for (final request in repository.countRequests) {
      if (!request.isCompleted) request.complete(0);
    }
    await tester.pump();
  });
  await tester.pumpWidget(host(repository));
  await settle(tester);
  repository.requests.single.result.complete(initial ?? page([row1]));
  repository.countRequests.single.complete(41);
  await settle(tester);
  return ProviderScope.containerOf(
    tester.element(find.byType(NotificationsPage)),
  );
}

void main() {
  Future<void> refresh(WidgetTester tester) => tester
      .widget<Mh17NotificationFeed>(find.byType(Mh17NotificationFeed))
      .onRefresh!();

  testWidgets(
    'head refresh accepts an immediately completed response before next frame',
    (tester) async {
      final repository = PageNotifications();
      await mountReadPage(tester, repository);
      final oldOpen = tester
          .widget<NotificationTile>(find.byType(NotificationTile))
          .onTap!;
      final pending = refresh(tester);
      expect(repository.requests.last.query.cursor, isNull);
      repository.requests.last.result.complete(page([newRow]));
      repository.countRequests.last.complete(42);
      await pending;
      await settle(tester);
      expect(find.text(newRow.title), findsOneWidget);
      expect(find.text(row1.title), findsNothing);
      expect(find.text('42'), findsOneWidget);
      expect(
        tester.widget<NotificationTile>(find.byType(NotificationTile)).onTap,
        isNotNull,
      );
      oldOpen();
      await settle(tester);
      expect(find.text('Mục tiêu thông báo hiện chưa khả dụng.'), findsNothing);
    },
  );

  testWidgets(
    'repeated refresh rejects earlier head and accepts latest queued round',
    (tester) async {
      final repository = PageNotifications();
      await mountReadPage(tester, repository);
      final first = refresh(tester);
      final old = repository.requests.last;
      await settle(tester);
      final second = refresh(tester);
      await settle(tester);
      expect(find.text(row1.title), findsOneWidget);
      expect(
        tester.widget<NotificationTile>(find.byType(NotificationTile)).onTap,
        isNull,
      );
      old.result.complete(page([row2]));
      repository.countRequests.last.complete(41);
      await settle(tester);
      expect(repository.requests.last, isNot(same(old)));
      expect(find.text(row2.title), findsNothing);
      repository.requests.last.result.complete(page([newRow]));
      for (final request in repository.countRequests) {
        if (!request.isCompleted) request.complete(42);
      }
      await Future.wait([first, second]);
      await settle(tester);
      expect(find.text(newRow.title), findsOneWidget);
      expect(find.text(row2.title), findsNothing);
      expect(
        tester.widget<NotificationTile>(find.byType(NotificationTile)).onTap,
        isNotNull,
      );
    },
  );

  testWidgets(
    'canonical ack invalidates before Future completion without optimistic rows/count',
    (tester) async {
      final repository = PageNotifications();
      final acknowledgement = Completer<NotificationItem>();
      var mutations = 0;
      repository.markReadHandler = (_) {
        mutations++;
        return acknowledgement.future;
      };
      final container = await mountReadPage(tester, repository);
      final events = <String>[];
      final cancel = container.read(epochCacheProvider).listen((key) {
        if (key.startsWith('notifications/list/')) events.add('invalidate');
      });
      addTearDown(cancel);
      tester
          .widget<NotificationTile>(find.byType(NotificationTile))
          .onMarkRead!();
      final sameRequest = container
          .read(notificationInteractionViewModelProvider.notifier)
          .markRead(row1);
      final observed = sameRequest.then((value) {
        events.add('completed');
        return value;
      });
      await settle(tester);
      expect(mutations, 1);
      expect(find.text('41'), findsOneWidget);
      expect(
        tester
            .widget<NotificationTile>(find.byType(NotificationTile))
            .notification
            .readAt,
        isNull,
      );
      acknowledgement.complete(row1Read);
      expect(await observed, true);
      await settle(tester);
      expect(events, containsAllInOrder(['invalidate', 'completed']));
      expect(find.text('41'), findsOneWidget);
      repository.requests.last.result.complete(page([row1Read]));
      repository.countRequests.last.complete(40);
      await settle(tester);
      expect(
        tester
            .widget<NotificationTile>(find.byType(NotificationTile))
            .notification,
        same(row1Read),
      );
      expect(find.text('40'), findsOneWidget);
    },
  );

  testWidgets(
    'ack completion after intervening head refresh keeps canonical newest head',
    (tester) async {
      final repository = PageNotifications();
      final acknowledgement = Completer<NotificationItem>();
      repository.markReadHandler = (_) => acknowledgement.future;
      await mountReadPage(tester, repository);
      tester
          .widget<NotificationTile>(find.byType(NotificationTile))
          .onMarkRead!();
      final refreshRound = refresh(tester);
      repository.requests.last.result.complete(page([row1Read]));
      repository.countRequests.last.complete(40);
      await refreshRound;
      await settle(tester);
      expect(
        tester
            .widget<NotificationTile>(find.byType(NotificationTile))
            .notification,
        same(row1Read),
      );
      acknowledgement.complete(row1Read);
      await settle(tester);
      // The ack's canonical invalidation may read active resources, but completion
      // itself must not create a competing refresh driver or revive old rows.
      for (final request in repository.requests) {
        if (!request.result.isCompleted) {
          request.result.complete(page([row1Read, newRow]));
        }
      }
      for (final request in repository.countRequests) {
        if (!request.isCompleted) request.complete(40);
      }
      await settle(tester);
      expect(find.text(newRow.title), findsOneWidget);
      expect(find.text('40'), findsOneWidget);
      expect(
        tester
            .widgetList<NotificationTile>(find.byType(NotificationTile))
            .first
            .notification
            .isRead,
        true,
      );
    },
  );

  testWidgets(
    'already-read tail open adopts cached head without another backend read',
    (tester) async {
      final repository = PageNotifications();
      await mountReadPage(
        tester,
        repository,
        initial: page([row1Read], nextCursor: 'tail'),
      );
      await tester.tap(find.text('Tải thêm'));
      await settle(tester);
      repository.requests.last.result.complete(page([row2]));
      await settle(tester);
      final listReads = repository.requests.length;
      final countReads = repository.countRequests.length;
      await tester.tap(find.text(row2.title));
      await settle(tester);
      expect(repository.requests.length, listReads);
      expect(repository.countRequests.length, countReads);
      expect(find.text(row1Read.title), findsOneWidget);
      expect(find.text(row2.title), findsNothing);
      expect(find.text('41'), findsOneWidget);
      expect(find.text('Tải thêm'), findsOneWidget);
    },
  );

  testWidgets(
    'account switch during owner refresh rejects late head/count and old callback',
    (tester) async {
      final rig = context_test.PageModalRig();
      final oldHead = Completer<NotificationPage>();
      final oldCount = Completer<int>();
      try {
        await rig.mount(tester);
        final oldOpen = tester
            .widget<NotificationTile>(find.byType(NotificationTile))
            .onTap!;
        rig.repository.pageHandler = (_) => oldHead.future;
        rig.repository.countHandler = () => oldCount.future;
        final pending = refresh(tester);
        await settle(tester);
        const next = SessionScope(
          userId: context_test.otherContextOwner,
          role: 'customer',
          generation: 2,
        );
        rig.repository.pageHandler = (_) async =>
            context_test.contextPage(next, 'B');
        rig.repository.countHandler = () async => 42;
        rig.change(next);
        await tester.pump();
        expect(find.text('Thông báo riêng A'), findsNothing);
        await tester.pumpAndSettle();
        oldHead.complete(
          context_test.contextPage(context_test.contextScope, 'A'),
        );
        oldCount.complete(99);
        await pending;
        oldOpen();
        await tester.pumpAndSettle();
        expect(find.text('Thông báo riêng B'), findsOneWidget);
        expect(find.text('Thông báo riêng A'), findsNothing);
        expect(find.text('42'), findsOneWidget);
        expect(find.text('99'), findsNothing);
        expect(
          find.byType(context_test.Mh17NotificationContextModal),
          findsNothing,
        );
      } finally {
        if (!oldHead.isCompleted) {
          oldHead.complete(
            context_test.contextPage(context_test.contextScope, 'A'),
          );
        }
        if (!oldCount.isCompleted) oldCount.complete(99);
        await rig.cleanup(tester);
      }
    },
  );
}
