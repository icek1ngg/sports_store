import 'dart:async';

import 'package:flutter/material.dart';
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
import 'package:sports_store/features/notifications/presentation/pages/notifications_page.dart';
import 'package:sports_store/features/notifications/presentation/view_models/notification_interaction_view_model.dart';
import 'package:sports_store/features/notifications/presentation/view_models/notification_providers.dart';

import '../../../../fixtures/order_notification_fixtures.dart';

const pageScope = SessionScope(
  userId: fixtureCustomerId,
  role: 'customer',
  generation: 1,
);

class PageNotifications implements NotificationRepository {
  final requests =
      <({NotificationQuery query, Completer<NotificationPage> result})>[];
  final countRequests = <Completer<int>>[];
  Future<NotificationItem> Function(String id)? markReadHandler;

  @override
  Future<NotificationPage> getPage(NotificationQuery query) {
    final result = Completer<NotificationPage>();
    requests.add((query: query, result: result));
    return result.future;
  }

  @override
  Future<int> getUnreadCount() {
    final result = Completer<int>();
    countRequests.add(result);
    return result.future;
  }

  @override
  Future<NotificationItem> markRead(String notificationId) {
    final handler = markReadHandler;
    if (handler == null) {
      return Future<NotificationItem>.error(
        StateError('not used in page tests'),
      );
    }
    return handler(notificationId);
  }
}

class PageTargetResolver implements NotificationTargetResolver {
  PageTargetResolver(this.decision);

  final NotificationTargetDecision decision;
  final calls = <String>[];

  @override
  Future<NotificationTargetDecision> resolve(String notificationId) async {
    calls.add(notificationId);
    return decision;
  }
}

final _row1 = NotificationDto.fromJson({
  ...fixtureNotificationJson(),
  'id': '50000000-0000-4000-8000-000000000011',
  'title': 'Thông báo trang một',
}).domain;

final _row2 = NotificationDto.fromJson({
  ...fixtureNotificationJson(),
  'id': '50000000-0000-4000-8000-000000000012',
  'read_at': '2026-10-08T04:00:00Z',
  'title': 'Thông báo trang hai',
}).domain;

final _row1Read = NotificationDto.fromJson({
  ..._row1.toMap(),
  'read_at': '2026-10-08T04:00:00Z',
}).domain;

final _longRow = NotificationDto.fromJson({
  ...fixtureNotificationJson(),
  'id': '50000000-0000-4000-8000-000000000013',
  'title': 'Thông báo có tiêu đề rất dài để kiểm tra khả năng xuống dòng trên màn hình nhỏ 320 dp',
  'body': List.filled(
    4,
    'Nội dung thông báo dài được giữ nguyên từ máy chủ và phải tự xuống dòng an toàn trên màn hình hẹp mà không gây tràn bố cục hoặc cắt mất ngữ cảnh của người nhận. ',
  ).join(),
}).domain;

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

Widget host(
  PageNotifications repository, {
  NotificationTargetResolver? resolver,
  Future<bool> Function(NotificationTargetDecision)? onNavigate,
  double? textScale,
  bool enablePolling = false,
}) {
  return ProviderScope(
    overrides: [
      featureSessionScopeProvider.overrideWithValue(pageScope),
      notificationRepositoryProvider.overrideWithValue(repository),
      notificationTargetResolverProvider.overrideWithValue(resolver),
      readRetryPolicyProvider.overrideWithValue(
        const ReadRetryPolicy(backoffs: []),
      ),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) {
          final page = NotificationsPage(
            enablePolling: enablePolling,
            onNavigate: onNavigate,
          );
          if (textScale == null) return page;
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: page,
          );
        },
      ),
    ),
  );
}

NotificationPage page(
  List<NotificationItem> items, {
  String? nextCursor,
  int? unreadCount,
}) {
  return NotificationPage(
    items: items,
    nextCursor: nextCursor,
    unreadCount: unreadCount,
    asOf: DateTime.utc(2026, 10, 8, 4),
  );
}

void main() {
  testWidgets('loads all/unread filters and shows server count', (
    tester,
  ) async {
    final repository = PageNotifications();
    await tester.pumpWidget(host(repository));
    await settle(tester);
    expect(repository.requests.single.query.filter, NotificationFilter.all);
    repository.requests.single.result.complete(
      page([_row1, _row2], unreadCount: 1),
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
    unreadRequest.result.complete(page([_row1], unreadCount: 1));
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
    repository.requests.single.result.complete(page([_row1]));
    await settle(tester);
    expect(find.text(_row1.title), findsOneWidget);
    expect(find.text('1'), findsNothing);
    repository.countRequests.single.complete(0);
    await settle(tester);
  });

  testWidgets('cursor pagination appends locally and filter resets cursor', (
    tester,
  ) async {
    final repository = PageNotifications();
    await tester.pumpWidget(host(repository));
    await settle(tester);
    repository.requests.single.result.complete(
      page([_row1], nextCursor: 'cursor-1'),
    );
    repository.countRequests.single.complete(1);
    await settle(tester);
    expect(find.text('Tải thêm'), findsOneWidget);

    await tester.tap(find.text('Tải thêm'));
    await settle(tester);
    expect(repository.requests.last.query.cursor, 'cursor-1');
    repository.requests.last.result.complete(
      page([_row2], nextCursor: 'cursor-2'),
    );
    await settle(tester);
    expect(find.text('Thông báo trang một'), findsOneWidget);
    expect(find.text('Thông báo trang hai'), findsOneWidget);

    await tester.tap(find.text('Tải thêm'));
    await settle(tester);
    expect(repository.requests.last.query.cursor, 'cursor-2');
    repository.requests.last.result.complete(
      page([_longRow], nextCursor: 'cursor-2'),
    );
    await settle(tester);
    expect(find.text('Thông báo trang một'), findsOneWidget);
    expect(find.text('Thông báo trang hai'), findsOneWidget);
    expect(find.text(_longRow.title), findsOneWidget);
    expect(find.text('Tải thêm'), findsNothing);

    await tester.tap(find.text('Chưa đọc'));
    await settle(tester);
    expect(repository.requests.last.query.cursor, isNull);
    repository.requests.last.result.complete(page([_row1]));
    await settle(tester);
  });

  testWidgets('next page failure keeps rows and retry loads the same cursor', (
    tester,
  ) async {
    final repository = PageNotifications();
    await tester.pumpWidget(host(repository));
    await settle(tester);
    repository.requests.single.result.complete(
      page([_row1], nextCursor: 'cursor-1'),
    );
    repository.countRequests.single.complete(1);
    await settle(tester);

    await tester.tap(find.text('Tải thêm'));
    await settle(tester);
    final failedRequest = repository.requests.last;
    expect(failedRequest.query.cursor, 'cursor-1');
    failedRequest.result.completeError(const AppFailure(code: AppFailure.network));
    await settle(tester);
    expect(find.text('Thông báo trang một'), findsOneWidget);
    expect(find.text('Tải thêm'), findsOneWidget);

    await tester.tap(find.text('Tải thêm'));
    await settle(tester);
    final retryRequest = repository.requests.last;
    expect(retryRequest.query.cursor, 'cursor-1');
    retryRequest.result.complete(page([_row2], nextCursor: 'cursor-2'));
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
      page([_row1], nextCursor: 'cursor-1'),
    );
    repository.countRequests.single.complete(1);
    await settle(tester);

    await tester.tap(find.text('Tải thêm'));
    await settle(tester);
    repository.requests.last.result.complete(
      page([_row2], nextCursor: 'cursor-2'),
    );
    await settle(tester);
    expect(find.text(_row2.title), findsOneWidget);

    final requestStart = repository.requests.length;
    final countStart = repository.countRequests.length;
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(repository.requests.length, greaterThan(requestStart));
    expect(repository.requests.last.query.cursor, isNull);
    repository.requests.last.result.complete(
      page([_row1], nextCursor: 'cursor-1'),
    );
    for (final countRequest in repository.countRequests.skip(countStart)) {
      if (!countRequest.isCompleted) countRequest.complete(1);
    }
    await settle(tester);
    expect(find.text(_row1.title), findsOneWidget);
    expect(find.text(_row2.title), findsNothing);
  });

  testWidgets('stale refresh keeps rows readable and disables read mutation', (
    tester,
  ) async {
    final repository = PageNotifications();
    await tester.pumpWidget(host(repository));
    await settle(tester);
    repository.requests.single.result.complete(page([_row1], unreadCount: 1));
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
    for (var i = 0; i < 5 &&
        repository.countRequests.length == countRequestStart; i++) {
      await tester.pump();
    }
    for (final countRequest
        in repository.countRequests.skip(countRequestStart)) {
      if (!countRequest.isCompleted) countRequest.complete(1);
    }
    if (repository.countRequests.length > countRequestStart) {
      await settle(tester);
    }
  });

  testWidgets('mark read keeps unread row and badge until canonical refresh', (
    tester,
  ) async {
    final repository = PageNotifications();
    final read = Completer<NotificationItem>();
    repository.markReadHandler = (_) => read.future;
    await tester.pumpWidget(host(repository));
    await settle(tester);
    repository.requests.single.result.complete(
      page([_row1], unreadCount: 1),
    );
    repository.countRequests.single.complete(1);
    await settle(tester);

    await tester.tap(find.text('Đánh dấu đã đọc'));
    await settle(tester);
    expect(find.text('Đánh dấu đã đọc'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    read.complete(_row1Read);
    for (var i = 0; i < 5 && repository.requests.length < 2; i++) {
      await tester.pump();
    }
    expect(repository.requests.length, greaterThanOrEqualTo(2));
    repository.requests.last.result.complete(page([_row1Read], unreadCount: 0));
    repository.countRequests.last.complete(0);
    await settle(tester);
    expect(find.text('Đánh dấu đã đọc'), findsNothing);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('long notification text lays out at 320 dp', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = PageNotifications();
    await tester.pumpWidget(host(repository, textScale: 2));
    await settle(tester);
    repository.requests.single.result.complete(page([_longRow]));
    repository.countRequests.single.complete(1);
    await settle(tester);
    expect(find.text(_longRow.title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
    repository.requests.single.result.complete(page([_row1]));
    repository.countRequests.single.complete(1);
    await settle(tester);
    await tester.tap(find.text(_row1.title));
    await settle(tester);
    expect(navigated, isTrue);
    expect(resolver.calls, [_row1.id]);
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
    repository.requests.single.result.complete(page([_row2]));
    repository.countRequests.single.complete(0);
    await settle(tester);
    await tester.tap(find.text(_row2.title));
    await settle(tester);
    expect(find.text('Mục tiêu thông báo hiện chưa khả dụng.'), findsOneWidget);
    expect(resolver.calls, [_row2.id]);
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
