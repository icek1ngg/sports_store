import 'mh17_page_test_support.dart';

void main() {
  testWidgets(
    'malformed initial head shows safe error without rows, cursor intent or automatic retry',
    (tester) async {
      final repository = PageNotifications();
      await tester.pumpWidget(host(repository));
      await settle(tester);
      repository.requests.single.result.complete(page([row1], nextCursor: ''));
      repository.countRequests.single.complete(41);
      await settle(tester);
      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.byType(NotificationTile), findsNothing);
      expect(find.text('Tải thêm'), findsNothing);
      expect(find.text('41'), findsOneWidget);
      expect(repository.requests, hasLength(1));
      await tester.tap(find.text('Thử lại'));
      await settle(tester);
      expect(
        repository.requests.last.query.cursor,
        isNull,
      ); // Explicit head retry only.
      repository.requests.last.result.complete(page([row1]));
      repository.countRequests.last.complete(41);
      await settle(tester);
      expect(find.byType(ErrorState), findsNothing);
      expect(find.text(row1.title), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final malformed in ['', List.filled(2049, 'c').join()]) {
    testWidgets(
      'malformed ${malformed.isEmpty ? 'empty' : '2049'} tail keeps head rows and retries same request cursor',
      (tester) async {
        final repository = PageNotifications();
        await tester.pumpWidget(host(repository));
        await settle(tester);
        repository.requests.single.result.complete(
          page([row1], nextCursor: 'valid-request-cursor'),
        );
        repository.countRequests.single.complete(41);
        await settle(tester);
        await tester.tap(find.text('Tải thêm'));
        await settle(tester);
        repository.requests.last.result.complete(
          page([row2], nextCursor: malformed),
        );
        await settle(tester);
        expect(find.text(row1.title), findsOneWidget);
        expect(find.text(row2.title), findsNothing);
        expect(find.text('Dữ liệu có thể chưa cập nhật'), findsOneWidget);
        expect(find.text('41'), findsOneWidget);
        expect(repository.requests, hasLength(2));
        final tile = tester.widget<NotificationTile>(
          find.byType(NotificationTile),
        );
        expect(tile.onTap, isNull);
        expect(tile.onMarkRead, isNull);
        await tester.tap(find.text('Tải thêm'));
        await settle(tester);
        expect(repository.requests.map((r) => r.query.cursor), [
          null,
          'valid-request-cursor',
          'valid-request-cursor',
        ]);
        repository.requests.last.result.complete(page([row2]));
        await settle(tester);
        expect(find.text(row1.title), findsOneWidget);
        expect(find.text(row2.title), findsOneWidget);
        expect(find.text('Tải thêm'), findsNothing);
        expect(find.text('41'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
