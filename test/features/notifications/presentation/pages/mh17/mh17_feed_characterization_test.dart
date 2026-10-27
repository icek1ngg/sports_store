import 'mh17_page_test_support.dart';

void main() {
  testWidgets(
    'duplicate tail ID replaces its projection without inflating count or rows',
    (tester) async {
      final repository = PageNotifications();
      await tester.pumpWidget(host(repository));
      await settle(tester);
      repository.requests.single.result.complete(
        page([row1], nextCursor: 'tail'),
      );
      repository.countRequests.single.complete(55);
      await settle(tester);
      final updated = NotificationDto.fromJson({
        ...row1Read.toMap(),
        'title': 'Projection mới cho cùng ID',
      }).domain;
      await tester.tap(find.text('Tải thêm'));
      await settle(tester);
      repository.requests.last.result.complete(page([updated, row2]));
      await settle(tester);
      final tiles = tester
          .widgetList<NotificationTile>(find.byType(NotificationTile))
          .toList();
      expect(tiles.map((tile) => tile.notification.id), [row1.id, row2.id]);
      expect(tiles.first.notification.isRead, isTrue);
      expect(find.text(row1.title), findsNothing);
      expect(find.text(updated.title), findsOneWidget);
      expect(find.text('55'), findsOneWidget);
      expect(repository.countRequests, hasLength(1));
      expect(find.text('Tải thêm'), findsNothing);
    },
  );

  testWidgets(
    'explicit head refresh rejects an in-flight tail before accepting the new head',
    (tester) async {
      final repository = PageNotifications();
      await tester.pumpWidget(host(repository));
      await settle(tester);
      repository.requests.single.result.complete(
        page([row1], nextCursor: 'old-tail'),
      );
      repository.countRequests.single.complete(55);
      await settle(tester);
      await tester.tap(find.text('Tải thêm'));
      await settle(tester);
      final oldTail = repository.requests.last;
      await tester.tap(find.byTooltip('Làm mới'));
      await settle(tester);
      final head = repository.requests.last;
      expect(head.query.cursor, isNull);
      expect(head.query.filter, NotificationFilter.all);
      expect(head, isNot(same(oldTail)));
      oldTail.result.complete(page([row2], nextCursor: 'obsolete'));
      await settle(tester);
      expect(find.text(row2.title), findsNothing);
      head.result.complete(page([newRow], nextCursor: 'fresh-tail'));
      repository.countRequests.last.complete(56);
      await settle(tester);
      expect(find.text(newRow.title), findsOneWidget);
      expect(find.text(row1.title), findsNothing);
      expect(find.text(row2.title), findsNothing);
      expect(find.text('56'), findsOneWidget);
      await tester.tap(find.text('Tải thêm'));
      await settle(tester);
      expect(repository.requests.last.query.cursor, 'fresh-tail');
      repository.requests.last.result.complete(page([row2]));
      await settle(tester);
      expect(find.text(row2.title), findsOneWidget);
    },
  );
}
