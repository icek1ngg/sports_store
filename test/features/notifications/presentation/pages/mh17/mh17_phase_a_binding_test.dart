import 'mh17_modal_integration_support.dart';

import 'package:sports_store/features/notifications/presentation/widgets/mh17/notification_filters.dart';
import 'package:sports_store/features/notifications/presentation/widgets/unread_badge.dart';

void main() {
  NotificationTile tile(WidgetTester tester) => tester.widget<NotificationTile>(
    find.byType(NotificationTile, skipOffstage: false),
  );

  for (final countFirst in [false, true]) {
    testWidgets(
      'Page bridge retains stale rows and waits for both new resources: countFirst=$countFirst',
      (tester) async {
        final rig = PageModalRig();
        final head = Completer<NotificationPage>();
        final count = Completer<int>();
        try {
          await rig.mount(tester);
          final accepted = tile(tester).notification;
          await rig.open(tester);
          final handle = rig.handle(tester);
          rig.repository.pageHandler = (_) => head.future;
          rig.repository.countHandler = () => count.future;
          rig.container.invalidate(epochCacheProvider);
          await tester.pump();
          rig.modalHidden(tester);
          expect(handle.isRevoked, true);
          expect(tile(tester).notification, same(accepted));
          expect(tile(tester).onTap, isNull);
          expect(tile(tester).onMarkRead, isNull);
          if (countFirst) {
            count.complete(1207);
          } else {
            head.complete(contextPage(contextScope, 'B'));
          }
          await tester.pumpAndSettle();
          expect(tile(tester).onTap, isNull);
          if (countFirst) {
            head.complete(contextPage(contextScope, 'B'));
          } else {
            count.complete(1207);
          }
          await tester.pumpAndSettle();
          expect(tile(tester).notification.title, 'Thông báo riêng B');
          expect(tile(tester).onTap, isNotNull);
          expect(
            tester
                .widget<UnreadBadge>(
                  find.byType(UnreadBadge, skipOffstage: false),
                )
                .count,
            1207,
          );
          expect(rig.handle(tester), same(handle));
          expect(
            handle.isRevoked,
            true,
          ); // Recovery never revives the old route.
          expect(rig.repository.markCalls, 0);
        } finally {
          if (!head.isCompleted) head.complete(contextPage(contextScope, 'B'));
          if (!count.isCompleted) count.complete(1207);
          await rig.cleanup(tester);
        }
      },
    );
  }

  testWidgets(
    'captured pre-handoff read/open callbacks stay revoked after recovery',
    (tester) async {
      final rig = PageModalRig();
      rig.repository.read = false;
      try {
        await rig.mount(tester);
        final oldOpen = tile(tester).onTap!;
        final oldRead = tile(tester).onMarkRead!;
        rig.repository.label = 'B';
        rig.container.invalidate(epochCacheProvider);
        await tester.pumpAndSettle();
        expect(tile(tester).onTap, isNotNull);
        expect(tile(tester).onMarkRead, isNotNull);
        oldRead();
        oldOpen();
        await tester.pumpAndSettle();
        expect(rig.repository.markCalls, 0);
        expect(find.byType(Mh17NotificationContextModal), findsNothing);
        expect(tile(tester).notification.title, 'Thông báo riêng B');
        // A newly rendered capability still works through the existing VM/modal.
        await tester.tap(find.text('Thông báo riêng B'));
        await tester.pumpAndSettle();
        expect(rig.repository.markCalls, 1);
        expect(find.byType(Mh17NotificationContextModal), findsOneWidget);
      } finally {
        await rig.cleanup(tester);
      }
    },
  );

  testWidgets(
    'cache handoff discards tail intent and late old tail cannot resurrect rows',
    (tester) async {
      final rig = PageModalRig();
      final tail = Completer<NotificationPage>();
      final head = Completer<NotificationPage>();
      final count = Completer<int>();
      rig.repository.pageHandler = (query) => query.cursor == null
          ? Future.value(
              NotificationPage(
                items: contextPage(contextScope, 'A').items,
                nextCursor: 'old-tail',
                unreadCount: null,
                asOf: DateTime.utc(2026, 10, 26),
              ),
            )
          : tail.future;
      try {
        await rig.mount(tester);
        await tester.tap(find.text('Tải thêm'));
        await tester.pump();
        rig.repository.pageHandler = (query) {
          expect(query.cursor, isNull);
          return head.future;
        };
        rig.repository.countHandler = () => count.future;
        rig.container.invalidate(epochCacheProvider);
        await tester.pump();
        expect(tile(tester).notification.title, 'Thông báo riêng A');
        expect(tile(tester).onTap, isNull);
        expect(find.text('Tải thêm'), findsNothing);
        tail.complete(contextPage(contextScope, 'OLD TAIL'));
        await tester.pump();
        expect(tile(tester).notification.title, 'Thông báo riêng A');
        head.complete(contextPage(contextScope, 'B'));
        count.complete(97);
        await tester.pumpAndSettle();
        expect(tile(tester).notification.title, 'Thông báo riêng B');
        expect(tile(tester).onTap, isNotNull);
        expect(find.text('Thông báo riêng OLD TAIL'), findsNothing);
        expect(find.text('Tải thêm'), findsNothing);
      } finally {
        if (!tail.isCompleted) {
          tail.complete(contextPage(contextScope, 'OLD TAIL'));
        }
        if (!head.isCompleted) head.complete(contextPage(contextScope, 'B'));
        if (!count.isCompleted) count.complete(97);
        await rig.cleanup(tester);
      }
    },
  );

  testWidgets(
    'handoff count denial clears retained rows and explicit two-fresh recovery works',
    (tester) async {
      final rig = PageModalRig();
      final head = Completer<NotificationPage>();
      final count = Completer<int>();
      try {
        await rig.mount(tester);
        rig.repository.pageHandler = (_) => head.future;
        rig.repository.countHandler = () => count.future;
        rig.container.invalidate(epochCacheProvider);
        await tester.pump();
        expect(tile(tester).notification.title, 'Thông báo riêng A');
        count.completeError(
          const AppFailure(code: AppFailure.forbiddenOrUnavailable),
        );
        await tester.pumpAndSettle();
        expect(find.byType(NotificationTile), findsNothing);
        head.complete(contextPage(contextScope, 'LATE'));
        await tester.pumpAndSettle();
        expect(find.byType(NotificationTile), findsNothing);
        rig.repository.pageHandler = (_) async =>
            contextPage(contextScope, 'B');
        rig.repository.countHandler = () async => 1207;
        tester
            .widget<Mh17NotificationFilters>(
              find.byType(Mh17NotificationFilters),
            )
            .onRefresh!();
        await tester.pumpAndSettle();
        expect(tile(tester).notification.title, 'Thông báo riêng B');
        expect(tile(tester).onTap, isNotNull);
        expect(
          tester.widget<UnreadBadge>(find.byType(UnreadBadge)).count,
          1207,
        );
      } finally {
        if (!head.isCompleted) head.complete(contextPage(contextScope, 'B'));
        if (!count.isCompleted) count.complete(1207);
        await rig.cleanup(tester);
      }
    },
  );
}
