import 'mh17_page_test_support.dart';

import 'package:sports_store/features/notifications/presentation/widgets/mh17/notification_feed.dart';
import 'package:sports_store/features/notifications/presentation/widgets/mh17/notification_filters.dart';

Mh17NotificationFeed feed(WidgetTester tester) =>
    tester.widget<Mh17NotificationFeed>(find.byType(Mh17NotificationFeed));
Mh17NotificationFilters filters(WidgetTester tester) => tester
    .widget<Mh17NotificationFilters>(find.byType(Mh17NotificationFilters));

void main() {
  testWidgets(
    'controlled filters query server and empty unread keeps exact server count',
    (tester) async {
      final repository = PageNotifications();
      await tester.pumpWidget(host(repository));
      await settle(tester);
      expect(feed(tester).isInitialLoading, true);
      expect(feed(tester).hasData, false);
      expect(filters(tester).selectedFilter, NotificationFilter.all);
      repository.requests.single.result.complete(page([row1]));
      repository.countRequests.single.complete(41);
      await settle(tester);
      expect(feed(tester).items.single, same(row1));
      expect(feed(tester).hasData, true);
      await tester.tap(find.text('Chưa đọc'));
      await settle(tester);
      expect(filters(tester).selectedFilter, NotificationFilter.unread);
      expect(repository.requests.last.query.filter, NotificationFilter.unread);
      expect(repository.requests.last.query.cursor, isNull);
      repository.requests.last.result.complete(page([]));
      await settle(tester);
      expect(feed(tester).filter, NotificationFilter.unread);
      expect(feed(tester).items, isEmpty);
      expect(find.text('Không có thông báo chưa đọc'), findsOneWidget);
      expect(find.text('41'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'filter resets pending Feed tail and rejects its late completion',
    (tester) async {
      final repository = PageNotifications();
      await tester.pumpWidget(host(repository));
      await settle(tester);
      repository.requests.single.result.complete(
        page([row1], nextCursor: 'tail-all'),
      );
      repository.countRequests.single.complete(41);
      await settle(tester);
      feed(tester).onLoadMore!();
      await settle(tester);
      final old = repository.requests.last;
      expect(old.query.cursor, 'tail-all');
      expect(feed(tester).isLoadingMore, true);
      filters(tester).onFilterChanged!(NotificationFilter.unread);
      await settle(tester);
      expect(repository.requests.last.query.cursor, isNull);
      expect(feed(tester).isLoadingMore, false);
      repository.requests.last.result.complete(page([]));
      await settle(tester);
      old.result.complete(page([row2], nextCursor: 'obsolete'));
      await settle(tester);
      expect(feed(tester).filter, NotificationFilter.unread);
      expect(feed(tester).items, isEmpty);
      expect(feed(tester).hasMore, false);
      expect(find.text(row2.title), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Feed footer failure keeps rows and retries current cursor without relabeling old control',
    (tester) async {
      final repository = PageNotifications();
      await tester.pumpWidget(host(repository));
      await settle(tester);
      repository.requests.single.result.complete(
        page([row1], nextCursor: 'retry-tail'),
      );
      repository.countRequests.single.complete(41);
      await settle(tester);
      await tester.tap(find.text('Tải thêm'));
      await settle(tester);
      repository.requests.last.result.completeError(
        const AppFailure(code: AppFailure.network),
      );
      await settle(tester);
      expect(feed(tester).items, [row1]);
      expect(
        feed(tester).isStale,
        false,
      ); // Tail has no cached snapshot; error still renders freshness banner.
      expect(find.text('Dữ liệu có thể chưa cập nhật'), findsOneWidget);
      expect(feed(tester).errorMessage, isNotNull);
      expect(feed(tester).loadMoreErrorMessage, isNull);
      expect(feed(tester).onOpen, isNull);
      expect(feed(tester).onMarkRead, isNull);
      expect(find.text('Tải thêm'), findsOneWidget);
      await tester.tap(find.text('Tải thêm'));
      await settle(tester);
      expect(repository.requests.last.query.cursor, 'retry-tail');
      repository.requests.last.result.complete(page([row2]));
      await settle(tester);
      expect(feed(tester).items, [row1, row2]);
      expect(feed(tester).hasMore, false);
      expect(find.text('41'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Feed refresh replaces head while original explicit refresh availability remains',
    (tester) async {
      final repository = PageNotifications();
      await tester.pumpWidget(host(repository));
      await settle(tester);
      repository.requests.single.result.complete(page([row1]));
      repository.countRequests.single.complete(41);
      await settle(tester);
      final refreshing = feed(tester).onRefresh!();
      await settle(tester);
      expect(repository.requests.last.query.cursor, isNull);
      expect(feed(tester).isRefreshing, true);
      expect(feed(tester).items, [row1]);
      expect(feed(tester).onOpen, isNull);
      expect(feed(tester).onMarkRead, isNull);
      expect(filters(tester).onRefresh, isNotNull);
      expect(filters(tester).isRefreshing, false);
      await tester.tap(
        find.byTooltip('Làm mới'),
      ); // Original deliberate second refresh remains possible.
      await settle(tester);
      repository.requests.last.result.complete(
        page([row2]),
      ); // Invalidated first round.
      repository.countRequests.last.complete(99);
      await settle(tester);
      expect(repository.requests.length, 3);
      expect(repository.requests.last.query.cursor, isNull);
      expect(feed(tester).items, [row1]);
      repository.requests.last.result.complete(page([newRow]));
      repository.countRequests.last.complete(97);
      await settle(tester);
      await refreshing;
      expect(feed(tester).items, [newRow]);
      expect(find.text(row1.title), findsNothing);
      expect(find.text('97'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'accepted empty tail preserves rows and trusts raw next cursor rather than page length',
    (tester) async {
      final repository = PageNotifications();
      await tester.pumpWidget(host(repository));
      await settle(tester);
      repository.requests.single.result.complete(
        page([row1], nextCursor: 'tail-empty'),
      );
      repository.countRequests.single.complete(41);
      await settle(tester);
      feed(tester).onLoadMore!();
      await settle(tester);
      repository.requests.last.result.complete(
        page([], nextCursor: 'tail-next'),
      );
      await settle(tester);
      expect(feed(tester).items, [row1]);
      expect(feed(tester).hasMore, true);
      expect(find.text('Chưa có thông báo'), findsNothing);
      feed(tester).onLoadMore!();
      await settle(tester);
      expect(repository.requests.last.query.cursor, 'tail-next');
      repository.requests.last.result.complete(page([]));
      await settle(tester);
      expect(feed(tester).items, [row1]);
      expect(feed(tester).hasMore, false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Feed error retry and accepted All empty preserve parent denial presentation',
    (tester) async {
      final repository = PageNotifications();
      await tester.pumpWidget(host(repository));
      await settle(tester);
      repository.requests.single.result.completeError(
        const AppFailure(code: AppFailure.network),
      );
      repository.countRequests.single.complete(41);
      await settle(tester);
      expect(feed(tester).hasData, false);
      expect(feed(tester).errorMessage, isNotNull);
      expect(find.byType(ErrorState), findsOneWidget);
      feed(tester).onRetry!();
      await settle(tester);
      repository.requests.last.result.complete(page([]));
      repository.countRequests.last.complete(41);
      await settle(tester);
      expect(feed(tester).hasData, true);
      expect(find.text('Chưa có thông báo'), findsOneWidget);
      filters(tester).onRefresh!();
      await settle(tester);
      repository.requests.last.result.completeError(
        const AppFailure(code: AppFailure.forbiddenOrUnavailable),
      );
      repository.countRequests.last.complete(41);
      await settle(tester);
      expect(find.byType(SessionUnavailableState), findsOneWidget);
      expect(find.byType(Mh17NotificationFeed), findsNothing);
      expect(find.text('41'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Feed read/open callbacks stay separate and pending state comes only from VM',
    (tester) async {
      final repository = PageNotifications(),
          ack = Completer<NotificationItem>();
      final readIds = <String>[];
      repository.markReadHandler = (id) {
        readIds.add(id);
        return ack.future;
      };
      const target = NotificationTargetDecision(
        available: true,
        screen: NotificationTargetScreen.customerOrder,
        entityId: fixtureOrderId,
        mode: NotificationTargetMode.order,
      );
      final resolver = PageTargetResolver(target);
      final opened = <NotificationTargetDecision>[];
      await tester.pumpWidget(
        host(
          repository,
          resolver: resolver,
          onNavigate: (decision) async {
            opened.add(decision);
            return true;
          },
        ),
      );
      await settle(tester);
      repository.requests.single.result.complete(page([row1]));
      repository.countRequests.single.complete(41);
      await settle(tester);
      feed(tester).onMarkRead!(row1);
      await settle(tester);
      expect(readIds, [row1.id]);
      expect(resolver.calls, isEmpty);
      expect(opened, isEmpty);
      expect(feed(tester).pendingReadIds, {row1.id});
      expect(feed(tester).items.single.readAt, isNull);
      feed(tester).onOpen!(row1);
      await settle(tester);
      expect(readIds, [row1.id]);
      expect(resolver.calls, [row1.id]);
      expect(opened, [target]);
      expect(find.text('41'), findsOneWidget);
      final captured = feed(tester).onOpen!;
      await tester.pumpWidget(const SizedBox.shrink());
      captured(row1);
      ack.complete(row1Read);
      await settle(tester);
      expect(readIds, [row1.id]);
      expect(opened, [target]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'composed Wrap filters and bounded Feed fit 320dp with text2 and long server text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = PageNotifications();
      await tester.pumpWidget(host(repository, textScale: 2));
      await settle(tester);
      repository.requests.single.result.complete(page([longRow]));
      repository.countRequests.single.complete(41);
      await settle(tester);
      expect(find.byType(Mh17NotificationFilters), findsOneWidget);
      expect(find.byType(Mh17NotificationFeed), findsOneWidget);
      expect(feed(tester).items.single, same(longRow));
      expect(find.text(longRow.title), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
