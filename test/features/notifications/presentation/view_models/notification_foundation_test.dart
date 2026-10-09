import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/core/state/read_retry_policy.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/notifications/data/models/notification_dto.dart';
import 'package:sports_store/features/notifications/domain/models/notification_page.dart';
import 'package:sports_store/features/notifications/domain/models/notification_query.dart';
import 'package:sports_store/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sports_store/features/notifications/presentation/view_models/notification_providers.dart';
import 'package:sports_store/features/notifications/presentation/view_models/notification_read_invalidation.dart';

import '../../../../fixtures/order_notification_fixtures.dart';

const scope = SessionScope(
  userId: fixtureCustomerId,
  role: 'customer',
  generation: 1,
);

class FakeNotifications implements NotificationRepository {
  final counts = <Completer<int>>[];
  final pages = <Completer<NotificationPage>>[];
  @override
  Future<NotificationPage> getPage(NotificationQuery query) {
    final result = Completer<NotificationPage>();
    pages.add(result);
    return result.future;
  }

  @override
  Future<int> getUnreadCount() {
    final result = Completer<int>();
    counts.add(result);
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Test fake only');
}

Future<void> settle(ProviderContainer container) async {
  await Future<void>.delayed(Duration.zero);
  await container.pump();
  await Future<void>.delayed(Duration.zero);
}

void main() {
  late ProviderContainer container;
  late FakeNotifications repository;
  setUp(() {
    repository = FakeNotifications();
    container = ProviderContainer(
      overrides: [
        featureSessionScopeProvider.overrideWithValue(scope),
        notificationRepositoryProvider.overrideWithValue(repository),
        readRetryPolicyProvider.overrideWithValue(
          const ReadRetryPolicy(backoffs: []),
        ),
      ],
    );
    container.listen(unreadCountFoundationProvider, (_, _) {});
  });
  tearDown(() => container.dispose());

  test('notification page has explicit accepted empty data', () async {
    final provider = notificationPageFoundationProvider(NotificationQuery());
    container.listen(provider, (_, _) {});
    await settle(container);
    repository.pages.single.complete(
      NotificationPage(
        items: [],
        nextCursor: null,
        unreadCount: null,
        asOf: null,
      ),
    );
    await settle(container);
    final state = container.read(provider).requireValue;
    expect(state.empty, isTrue);
    expect(state.isFresh, isTrue);
    expect(state.data!.unreadCount, isNull);
  });

  for (final malformed in ['other recipient', 'read row in unread filter']) {
    test('$malformed cannot enter the notification cache', () async {
      final provider = notificationPageFoundationProvider(
        NotificationQuery(filter: NotificationFilter.unread),
      );
      container.listen(provider, (_, _) {});
      await settle(container);
      final json = fixtureNotificationJson();
      if (malformed == 'other recipient') {
        json['recipient_id'] = fixtureOrderId;
      } else {
        json['read_at'] = '2026-10-08T03:41:00Z';
      }
      repository.pages.single.complete(
        NotificationPage(
          items: [NotificationDto.fromJson(json).domain],
          nextCursor: null,
          unreadCount: null,
          asOf: null,
        ),
      );
      await settle(container);
      final state = container.read(provider).requireValue;
      expect(state.data, isNull);
      expect(state.failure!.code, AppFailure.unsupportedData);
    });
  }

  test(
    'unresolved role waits without private reads or a false expiry error',
    () async {
      container.updateOverrides([
        featureSessionScopeProvider.overrideWithValue(
          const SessionScope.unresolved(),
        ),
        notificationRepositoryProvider.overrideWithValue(repository),
        readRetryPolicyProvider.overrideWithValue(
          const ReadRetryPolicy(backoffs: []),
        ),
      ]);
      await settle(container);
      final state = container.read(unreadCountFoundationProvider).requireValue;
      expect(state.data, isNull);
      expect(state.empty, isFalse);
      expect(state.failure, isNull);
      expect(state.isInitialLoading, isTrue);
    },
  );

  test('resolved logged-out session hides data and reports authentication required', () async {
    container.updateOverrides([
      featureSessionScopeProvider.overrideWithValue(
        const SessionScope(userId: null, role: null, generation: 2),
      ),
      notificationRepositoryProvider.overrideWithValue(repository),
      readRetryPolicyProvider.overrideWithValue(
        const ReadRetryPolicy(backoffs: []),
      ),
    ]);
    await settle(container);
    final state = container.read(unreadCountFoundationProvider).requireValue;
    expect(state.data, isNull);
    expect(state.isInitialLoading, isFalse);
    expect(state.failure!.code, AppFailure.unauthenticated);
  });

  test(
    'expiry from another resource clears displayed count immediately',
    () async {
      await settle(container);
      repository.counts.single.complete(55);
      await settle(container);
      container.read(epochCacheProvider).blockSession();
      final state = container.read(unreadCountFoundationProvider).requireValue;
      expect(state.data, isNull);
      expect(state.loading, isFalse);
      expect(state.failure!.code, AppFailure.unauthenticated);
      await settle(container);
      expect(repository.counts.length, 1);
    },
  );

  test(
    'account switch drops the old unread count while starting a new read',
    () async {
      await settle(container);
      container.updateOverrides([
        featureSessionScopeProvider.overrideWithValue(
          const SessionScope(
            userId: fixtureOrderId,
            role: 'manager',
            generation: 2,
          ),
        ),
        notificationRepositoryProvider.overrideWithValue(repository),
        readRetryPolicyProvider.overrideWithValue(
          const ReadRetryPolicy(backoffs: []),
        ),
      ]);
      await settle(container);
      expect(repository.counts.length, 2);
      expect(
        container.read(unreadCountFoundationProvider).requireValue.data,
        isNull,
      );
      repository.counts.first.complete(55);
      await settle(container);
      expect(
        container.read(unreadCountFoundationProvider).requireValue.data,
        isNull,
      );
      repository.counts.last.complete(11);
      await settle(container);
      expect(
        container.read(unreadCountFoundationProvider).requireValue.data,
        11,
      );
    },
  );

  for (final code in [
    AppFailure.forbiddenOrUnavailable,
    AppFailure.invalidArgument,
    AppFailure.unsupportedData,
    AppFailure.externalDependencyUnavailable,
  ]) {
    test('$code is never automatically retried', () async {
      await settle(container);
      repository.counts.single.completeError(AppFailure(code: code));
      await settle(container);
      expect(repository.counts.length, 1);
      expect(
        container
            .read(unreadCountFoundationProvider)
            .requireValue
            .failure!
            .code,
        code,
      );
    });
  }

  test(
    'T17-26: read ack rejects old count and refetches exact whole count',
    () async {
      await settle(container);
      final row = NotificationDto.fromJson(
        fixtureNotificationJson(readAt: '2026-10-08T03:41:00Z'),
      ).domain;
      final ack = container.read(notificationReadInvalidationProvider);
      expect(
        ack.acknowledge(
          row,
          expectedNotificationId: fixtureNotificationId,
          submittedScope: scope,
        ),
        isTrue,
      );
      repository.counts.first.complete(55);
      await settle(container);
      expect(
        container.read(unreadCountFoundationProvider).requireValue.data,
        isNull,
      );
      expect(repository.counts.length, 2);
      repository.counts.last.complete(54);
      await settle(container);
      expect(
        container.read(unreadCountFoundationProvider).requireValue.data,
        54,
      );
      // No guessed decrement, the returned server count is authoritative.
    },
  );

  test('unconfirmed read and other-session ack never decrement or invalidate count', () async {
    await settle(container);
    repository.counts.single.complete(55);
    await settle(container);
    final ack = container.read(notificationReadInvalidationProvider);
    final unread = NotificationDto.fromJson(fixtureNotificationJson()).domain;
    expect(
      ack.acknowledge(
        unread,
        expectedNotificationId: fixtureNotificationId,
        submittedScope: scope,
      ),
      isFalse,
    );
    final read = NotificationDto.fromJson(
      fixtureNotificationJson(readAt: '2026-10-08T03:41:00Z'),
    ).domain;
    expect(
      ack.acknowledge(
        read,
        expectedNotificationId: fixtureNotificationId,
        submittedScope: const SessionScope(
          userId: 'B',
          role: 'manager',
          generation: 2,
        ),
      ),
      isFalse,
    );
    expect(container.read(unreadCountFoundationProvider).requireValue.data, 55);
    expect(repository.counts.length, 1);
  });

  test('negative exact count is unsupported, never zero success', () async {
    await settle(container);
    repository.counts.single.complete(-1);
    await settle(container);
    final state = container.read(unreadCountFoundationProvider).requireValue;
    expect(state.data, isNull);
    expect(state.failure!.code, AppFailure.unsupportedData);
  });

  test(
    'unexpected adapter errors are not misclassified as retryable transport',
    () async {
      await settle(container);
      repository.counts.single.completeError(
        StateError('malformed adapter result'),
      );
      await settle(container);
      final state = container.read(unreadCountFoundationProvider).requireValue;
      expect(state.failure!.code, AppFailure.unsupportedData);
      expect(state.data, isNull);
      expect(repository.counts.length, 1);
    },
  );

  test(
    'network reads retry twice, auth expiry never retries and hides cache',
    () async {
      // Configure retries before the first read, avoiding an orphaned read from
      // the default policy racing the rebuilt provider.
      container.dispose();
      repository = FakeNotifications();
      final waits = <Duration>[];
      container = ProviderContainer(
        overrides: [
          featureSessionScopeProvider.overrideWithValue(scope),
          notificationRepositoryProvider.overrideWithValue(repository),
          readRetryPolicyProvider.overrideWithValue(
            ReadRetryPolicy(
              wait: (duration) async {
                waits.add(duration);
              },
            ),
          ),
        ],
      );
      container.listen(unreadCountFoundationProvider, (_, _) {});
      await settle(container);
      repository.counts.last.completeError(
        const AppFailure(code: AppFailure.network),
      );
      await settle(container);
      repository.counts.last.completeError(
        const AppFailure(code: AppFailure.network),
      );
      await settle(container);
      repository.counts.last.complete(0);
      await settle(container);
      expect(repository.counts.length, 3);
      expect(waits, [
        const Duration(milliseconds: 500),
        const Duration(milliseconds: 1500),
      ]);
      expect(
        container.read(unreadCountFoundationProvider).requireValue.empty,
        isTrue,
      );
      final refresh = container
          .read(unreadCountFoundationProvider.notifier)
          .refresh();
      await settle(container);
      repository.counts.last.completeError(
        const AppFailure(code: AppFailure.unauthenticated),
      );
      await refresh;
      final state = container.read(unreadCountFoundationProvider).requireValue;
      expect(state.data, isNull);
      expect(state.failure!.code, AppFailure.unauthenticated);
      expect(repository.counts.length, 4);
      expect(container.read(epochCacheProvider).canRead, isFalse);
    },
  );

  test(
    'exhausted transport retries retain stale data and stop at two retries',
    () async {
      container.dispose();
      repository = FakeNotifications();
      container = ProviderContainer(
        overrides: [
          featureSessionScopeProvider.overrideWithValue(scope),
          notificationRepositoryProvider.overrideWithValue(repository),
          readRetryPolicyProvider.overrideWithValue(
            ReadRetryPolicy(wait: (_) async {}),
          ),
        ],
      );
      container.listen(unreadCountFoundationProvider, (_, _) {});
      await settle(container);
      repository.counts.single.complete(55);
      await settle(container);
      final refresh = container
          .read(unreadCountFoundationProvider.notifier)
          .refresh();
      for (var attempt = 0; attempt < 3; attempt++) {
        await settle(container);
        repository.counts.last.completeError(
          const AppFailure(code: AppFailure.network),
        );
      }
      await refresh;
      final state = container.read(unreadCountFoundationProvider).requireValue;
      expect(
        repository.counts.length,
        4,
      ); // initial read plus three refresh attempts
      expect(state.data, 55);
      expect(state.stale, isTrue);
      expect(state.isFresh, isFalse);
      expect(state.failure!.code, AppFailure.network);
    },
  );
}
