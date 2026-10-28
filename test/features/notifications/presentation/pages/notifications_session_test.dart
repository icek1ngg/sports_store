import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/core/state/read_retry_policy.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/notifications/data/models/notification_dto.dart';
import 'package:sports_store/features/notifications/domain/models/notification_item.dart';
import 'package:sports_store/features/notifications/domain/models/notification_page.dart';
import 'package:sports_store/features/notifications/domain/models/notification_query.dart';
import 'package:sports_store/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sports_store/features/notifications/presentation/pages/notifications_page.dart';
import 'package:sports_store/features/notifications/presentation/view_models/notification_providers.dart';
import 'package:sports_store/shared/widgets/async_content.dart';

import '../../../../fixtures/order_notification_fixtures.dart';

const _scopeA = SessionScope(
  userId: fixtureCustomerId,
  role: 'customer',
  generation: 1,
);
const _scopeB = SessionScope(
  userId: '20000000-0000-4000-8000-000000000099',
  role: 'customer',
  generation: 2,
);

NotificationItem _row(SessionScope scope, String label) =>
    NotificationDto.fromJson({
      ...fixtureNotificationJson(subjectType: 'notification_only'),
      'recipient_id': scope.userId,
      'subject_id': fixtureEventId,
      'title': 'Thông báo riêng $label',
      'body': 'Nội dung riêng $label',
    }).domain;

NotificationPage _page(SessionScope scope, String label) => NotificationPage(
  items: [_row(scope, label)],
  nextCursor: null,
  unreadCount: null,
  asOf: DateTime.utc(2026, 10, 8, 4),
);

class _SessionNotifications implements NotificationRepository {
  Future<NotificationPage> Function(NotificationQuery)? pageHandler;
  Future<int> Function()? countHandler;
  int pageCalls = 0;

  @override
  Future<NotificationPage> getPage(NotificationQuery query) {
    pageCalls++;
    return pageHandler!(query);
  }

  @override
  Future<int> getUnreadCount() => countHandler!();

  @override
  Future<NotificationItem> markRead(String notificationId) async =>
      throw const AppFailure(code: AppFailure.externalDependencyUnavailable);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump();
}

Future<void> _show(
  WidgetTester tester,
  ProviderContainer container, {
  bool enablePolling = false,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        home: NotificationsPage(enablePolling: enablePolling),
      ),
    ),
  );
  await _settle(tester);
}

void main() {
  testWidgets(
    'inbox denial also hides an already open notification-only modal',
    (tester) async {
      final repository = _SessionNotifications()
        ..pageHandler = ((_) async => _page(_scopeA, 'A'))
        ..countHandler = () async => 41;
      final container = ProviderContainer(
        overrides: [
          featureSessionScopeProvider.overrideWithValue(_scopeA),
          notificationRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      await _show(tester, container);
      await tester.tap(find.text('Thông báo riêng A'));
      await tester.pumpAndSettle();
      expect(find.text('Nội dung riêng A'), findsWidgets);
      repository.countHandler = () async =>
          throw const AppFailure(code: AppFailure.forbiddenOrUnavailable);
      final refresh = container
          .read(unreadCountFoundationProvider.notifier)
          .refresh();
      await _settle(tester);
      await refresh;
      await _settle(tester);
      expect(find.text('Nội dung riêng A'), findsNothing);
      expect(find.text('Thông báo riêng A'), findsNothing);
      expect(find.text('41'), findsNothing);
      expect(find.byType(SessionUnavailableState), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'expiry during polling hides private state and drops the late poll',
    (tester) async {
      var scope = _scopeA;
      final response = Completer<NotificationPage>();
      final count = Completer<int>();
      var polling = false;
      final repository = _SessionNotifications()
        ..pageHandler = ((_) =>
            polling ? response.future : Future.value(_page(_scopeA, 'A')))
        ..countHandler = () => polling ? count.future : Future.value(41);
      final container = ProviderContainer(
        overrides: [
          featureSessionScopeProvider.overrideWith((ref) => scope),
          notificationRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      await _show(tester, container, enablePolling: true);
      expect(find.text('Thông báo riêng A'), findsOneWidget);
      polling = true;
      await tester.pump(const Duration(seconds: 3));
      await _settle(tester);
      expect(repository.pageCalls, 2);
      scope = const SessionScope(userId: null, role: null, generation: 2);
      container.invalidate(featureSessionScopeProvider);
      await _settle(tester);
      expect(find.text('Thông báo riêng A'), findsNothing);
      expect(find.text('41'), findsNothing);
      response.complete(_page(_scopeA, 'A'));
      count.complete(42);
      await _settle(tester);
      await tester.pump(const Duration(seconds: 7));
      expect(repository.pageCalls, 2);
      expect(find.text('Thông báo riêng A'), findsNothing);
      expect(find.text('42'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('account switch hides old rows and badge in the first frame', (
    tester,
  ) async {
    var scope = _scopeA;
    final oldResponse = Completer<NotificationPage>();
    final newResponse = Completer<NotificationPage>();
    final newCount = Completer<int>();
    var oldRefreshPending = false;
    final repository = _SessionNotifications()
      ..pageHandler = ((_) => scope == _scopeB
          ? newResponse.future
          : oldRefreshPending
          ? oldResponse.future
          : Future.value(_page(_scopeA, 'A')))
      ..countHandler = () =>
          scope == _scopeB ? newCount.future : Future.value(41);
    final container = ProviderContainer(
      overrides: [
        featureSessionScopeProvider.overrideWith((ref) => scope),
        notificationRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await _show(tester, container);
    expect(find.text('Thông báo riêng A'), findsOneWidget);
    expect(find.text('41'), findsOneWidget);
    oldRefreshPending = true;
    final oldRefresh = container
        .read(notificationPageFoundationProvider(NotificationQuery()).notifier)
        .refresh();
    await tester.pump();
    scope = _scopeB;
    container.invalidate(featureSessionScopeProvider);
    await tester.pump();
    expect(find.text('Thông báo riêng A'), findsNothing);
    expect(find.text('Nội dung riêng A'), findsNothing);
    expect(find.text('41'), findsNothing);
    await _settle(tester);
    oldResponse.complete(_page(_scopeA, 'A'));
    await oldRefresh;
    await _settle(tester);
    expect(find.text('Thông báo riêng A'), findsNothing);
    expect(find.byType(LoadingState), findsOneWidget);
    newResponse.complete(_page(_scopeB, 'B'));
    newCount.complete(3);
    await _settle(tester);
    expect(find.text('Thông báo riêng B'), findsOneWidget);
    expect(find.text('Thông báo riêng A'), findsNothing);
    expect(find.text('3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final switchAccount in [true, false]) {
    testWidgets(
      'notification-only modal hides private content on ${switchAccount ? 'account switch' : 'expiry'}',
      (tester) async {
        var scope = _scopeA;
        final repository = _SessionNotifications()
          ..pageHandler = ((_) async =>
              scope == _scopeA ? _page(_scopeA, 'A') : _page(_scopeB, 'B'))
          ..countHandler = () async => 1;
        final container = ProviderContainer(
          overrides: [
            featureSessionScopeProvider.overrideWith((ref) => scope),
            notificationRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);
        await _show(tester, container);
        await tester.tap(find.text('Thông báo riêng A'));
        await tester.pumpAndSettle();
        expect(find.text('Nội dung riêng A'), findsNWidgets(2));
        if (switchAccount) {
          scope = _scopeB;
          container.invalidate(featureSessionScopeProvider);
        } else {
          container.read(epochCacheProvider).blockSession();
        }
        await tester.pump();
        expect(find.text('Thông báo riêng A'), findsNothing);
        expect(find.text('Nội dung riêng A'), findsNothing);
        await _settle(tester);
        expect(find.text('Nội dung riêng A'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('unresolved and signed-out sessions never query the inbox', (
    tester,
  ) async {
    final repository = _SessionNotifications();
    final container = ProviderContainer(
      overrides: [
        featureSessionScopeProvider.overrideWithValue(
          const SessionScope.unresolved(),
        ),
        notificationRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await _show(tester, container);
    expect(find.byType(LoadingState), findsOneWidget);
    expect(repository.pageCalls, 0);
    container.updateOverrides([
      featureSessionScopeProvider.overrideWithValue(
        const SessionScope(userId: null, role: null, generation: 1),
      ),
      notificationRepositoryProvider.overrideWithValue(repository),
    ]);
    await tester.pump();
    expect(find.byType(SessionExpiredState), findsOneWidget);
    expect(repository.pageCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('initial error can retry to a confirmed empty inbox', (
    tester,
  ) async {
    final repository = _SessionNotifications()
      ..pageHandler = ((_) async =>
          throw const AppFailure(code: AppFailure.network))
      ..countHandler = () async => 0;
    final container = ProviderContainer(
      overrides: [
        featureSessionScopeProvider.overrideWithValue(_scopeA),
        notificationRepositoryProvider.overrideWithValue(repository),
        readRetryPolicyProvider.overrideWithValue(
          const ReadRetryPolicy(backoffs: []),
        ),
      ],
    );
    addTearDown(container.dispose);
    await _show(tester, container);
    expect(find.byType(ErrorState), findsOneWidget);
    repository.pageHandler = (_) async => NotificationPage(
      items: const [],
      nextCursor: null,
      unreadCount: 0,
      asOf: DateTime.utc(2026, 10, 8, 4),
    );
    await tester.tap(find.text('Thử lại'));
    await _settle(tester);
    expect(find.text('Chưa có thông báo'), findsOneWidget);
    expect(find.byType(ErrorState), findsNothing);
    expect(repository.pageCalls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
