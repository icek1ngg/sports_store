import 'mh17_page_test_support.dart';

void main() {
  testWidgets('cursor pagination appends locally and filter resets cursor', (
    tester,
  ) async {
    final repository = PageNotifications();
    await tester.pumpWidget(host(repository));
    await settle(tester);
    repository.requests.single.result.complete(
      page([row1], nextCursor: 'cursor-1'),
    );
    repository.countRequests.single.complete(1);
    await settle(tester);
    expect(find.text('Tải thêm'), findsOneWidget);

    await tester.tap(find.text('Tải thêm'));
    await settle(tester);
    expect(repository.requests.last.query.cursor, 'cursor-1');
    repository.requests.last.result.complete(
      page([row2], nextCursor: 'cursor-2'),
    );
    await settle(tester);
    expect(find.text('Thông báo trang một'), findsOneWidget);
    expect(find.text('Thông báo trang hai'), findsOneWidget);

    await tester.tap(find.text('Tải thêm'));
    await settle(tester);
    expect(repository.requests.last.query.cursor, 'cursor-2');
    repository.requests.last.result.complete(
      page([longRow], nextCursor: 'cursor-2'),
    );
    await settle(tester);
    expect(find.text('Thông báo trang một'), findsOneWidget);
    expect(find.text('Thông báo trang hai'), findsOneWidget);
    expect(find.text(longRow.title), findsOneWidget);
    expect(find.text('Tải thêm'), findsNothing);

    await tester.tap(find.text('Chưa đọc'));
    await settle(tester);
    expect(repository.requests.last.query.cursor, isNull);
    repository.requests.last.result.complete(page([row1]));
    await settle(tester);
  });

  testWidgets('next page failure keeps rows and retry loads the same cursor', (
    tester,
  ) async {
    final repository = PageNotifications();
    await tester.pumpWidget(host(repository));
    await settle(tester);
    repository.requests.single.result.complete(
      page([row1], nextCursor: 'cursor-1'),
    );
    repository.countRequests.single.complete(1);
    await settle(tester);

    await tester.tap(find.text('Tải thêm'));
    await settle(tester);
    final failedRequest = repository.requests.last;
    expect(failedRequest.query.cursor, 'cursor-1');
    failedRequest.result.completeError(
      const AppFailure(code: AppFailure.network),
    );
    await settle(tester);
    expect(find.text('Thông báo trang một'), findsOneWidget);
    expect(find.text('Tải thêm'), findsOneWidget);

    await tester.tap(find.text('Tải thêm'));
    await settle(tester);
    final retryRequest = repository.requests.last;
    expect(retryRequest.query.cursor, 'cursor-1');
    retryRequest.result.complete(page([row2], nextCursor: 'cursor-2'));
    await settle(tester);
    expect(find.text('Thông báo trang hai'), findsOneWidget);
  });

  testWidgets('polling pagination refreshes the canonical head page', (
    tester,
  ) async {
    final repository = PageNotifications();
    await tester.pumpWidget(host(repository, enablePolling: true));
    await settle(tester);
    repository.requests.single.result.complete(
      page([row1], nextCursor: 'cursor-1'),
    );
    repository.countRequests.single.complete(1);
    await settle(tester);

    await tester.tap(find.text('Tải thêm'));
    await settle(tester);
    repository.requests.last.result.complete(
      page([row2], nextCursor: 'cursor-2'),
    );
    await settle(tester);
    expect(find.text(row2.title), findsOneWidget);

    final requestStart = repository.requests.length;
    final countStart = repository.countRequests.length;
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(repository.requests.length, requestStart + 1);
    expect(repository.requests.last.query.cursor, isNull);
    repository.requests.last.result.complete(
      page([row1], nextCursor: 'cursor-1'),
    );
    for (final countRequest in repository.countRequests.skip(countStart)) {
      if (!countRequest.isCompleted) countRequest.complete(1);
    }
    await settle(tester);
    expect(find.text(row1.title), findsOneWidget);
    expect(find.text(row2.title), findsNothing);
    expect(
      repository.requests.every((request) => request.result.isCompleted),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
    expect(repository.requests.length, requestStart + 1);
  });

  testWidgets(
    'poll accepts new head rows, exact count and a new cursor chain',
    (tester) async {
      final repository = PageNotifications();
      await tester.pumpWidget(host(repository, enablePolling: true));
      await settle(tester);
      repository.requests.single.result.complete(
        page([row1], nextCursor: 'old-cursor'),
      );
      repository.countRequests.single.complete(55);
      await settle(tester);
      expect(find.text('55'), findsOneWidget);
      await tester.tap(find.text('Tải thêm'));
      await settle(tester);
      repository.requests.last.result.complete(page([row2]));
      await settle(tester);
      final beforePoll = repository.requests.length;
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(repository.requests.length, beforePoll + 1);
      // A busy head/count query must not queue another periodic read.
      await tester.pump(const Duration(seconds: 3));
      expect(repository.requests.length, beforePoll + 1);
      expect(repository.countRequests.length, 2);
      repository.requests.last.result.complete(
        page([newRow, row1], nextCursor: 'new-cursor'),
      );
      repository.countRequests.last.complete(56);
      await settle(tester);
      expect(find.text(newRow.title), findsOneWidget);
      expect(find.text(row2.title), findsNothing);
      expect(find.text('56'), findsOneWidget);
      await tester.tap(find.text('Tải thêm'));
      await settle(tester);
      expect(repository.requests.last.query.cursor, 'new-cursor');
      repository.requests.last.result.complete(page([row1, row2]));
      await settle(tester);
      expect(find.text(row1.title), findsOneWidget);
      expect(find.text(row2.title), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
      expect(repository.requests.length, beforePoll + 2);
    },
  );

  testWidgets('filter change drops a late cursor response', (tester) async {
    final repository = PageNotifications();
    await tester.pumpWidget(host(repository));
    await settle(tester);
    repository.requests.single.result.complete(
      page([row1], nextCursor: 'all-cursor'),
    );
    repository.countRequests.single.complete(41);
    await settle(tester);
    await tester.tap(find.text('Tải thêm'));
    await settle(tester);
    final oldPage = repository.requests.last;
    await tester.tap(find.text('Chưa đọc'));
    await settle(tester);
    final newPage = repository.requests.last;
    expect(newPage.query.filter, NotificationFilter.unread);
    expect(newPage.query.cursor, isNull);
    newPage.result.complete(page([longRow]));
    await settle(tester);
    oldPage.result.complete(page([row2], nextCursor: 'obsolete-cursor'));
    await settle(tester);
    expect(find.text(longRow.title), findsOneWidget);
    expect(find.text(row2.title), findsNothing);
    expect(find.text('Tải thêm'), findsNothing);
    expect(find.text('41'), findsOneWidget);
  });

  testWidgets('expired cursor refetches the head instead of retrying it', (
    tester,
  ) async {
    final repository = PageNotifications();
    await tester.pumpWidget(host(repository));
    await settle(tester);
    repository.requests.single.result.complete(
      page([row1], nextCursor: 'expired'),
    );
    repository.countRequests.single.complete(1);
    await settle(tester);
    await tester.tap(find.text('Tải thêm'));
    await settle(tester);
    repository.requests.last.result.completeError(
      const AppFailure(code: AppFailure.invalidCursor),
    );
    await settle(tester);
    expect(repository.requests.length, 3);
    expect(repository.requests.last.query.cursor, isNull);
    repository.requests.last.result.complete(
      page([longRow], nextCursor: 'fresh'),
    );
    repository.countRequests.last.complete(2);
    await settle(tester);
    expect(find.text(row1.title), findsNothing);
    expect(find.text(longRow.title), findsOneWidget);
  });
}
