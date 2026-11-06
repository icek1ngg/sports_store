import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/core/state/read_retry_policy.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/notifications/data/models/notification_dto.dart';
import 'package:sports_store/features/notifications/domain/models/notification_item.dart';
import 'package:sports_store/features/notifications/domain/models/notification_page.dart';
import 'package:sports_store/features/notifications/domain/models/notification_query.dart';
import 'package:sports_store/features/notifications/domain/models/notification_target.dart';
import 'package:sports_store/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sports_store/features/notifications/presentation/view_models/notification_interaction_view_model.dart';
import 'package:sports_store/features/notifications/presentation/view_models/notification_providers.dart';

import '../../../../fixtures/order_notification_fixtures.dart';

const customerScope = SessionScope(
  userId: fixtureCustomerId,
  role: 'customer',
  generation: 1,
);

NotificationItem notification({
  String subjectType = 'order',
  DateTime? readAt,
}) {
  return NotificationDto.fromJson(
    fixtureNotificationJson(
      subjectType: subjectType,
      readAt: readAt?.toIso8601String(),
    ),
  ).domain;
}

class InteractionNotifications implements NotificationRepository {
  Future<NotificationItem> Function(String id)? readHandler;
  var markReadCalls = 0;

  @override
  Future<NotificationPage> getPage(NotificationQuery query) async {
    return NotificationPage(
      items: const [],
      nextCursor: null,
      unreadCount: 0,
      asOf: null,
    );
  }

  @override
  Future<int> getUnreadCount() async => 0;

  @override
  Future<NotificationItem> markRead(String notificationId) {
    markReadCalls++;
    final handler = readHandler;
    if (handler == null) {
      return Future<NotificationItem>.error(StateError('missing handler'));
    }
    return handler(notificationId);
  }
}

class Resolver implements NotificationTargetResolver {
  Resolver(this.decision);

  final NotificationTargetDecision decision;
  final calls = <String>[];

  @override
  Future<NotificationTargetDecision> resolve(String notificationId) async {
    calls.add(notificationId);
    return decision;
  }
}

class PendingResolver implements NotificationTargetResolver {
  final result = Completer<NotificationTargetDecision>();

  @override
  Future<NotificationTargetDecision> resolve(String notificationId) =>
      result.future;
}

Future<void> settle(ProviderContainer container) async {
  await Future<void>.delayed(Duration.zero);
  await container.pump();
  await Future<void>.delayed(Duration.zero);
}

ProviderContainer makeContainer({
  InteractionNotifications? repository,
  NotificationTargetResolver? resolver,
  SessionScope scope = customerScope,
}) {
  return ProviderContainer(
    overrides: [
      featureSessionScopeProvider.overrideWithValue(scope),
      notificationRepositoryProvider.overrideWithValue(repository),
      notificationTargetResolverProvider.overrideWithValue(resolver),
      readRetryPolicyProvider.overrideWithValue(
        const ReadRetryPolicy(backoffs: []),
      ),
    ],
  );
}

void main() {
  test(
    'invalidating interactions drops a pending resolver in the same session',
    () async {
      final resolver = PendingResolver();
      final container = makeContainer(resolver: resolver);
      addTearDown(container.dispose);
      final provider = notificationInteractionViewModelProvider;
      container.listen(provider, (_, _) {});
      await settle(container);
      var navigations = 0;
      final pending = container
          .read(provider.notifier)
          .openNotification(
            notification(readAt: DateTime.utc(2026, 10, 8, 4)),
            onNavigate: (_) async {
              navigations++;
              return true;
            },
          );
      container.invalidate(provider);
      await settle(container);
      resolver.result.complete(
        const NotificationTargetDecision(
          available: true,
          screen: NotificationTargetScreen.customerOrder,
          entityId: fixtureOrderId,
          mode: NotificationTargetMode.order,
        ),
      );
      expect(await pending, isFalse);
      expect(navigations, 0);
    },
  );

  test(
    'invalidating interaction state drops an old pending acknowledgement',
    () async {
      final repository = InteractionNotifications();
      final response = Completer<NotificationItem>();
      repository.readHandler = (_) => response.future;
      final container = makeContainer(repository: repository);
      addTearDown(container.dispose);
      final provider = notificationInteractionViewModelProvider;
      container.listen(provider, (_, _) {});
      await settle(container);
      final pending = container
          .read(provider.notifier)
          .markRead(notification());
      container.invalidate(provider);
      await settle(container);
      expect(container.read(provider).pendingReadIds, isEmpty);
      response.complete(notification(readAt: DateTime.utc(2026, 10, 8, 4)));
      expect(await pending, isFalse);
      expect(container.read(provider).pendingReadIds, isEmpty);
    },
  );

  test('failed read can retry explicitly and clears its failure only after acknowledgement', () async {
    final repository = InteractionNotifications();
    repository.readHandler = (_) async =>
        throw const AppFailure(code: AppFailure.network);
    final container = makeContainer(repository: repository);
    addTearDown(container.dispose);
    container.listen(notificationInteractionViewModelProvider, (_, _) {});
    await settle(container);
    final vm = container.read(
      notificationInteractionViewModelProvider.notifier,
    );
    expect(await vm.markRead(notification()), isFalse);
    expect(repository.markReadCalls, 1);
    expect(
      container
          .read(notificationInteractionViewModelProvider)
          .failureFor(fixtureNotificationId)
          ?.code,
      AppFailure.network,
    );
    repository.readHandler = (_) async =>
        notification(readAt: DateTime.utc(2026, 10, 8, 4));
    expect(await vm.markRead(notification()), isTrue);
    expect(repository.markReadCalls, 2);
    expect(
      container
          .read(notificationInteractionViewModelProvider)
          .failureFor(fixtureNotificationId),
      isNull,
    );
  });

  test('denied target never reaches navigation', () async {
    final resolver = Resolver(
      const NotificationTargetDecision.unavailable(messageKey: 'MSG-63'),
    );
    final container = makeContainer(resolver: resolver);
    addTearDown(container.dispose);
    container.listen(notificationInteractionViewModelProvider, (_, _) {});
    await settle(container);
    var navigations = 0;
    expect(
      await container
          .read(notificationInteractionViewModelProvider.notifier)
          .openNotification(
            notification(readAt: DateTime.utc(2026, 10, 8, 4)),
            onNavigate: (_) async {
              navigations++;
              return true;
            },
          ),
      isFalse,
    );
    expect(navigations, 0);
    expect(
      container
          .read(notificationInteractionViewModelProvider)
          .lastUnavailableMessageKey,
      'MSG-63',
    );
  });

  for (final dispose in [true, false]) {
    test(
      'late target resolution after ${dispose ? 'disposal' : 'session expiry'} never navigates',
      () async {
        final resolver = PendingResolver();
        final container = makeContainer(resolver: resolver);
        if (!dispose) addTearDown(container.dispose);
        container.listen(notificationInteractionViewModelProvider, (_, _) {});
        await settle(container);
        var navigations = 0;
        final pending = container
            .read(notificationInteractionViewModelProvider.notifier)
            .openNotification(
              notification(readAt: DateTime.utc(2026, 10, 8, 4)),
              onNavigate: (_) async {
                navigations++;
                return true;
              },
            );
        if (dispose) {
          container.dispose();
        } else {
          container.read(epochCacheProvider).blockSession();
        }
        resolver.result.complete(
          const NotificationTargetDecision(
            available: true,
            screen: NotificationTargetScreen.customerOrder,
            entityId: fixtureOrderId,
            mode: NotificationTargetMode.order,
          ),
        );
        expect(await pending, isFalse);
        expect(navigations, 0);
      },
    );
  }

  test(
    'acknowledges only a canonical read row and does not optimistically read',
    () async {
      final repository = InteractionNotifications();
      repository.readHandler = (_) async =>
          notification(readAt: DateTime.utc(2026, 10, 8, 4));
      final container = makeContainer(repository: repository);
      addTearDown(container.dispose);
      final provider = notificationInteractionViewModelProvider;
      container.listen(provider, (_, _) {});
      await settle(container);

      final row = notification();
      final future = container.read(provider.notifier).markRead(row);
      expect(
        container.read(provider).isReadPending(row.id),
        isTrue,
        reason: 'The row stays unread while OP-N03 is in flight.',
      );
      expect(await future, isTrue);
      expect(repository.markReadCalls, 1);
      expect(container.read(provider).isReadPending(row.id), isFalse);
      expect(container.read(provider).failureFor(row.id), isNull);
    },
  );

  test('a canonical row that is still unread is rejected', () async {
    final repository = InteractionNotifications();
    repository.readHandler = (_) async => notification();
    final container = makeContainer(repository: repository);
    addTearDown(container.dispose);
    final provider = notificationInteractionViewModelProvider;
    container.listen(provider, (_, _) {});
    await settle(container);

    expect(
      await container.read(provider.notifier).markRead(notification()),
      isFalse,
    );
    expect(
      container.read(provider).failureFor(fixtureNotificationId)?.code,
      AppFailure.unsupportedData,
    );
  });

  test('a read row is accepted without another repository mutation', () async {
    final repository = InteractionNotifications();
    final container = makeContainer(repository: repository);
    addTearDown(container.dispose);
    final provider = notificationInteractionViewModelProvider;
    container.listen(provider, (_, _) {});
    await settle(container);

    expect(
      await container
          .read(provider.notifier)
          .markRead(notification(readAt: DateTime.utc(2026, 10, 8, 4))),
      isTrue,
    );
    expect(repository.markReadCalls, 0);
  });

  test('foreign recipient rows cannot reach the target resolver', () async {
    final repository = InteractionNotifications();
    final resolver = Resolver(
      const NotificationTargetDecision(
        available: true,
        screen: NotificationTargetScreen.customerOrder,
        entityId: fixtureOrderId,
        mode: NotificationTargetMode.order,
      ),
    );
    final container = makeContainer(repository: repository, resolver: resolver);
    addTearDown(container.dispose);
    final provider = notificationInteractionViewModelProvider;
    container.listen(provider, (_, _) {});
    await settle(container);

    final foreign = NotificationDto.fromJson({
      ...fixtureNotificationJson(readAt: '2026-10-08T04:00:00Z'),
      'recipient_id': fixtureManagerId,
    }).domain;
    expect(
      await container
          .read(provider.notifier)
          .openNotification(foreign, onNavigate: (_) async => true),
      isFalse,
    );
    expect(resolver.calls, isEmpty);
    expect(
      container.read(provider).failureFor(foreign.id)?.code,
      AppFailure.forbiddenOrUnavailable,
    );
  });

  test(
    'read failure does not block independently authorized navigation',
    () async {
      final repository = InteractionNotifications();
      repository.readHandler = (_) => Future<NotificationItem>.error(
        const AppFailure(code: AppFailure.network),
      );
      final resolver = Resolver(
        const NotificationTargetDecision(
          available: true,
          screen: NotificationTargetScreen.customerOrder,
          entityId: fixtureOrderId,
          mode: NotificationTargetMode.order,
        ),
      );
      final container = makeContainer(
        repository: repository,
        resolver: resolver,
      );
      addTearDown(container.dispose);
      final provider = notificationInteractionViewModelProvider;
      container.listen(provider, (_, _) {});
      await settle(container);
      var navigated = false;

      expect(
        await container
            .read(provider.notifier)
            .openNotification(
              notification(),
              onNavigate: (decision) async {
                navigated = decision.available;
                return true;
              },
            ),
        isTrue,
      );
      expect(navigated, isTrue);
      expect(resolver.calls, [fixtureNotificationId]);
      await settle(container);
      expect(
        container.read(provider).failureFor(fixtureNotificationId)?.code,
        AppFailure.network,
      );
    },
  );

  test(
    'a mutation timeout is outcome-unknown and leaves the row unconfirmed',
    () async {
      final repository = InteractionNotifications();
      repository.readHandler = (_) => Future<NotificationItem>.error(
        TimeoutException('ack response timed out'),
      );
      final container = makeContainer(repository: repository);
      addTearDown(container.dispose);
      final provider = notificationInteractionViewModelProvider;
      container.listen(provider, (_, _) {});
      await settle(container);

      expect(
        await container.read(provider.notifier).markRead(notification()),
        isFalse,
      );
      final failure = container
          .read(provider)
          .failureFor(fixtureNotificationId);
      expect(failure?.code, AppFailure.outcomeUnknownCode);
      expect(failure?.outcomeUnknown, isTrue);
    },
  );

  test('late acknowledgement after session block is dropped', () async {
    final repository = InteractionNotifications();
    final completer = Completer<NotificationItem>();
    repository.readHandler = (_) => completer.future;
    final container = makeContainer(repository: repository);
    addTearDown(container.dispose);
    final provider = notificationInteractionViewModelProvider;
    container.listen(provider, (_, _) {});
    await settle(container);

    final pending = container.read(provider.notifier).markRead(notification());
    container.read(epochCacheProvider).blockSession();
    completer.complete(notification(readAt: DateTime.utc(2026, 10, 8, 4)));
    expect(await pending, isFalse);
    expect(container.read(provider).pendingReadIds, isEmpty);
    expect(container.read(provider).failureFor(fixtureNotificationId), isNull);
  });

  test(
    'unknown and notification-only rows never call the target resolver',
    () async {
      final repository = InteractionNotifications();
      repository.readHandler = (_) async => notification(
        subjectType: 'notification_only',
        readAt: DateTime.utc(2026, 10, 8, 4),
      );
      final resolver = Resolver(
        const NotificationTargetDecision.unavailable(messageKey: 'MSG-63'),
      );
      final container = makeContainer(
        repository: repository,
        resolver: resolver,
      );
      addTearDown(container.dispose);
      final provider = notificationInteractionViewModelProvider;
      container.listen(provider, (_, _) {});
      await settle(container);

      expect(
        await container
            .read(provider.notifier)
            .openNotification(notification(subjectType: 'notification_only')),
        isFalse,
      );
      final unknown = NotificationDto.fromJson(
        fixtureNotificationJson(subjectType: 'future_subject'),
      ).domain;
      expect(
        await container.read(provider.notifier).openNotification(unknown),
        isFalse,
      );
      expect(resolver.calls, isEmpty);
    },
  );

  test('invalid typed decision and missing callback fail closed', () async {
    final repository = InteractionNotifications();
    repository.readHandler = (_) async =>
        notification(readAt: DateTime.utc(2026, 10, 8, 4));
    final resolver = Resolver(
      const NotificationTargetDecision(
        available: true,
        screen: NotificationTargetScreen.managerOrder,
        entityId: fixtureOrderId,
        mode: NotificationTargetMode.order,
      ),
    );
    final container = makeContainer(repository: repository, resolver: resolver);
    addTearDown(container.dispose);
    final provider = notificationInteractionViewModelProvider;
    container.listen(provider, (_, _) {});
    await settle(container);

    expect(
      await container.read(provider.notifier).openNotification(notification()),
      isFalse,
    );
    var callbackCalled = false;
    final validResolver = Resolver(
      const NotificationTargetDecision(
        available: true,
        screen: NotificationTargetScreen.customerOrder,
        entityId: fixtureOrderId,
        mode: NotificationTargetMode.order,
      ),
    );
    container.updateOverrides([
      featureSessionScopeProvider.overrideWithValue(customerScope),
      notificationRepositoryProvider.overrideWithValue(repository),
      notificationTargetResolverProvider.overrideWithValue(validResolver),
      readRetryPolicyProvider.overrideWithValue(
        const ReadRetryPolicy(backoffs: []),
      ),
    ]);
    await settle(container);
    expect(
      await container
          .read(provider.notifier)
          .openNotification(
            notification(),
            onNavigate: (decision) async {
              callbackCalled = true;
              return true;
            },
          ),
      isTrue,
    );
    expect(callbackCalled, isTrue);
  });

  test('authentication failure blocks private cache', () async {
    final repository = InteractionNotifications();
    repository.readHandler = (_) => Future<NotificationItem>.error(
      const AppFailure(code: AppFailure.unauthenticated),
    );
    final container = makeContainer(repository: repository);
    addTearDown(container.dispose);
    final provider = notificationInteractionViewModelProvider;
    container.listen(provider, (_, _) {});
    await settle(container);

    expect(
      await container.read(provider.notifier).markRead(notification()),
      isFalse,
    );
    expect(container.read(epochCacheProvider).canRead, isFalse);
  });
}
