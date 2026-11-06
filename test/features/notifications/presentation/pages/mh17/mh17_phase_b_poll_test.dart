import 'mh17_page_test_support.dart';

import 'package:sports_store/shared/widgets/foreground_refresh.dart';

void main() {
  Future<void> mountPoll(
    WidgetTester tester,
    PageNotifications repository, {
    bool countFails = false,
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
    await tester.pumpWidget(host(repository, enablePolling: true));
    await settle(tester);
    repository.requests.single.result.complete(
      page([row1], nextCursor: 'tail'),
    );
    if (countFails) {
      repository.countRequests.single.completeError(
        const AppFailure(code: AppFailure.network),
      );
    } else {
      repository.countRequests.single.complete(41);
    }
    await settle(tester);
  }

  testWidgets(
    'count-only poll preserves failed tail intent and does not request a head',
    (tester) async {
      final repository = PageNotifications();
      await mountPoll(tester, repository);
      await tester.tap(find.text('Tải thêm'));
      await settle(tester);
      repository.requests.last.result.completeError(
        const AppFailure(code: AppFailure.network),
      );
      await settle(tester);
      final reads = repository.requests.length;
      final counts = repository.countRequests.length;
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(repository.requests.length, reads);
      expect(repository.countRequests.length, counts + 1);
      repository.countRequests.last.complete(42);
      await settle(tester);
      expect(find.text(row1.title), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      await tester.tap(find.text('Tải thêm'));
      await settle(tester);
      expect(repository.requests.last.query.cursor, 'tail');
      repository.requests.last.result.complete(page([row2]));
      await settle(tester);
      expect(find.text(row1.title), findsOneWidget);
      expect(find.text(row2.title), findsOneWidget);
    },
  );

  testWidgets('head-only poll never retries an ineligible count resource', (
    tester,
  ) async {
    final repository = PageNotifications();
    await mountPoll(tester, repository, countFails: true);
    final reads = repository.requests.length;
    final counts = repository.countRequests.length;
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
    expect(repository.requests.length, reads + 1);
    expect(repository.requests.last.query.cursor, isNull);
    expect(repository.countRequests.length, counts);
    repository.requests.last.result.complete(page([newRow]));
    await settle(tester);
    expect(find.text(newRow.title), findsOneWidget);
    expect(repository.countRequests.length, counts);
  });

  testWidgets(
    'captured poll after filter switch cannot refresh the obsolete query',
    (tester) async {
      final repository = PageNotifications();
      await mountPoll(tester, repository);
      final oldPoll = tester
          .widget<ForegroundRefresh>(find.byType(ForegroundRefresh))
          .onRefresh;
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      final oldHead = repository.requests.last;
      await tester.tap(find.text('Chưa đọc'));
      await settle(tester);
      final unreadHead = repository.requests.last;
      expect(unreadHead.query.filter, NotificationFilter.unread);
      expect(unreadHead.query.cursor, isNull);
      oldHead.result.complete(page([newRow]));
      unreadHead.result.complete(page([row1]));
      repository.countRequests.last.complete(42);
      await settle(tester);
      final reads = repository.requests.length;
      final counts = repository.countRequests.length;
      oldPoll();
      await settle(tester);
      expect(repository.requests.length, reads);
      expect(repository.countRequests.length, counts);
      expect(find.text(row1.title), findsOneWidget);
      expect(find.text(newRow.title), findsNothing);
    },
  );
}
