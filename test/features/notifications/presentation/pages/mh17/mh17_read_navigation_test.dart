import 'mh17_page_test_support.dart';

void main() {
  testWidgets('mark read keeps unread row and badge until canonical refresh', (
    tester,
  ) async {
    final repository = PageNotifications();
    final read = Completer<NotificationItem>();
    repository.markReadHandler = (_) => read.future;
    await tester.pumpWidget(host(repository));
    await settle(tester);
    repository.requests.single.result.complete(page([row1], unreadCount: 1));
    repository.countRequests.single.complete(1);
    await settle(tester);

    await tester.tap(find.text('Đánh dấu đã đọc'));
    await settle(tester);
    expect(find.text('Đánh dấu đã đọc'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    read.complete(row1Read);
    for (var i = 0; i < 5 && repository.requests.length < 2; i++) {
      await tester.pump();
    }
    expect(repository.requests.length, greaterThanOrEqualTo(2));
    repository.requests.last.result.complete(page([row1Read], unreadCount: 0));
    repository.countRequests.last.complete(0);
    await settle(tester);
    expect(find.text('Đánh dấu đã đọc'), findsNothing);
    expect(find.text('0'), findsNothing);
  });

  testWidgets(
    'unread filter removes an acknowledged row only after canonical reload',
    (tester) async {
      final repository = PageNotifications();
      final read = Completer<NotificationItem>();
      repository.markReadHandler = (_) => read.future;
      await tester.pumpWidget(host(repository));
      await settle(tester);
      repository.requests.single.result.complete(page([row1]));
      repository.countRequests.single.complete(41);
      await settle(tester);
      await tester.tap(find.text('Chưa đọc'));
      await settle(tester);
      repository.requests.last.result.complete(page([row1]));
      await settle(tester);
      await tester.tap(find.text('Đánh dấu đã đọc'));
      await settle(tester);
      expect(find.text(row1.title), findsOneWidget);
      expect(find.text('41'), findsOneWidget);
      read.complete(row1Read);
      await settle(tester);
      expect(repository.requests.last.query.filter, NotificationFilter.unread);
      expect(repository.requests.last.query.cursor, isNull);
      expect(find.text(row1.title), findsOneWidget);
      repository.requests.last.result.complete(page([]));
      repository.countRequests.last.complete(40);
      await settle(tester);
      expect(find.text(row1.title), findsNothing);
      expect(find.text('40'), findsOneWidget);
      expect(find.text('Không có thông báo chưa đọc'), findsOneWidget);
    },
  );

  testWidgets('authorized navigation remains independent from read failure', (
    tester,
  ) async {
    final repository = PageNotifications();
    repository.markReadHandler = (_) => Future<NotificationItem>.error(
      const AppFailure(code: AppFailure.network),
    );
    final resolver = PageTargetResolver(
      const NotificationTargetDecision(
        available: true,
        screen: NotificationTargetScreen.customerOrder,
        entityId: fixtureOrderId,
        mode: NotificationTargetMode.order,
      ),
    );
    var navigated = false;
    await tester.pumpWidget(
      host(
        repository,
        resolver: resolver,
        onNavigate: (decision) async {
          navigated = decision.available;
          return true;
        },
      ),
    );
    await settle(tester);
    repository.requests.single.result.complete(page([row1]));
    repository.countRequests.single.complete(1);
    await settle(tester);
    await tester.tap(find.text(row1.title));
    await settle(tester);
    expect(navigated, isTrue);
    expect(resolver.calls, [row1.id]);
  });

  testWidgets('missing navigation callback stays explicitly unavailable', (
    tester,
  ) async {
    final repository = PageNotifications();
    final resolver = PageTargetResolver(
      const NotificationTargetDecision(
        available: true,
        screen: NotificationTargetScreen.customerOrder,
        entityId: fixtureOrderId,
        mode: NotificationTargetMode.order,
      ),
    );
    await tester.pumpWidget(host(repository, resolver: resolver));
    await settle(tester);
    repository.requests.single.result.complete(page([row2]));
    repository.countRequests.single.complete(0);
    await settle(tester);
    await tester.tap(find.text(row2.title));
    await settle(tester);
    expect(find.text('Mục tiêu thông báo hiện chưa khả dụng.'), findsOneWidget);
    expect(resolver.calls, [row2.id]);
  });
}
