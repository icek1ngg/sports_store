import 'mh17/mh17_page_test_support.dart';

void main() {
  testWidgets(
    'captured tile callbacks recheck invalidated cache before a rebuild',
    (tester) async {
      final repository = PageNotifications();
      var markReadCalls = 0;
      repository.markReadHandler = (id) async {
        markReadCalls++;
        return row1;
      };
      await tester.pumpWidget(host(repository));
      await settle(tester);
      repository.requests.single.result.complete(page([row1]));
      repository.countRequests.single.complete(124);
      await settle(tester);
      final tile = tester.widget<NotificationTile>(
        find.byType(NotificationTile).first,
      );
      expect(tile.onTap, isNotNull);
      expect(tile.onMarkRead, isNotNull);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NotificationsPage)),
      );
      container
          .read(epochCacheProvider)
          .invalidatePrefix('notifications/list/');
      tile.onTap!();
      tile.onMarkRead!();
      expect(markReadCalls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      for (final request in repository.requests.where(
        (request) => !request.result.isCompleted,
      )) {
        request.result.complete(page([]));
      }
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  for (final denyCount in [true, false]) {
    testWidgets(
      '${denyCount ? 'count' : 'list'} denial hides the entire inbox until both fresh reads recover',
      (tester) async {
        final repository = PageNotifications();
        await tester.pumpWidget(host(repository));
        await settle(tester);
        repository.requests.single.result.complete(page([row1]));
        repository.countRequests.single.complete(41);
        await settle(tester);
        await tester.tap(find.byTooltip('Làm mới'));
        await settle(tester);
        if (denyCount) {
          repository.requests.last.result.complete(page([row1]));
          repository.countRequests.last.completeError(
            const AppFailure(code: AppFailure.forbiddenOrUnavailable),
          );
        } else {
          repository.requests.last.result.completeError(
            const AppFailure(code: AppFailure.forbiddenOrUnavailable),
          );
          repository.countRequests.last.complete(41);
        }
        await settle(tester);
        await settle(tester);
        expect(find.byType(SessionUnavailableState), findsOneWidget);
        expect(find.text(row1.title), findsNothing);
        expect(find.text('41'), findsNothing);
        expect(find.text('Đánh dấu đã đọc'), findsNothing);
        // A successful page alone cannot override a denied/pending count.
        await tester.tap(find.byTooltip('Làm mới'));
        await settle(tester);
        repository.requests.last.result.complete(page([newRow]));
        await settle(tester);
        expect(find.text(newRow.title), findsNothing);
        expect(find.byType(SessionUnavailableState), findsOneWidget);
        repository.countRequests.last.complete(42);
        await settle(tester);
        expect(find.text(newRow.title), findsOneWidget);
        expect(find.text('42'), findsOneWidget);
        expect(find.byType(SessionUnavailableState), findsNothing);
      },
    );
  }

  testWidgets('loads all/unread filters and shows server count', (
    tester,
  ) async {
    final repository = PageNotifications();
    await tester.pumpWidget(host(repository));
    await settle(tester);
    expect(repository.requests.single.query.filter, NotificationFilter.all);
    repository.requests.single.result.complete(
      page([row1, row2], unreadCount: 1),
    );
    repository.countRequests.single.complete(1);
    await settle(tester);
    expect(find.text('Thông báo trang một'), findsOneWidget);
    expect(find.text('Thông báo trang hai'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.text('Chưa đọc'));
    await settle(tester);
    final unreadRequest = repository.requests.last;
    expect(unreadRequest.query.filter, NotificationFilter.unread);
    unreadRequest.result.complete(page([row1], unreadCount: 1));
    await settle(tester);
    expect(find.text('Thông báo trang một'), findsOneWidget);
    expect(find.text('Thông báo trang hai'), findsNothing);
  });

  testWidgets('does not invent a badge while unread count is unknown', (
    tester,
  ) async {
    final repository = PageNotifications();
    await tester.pumpWidget(host(repository));
    await settle(tester);
    repository.requests.single.result.complete(page([row1]));
    await settle(tester);
    expect(find.text(row1.title), findsOneWidget);
    expect(find.text('1'), findsNothing);
    repository.countRequests.single.complete(0);
    await settle(tester);
  });

  testWidgets(
    'dispose during a poll ignores late results and stops future polling',
    (tester) async {
      final repository = PageNotifications();
      await tester.pumpWidget(host(repository, enablePolling: true));
      await settle(tester);
      repository.requests.single.result.complete(page([row1]));
      repository.countRequests.single.complete(1);
      await settle(tester);
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(repository.requests.length, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      repository.requests.last.result.complete(page([longRow]));
      repository.countRequests.last.complete(99);
      await settle(tester);
      await tester.pump(const Duration(seconds: 7));
      expect(repository.requests.length, 2);
      expect(repository.countRequests.length, 2);
      expect(find.text(longRow.title), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stale refresh keeps rows readable and disables read mutation', (
    tester,
  ) async {
    final repository = PageNotifications();
    await tester.pumpWidget(host(repository));
    await settle(tester);
    repository.requests.single.result.complete(page([row1], unreadCount: 1));
    repository.countRequests.single.complete(1);
    await settle(tester);
    expect(find.text('Đánh dấu đã đọc'), findsOneWidget);

    final countRequestStart = repository.countRequests.length;
    await tester.tap(find.byTooltip('Làm mới'));
    await settle(tester);
    final refresh = repository.requests.last;
    refresh.result.completeError(const AppFailure(code: AppFailure.network));
    await settle(tester);
    expect(find.text('Thông báo trang một'), findsOneWidget);
    expect(find.text('Dữ liệu có thể chưa cập nhật'), findsWidgets);
    expect(find.text('Đánh dấu đã đọc'), findsNothing);
    for (
      var i = 0;
      i < 5 && repository.countRequests.length == countRequestStart;
      i++
    ) {
      await tester.pump();
    }
    for (final countRequest in repository.countRequests.skip(
      countRequestStart,
    )) {
      if (!countRequest.isCompleted) countRequest.complete(1);
    }
    if (repository.countRequests.length > countRequestStart) {
      await settle(tester);
    }
  });

  testWidgets('long notification text lays out at 320 dp', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = PageNotifications();
    await tester.pumpWidget(host(repository, textScale: 2));
    await settle(tester);
    repository.requests.single.result.complete(page([longRow]));
    repository.countRequests.single.complete(1);
    await settle(tester);
    expect(find.text(longRow.title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown role and unresolved session fail closed', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          featureSessionScopeProvider.overrideWithValue(
            const SessionScope(
              userId: fixtureCustomerId,
              role: 'auditor',
              generation: 1,
            ),
          ),
        ],
        child: const MaterialApp(home: NotificationsPage(enablePolling: false)),
      ),
    );
    await settle(tester);
    expect(find.text('Không thể truy cập dữ liệu'), findsOneWidget);
  });
}
