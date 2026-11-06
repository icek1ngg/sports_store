import 'mh17_characterization_support.dart';

void main() {
  for (final role in ['customer', 'manager', 'shipper']) {
    testWidgets(
      '$role page accepts own row and never renders a foreign recipient projection',
      (tester) async {
        final scope = SessionScope(
          userId: role == 'customer'
              ? fixtureCustomerId
              : role == 'manager'
              ? fixtureManagerId
              : '20000000-0000-4000-8000-000000000003',
          role: role,
          generation: 1,
        );
        final own = scopedNotification(scope, 31);
        final foreign = NotificationDto.fromJson({
          ...own.toMap(),
          'id': '50000000-0000-4000-8000-000000000099',
          'recipient_id': '20000000-0000-4000-8000-000000000099',
          'title': 'Thông báo không thuộc tài khoản',
          'body': 'Nội dung tài khoản khác',
        }).domain;
        final repository = PageNotifications();
        final container = ProviderContainer(
          overrides: [
            featureSessionScopeProvider.overrideWithValue(scope),
            notificationRepositoryProvider.overrideWithValue(repository),
            readRetryPolicyProvider.overrideWithValue(
              const ReadRetryPolicy(backoffs: []),
            ),
          ],
        );
        addTearDown(container.dispose);
        await mountScopedPage(tester, container);
        repository.requests.single.result.complete(page([own]));
        repository.countRequests.single.complete(41);
        await settle(tester);
        expect(find.text(own.title), findsOneWidget);
        expect(find.text('41'), findsOneWidget);
        await tester.tap(find.byTooltip('Làm mới'));
        await settle(tester);
        repository.requests.last.result.complete(page([foreign]));
        repository.countRequests.last.complete(41);
        await settle(tester);
        expect(find.text(foreign.title), findsNothing);
        expect(find.text(foreign.body), findsNothing);
        expect(
          tester
              .widgetList<NotificationTile>(find.byType(NotificationTile))
              .every((tile) => tile.notification.recipientId == scope.userId),
          isTrue,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'late A count cannot replace B badge after the first-frame account clear',
    (tester) async {
      var scope = pageScope;
      const scopeB = SessionScope(
        userId: '20000000-0000-4000-8000-000000000099',
        role: 'customer',
        generation: 2,
      );
      final ownA = scopedNotification(scope, 41),
          ownB = scopedNotification(scopeB, 42);
      final repository = PageNotifications();
      final container = ProviderContainer(
        overrides: [
          featureSessionScopeProvider.overrideWith((ref) => scope),
          notificationRepositoryProvider.overrideWithValue(repository),
          readRetryPolicyProvider.overrideWithValue(
            const ReadRetryPolicy(backoffs: []),
          ),
        ],
      );
      addTearDown(container.dispose);
      await mountScopedPage(tester, container);
      repository.requests.single.result.complete(page([ownA]));
      repository.countRequests.single.complete(41);
      await settle(tester);
      expect(find.text(ownA.title), findsOneWidget);
      final oldRefresh = container
          .read(unreadCountFoundationProvider.notifier)
          .refresh();
      await settle(tester);
      final oldCount = repository.countRequests.last;
      scope = scopeB;
      container.invalidate(featureSessionScopeProvider);
      await tester.pump();
      expect(find.text(ownA.title), findsNothing);
      expect(find.text('41'), findsNothing);
      await settle(tester);
      expect(repository.countRequests.length, greaterThanOrEqualTo(3));
      expect(repository.countRequests.last, isNot(same(oldCount)));
      repository.requests.last.result.complete(page([ownB]));
      repository.countRequests.last.complete(3);
      await settle(tester);
      expect(find.text(ownB.title), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      oldCount.complete(99);
      await oldRefresh;
      await settle(tester);
      expect(find.text('99'), findsNothing);
      expect(find.text('3'), findsOneWidget);
      expect(find.text(ownA.title), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
