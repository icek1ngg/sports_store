import 'mh17_characterization_support.dart';

class DeferredPageResolver implements NotificationTargetResolver {
  final result = Completer<NotificationTargetDecision>();
  final calls = <String>[];

  @override
  Future<NotificationTargetDecision> resolve(String id) {
    calls.add(id);
    return result.future;
  }
}

void main() {
  for (final scenario in ['unknown', 'resolver absent', 'target unavailable']) {
    testWidgets('$scenario keeps the page and never reaches navigation', (
      tester,
    ) async {
      final item = NotificationDto.fromJson({
        ...row2.toMap(),
        'subject_type': scenario == 'unknown' ? 'future_kind' : 'order',
        'body': 'Nội dung plain text: https://example.invalid/private',
      }).domain;
      final resolver = PageTargetResolver(
        scenario == 'target unavailable'
            ? const NotificationTargetDecision.unavailable()
            : availableOrderDecision,
      );
      final repository = PageNotifications();
      var navigations = 0, reads = 0;
      repository.markReadHandler = (_) async {
        reads++;
        return row1Read;
      };
      await tester.pumpWidget(
        host(
          repository,
          resolver: scenario == 'resolver absent' ? null : resolver,
          onNavigate: (_) async {
            navigations++;
            return true;
          },
        ),
      );
      await settle(tester);
      repository.requests.single.result.complete(page([item]));
      repository.countRequests.single.complete(0);
      await settle(tester);
      await tester.tap(find.text(item.title));
      await settle(tester);
      expect(navigations, 0);
      expect(reads, 0);
      expect(
        resolver.calls,
        scenario == 'target unavailable' ? [item.id] : isEmpty,
      );
      expect(find.byType(NotificationsPage), findsOneWidget);
      expect(find.text(item.body), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final disposeOwner in [true, false]) {
    testWidgets(
      'pending resolve cannot navigate after ${disposeOwner ? 'owner disposal' : 'same-user scope generation change'}',
      (tester) async {
        var scope = pageScope;
        final repository = PageNotifications();
        final resolver = DeferredPageResolver();
        var navigations = 0;
        final container = ProviderContainer(
          overrides: [
            featureSessionScopeProvider.overrideWith((ref) => scope),
            notificationRepositoryProvider.overrideWithValue(repository),
            notificationTargetResolverProvider.overrideWithValue(resolver),
            readRetryPolicyProvider.overrideWithValue(
              const ReadRetryPolicy(backoffs: []),
            ),
          ],
        );
        addTearDown(container.dispose);
        await mountScopedPage(
          tester,
          container,
          onNavigate: (_) async {
            navigations++;
            return true;
          },
        );
        repository.requests.single.result.complete(page([row2]));
        repository.countRequests.single.complete(41);
        await settle(tester);
        await tester.tap(find.text(row2.title));
        await settle(tester);
        expect(resolver.calls, [row2.id]);
        if (!disposeOwner) {
          scope = SessionScope(
            userId: scope.userId,
            role: scope.role,
            generation: 2,
          );
          container.invalidate(featureSessionScopeProvider);
          await settle(tester);
          expect(find.text(row2.title), findsNothing);
          expect(find.text('41'), findsNothing);
        } else {
          await tester.pumpWidget(const SizedBox.shrink());
        }
        for (final request in repository.requests) {
          if (!request.result.isCompleted) request.result.complete(page([]));
        }
        for (final count in repository.countRequests) {
          if (!count.isCompleted) count.complete(0);
        }
        await settle(tester);
        if (!disposeOwner) {
          expect(find.byType(NotificationsPage), findsOneWidget);
        }
        resolver.result.complete(availableOrderDecision);
        await settle(tester);
        expect(navigations, 0);
        if (!disposeOwner) {
          expect(find.byType(NotificationsPage), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }
}
