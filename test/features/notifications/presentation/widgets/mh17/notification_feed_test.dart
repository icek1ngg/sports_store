import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/notifications/domain/models/notification_item.dart';
import 'package:sports_store/features/notifications/domain/models/notification_query.dart';
import 'package:sports_store/features/notifications/presentation/widgets/mh17/notification_feed.dart';
import 'package:sports_store/features/notifications/presentation/widgets/notification_tile.dart';
import 'package:sports_store/features/notifications/presentation/widgets/unread_badge.dart';
import 'package:sports_store/shared/widgets/async_content.dart';

import 'notification_test_support.dart';

void main() {
  for (final filter in NotificationFilter.values) {
    testWidgets(
      'accepted empty ${filter.name} has distinct copy and no badge',
      (tester) async {
        await pumpNotificationFeed(
          tester,
          Mh17NotificationFeed(items: [], hasData: true, filter: filter),
        );
        expect(
          find.text(
            filter == NotificationFilter.all
                ? 'Chưa có thông báo'
                : 'Không có thông báo chưa đọc',
          ),
          findsOneWidget,
        );
        expect(find.byType(NotificationTile), findsNothing);
        expect(find.byType(UnreadBadge), findsNothing);
        expect(find.text('Tải thêm'), findsNothing);
      },
    );
  }

  testWidgets(
    'one item reuses tile, exact identity, full text and Hanoi timestamp',
    (tester) async {
      final item = notificationRow(1);
      await pumpNotificationFeed(
        tester,
        Mh17NotificationFeed(items: [item], hasData: true),
      );
      final tile = tester.widget<NotificationTile>(
        find.byType(NotificationTile),
      );
      expect(tile.notification, same(item));
      expect(tile.key, ValueKey(item.id));
      expect(find.text(item.title), findsOneWidget);
      expect(find.text(item.body), findsOneWidget);
      expect(find.text('21/10/2026 14:00'), findsOneWidget);
      expect(find.text('Đơn hàng'), findsOneWidget);
    },
  );

  testWidgets('mixed read/unread rows are not locally filtered or reordered', (
    tester,
  ) async {
    final rows = [notificationRow(1, read: true), notificationRow(2)];
    await pumpNotificationFeed(
      tester,
      Mh17NotificationFeed(
        items: rows,
        hasData: true,
        filter: NotificationFilter.unread,
        onMarkRead: (_) {},
      ),
    );
    expect(
      tester
          .widgetList<NotificationTile>(find.byType(NotificationTile))
          .map((t) => t.notification),
      orderedEquals(rows),
    );
    expect(find.text('Đánh dấu đã đọc'), findsOneWidget);
    expect(rows.first.isRead, isTrue);
    expect(rows.last.isRead, isFalse);
  });

  testWidgets('unknown subject preserves text and safe existing type label', (
    tester,
  ) async {
    final item = notificationRow(
      1,
      type: NotificationSubjectType.fromWire('future_kind'),
    );
    await pumpNotificationFeed(
      tester,
      Mh17NotificationFeed(items: [item], hasData: true),
    );
    expect(find.text(item.body), findsOneWidget);
    expect(find.text('Thông báo chưa phân loại'), findsOneWidget);
  });

  testWidgets(
    'initial loading and error hide unaccepted rows, explicit retry fires once',
    (tester) async {
      final item = notificationRow(1);
      var retries = 0;
      await pumpNotificationFeed(
        tester,
        Mh17NotificationFeed(
          items: [item],
          hasData: false,
          isInitialLoading: true,
        ),
      );
      expect(find.byType(LoadingState), findsOneWidget);
      expect(find.text(item.title), findsNothing);
      await pumpNotificationFeed(
        tester,
        Mh17NotificationFeed(
          items: [item],
          hasData: false,
          errorMessage: 'Không thể tải thông báo.',
          onRetry: () => retries++,
        ),
      );
      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text(item.title), findsNothing);
      await tester.tap(find.text('Thử lại'));
      expect(retries, 1);
    },
  );

  testWidgets('stale and refreshing are delegated to shared AsyncContent', (
    tester,
  ) async {
    final item = notificationRow(1);
    await pumpNotificationFeed(
      tester,
      Mh17NotificationFeed(
        items: [item],
        hasData: true,
        isStale: true,
        isRefreshing: true,
      ),
    );
    expect(find.byType(StaleDataBanner), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text(item.title), findsOneWidget);
    expect(
      tester.widget<NotificationTile>(find.byType(NotificationTile)).onTap,
      isNull,
    );
  });

  testWidgets(
    'load more error keeps rows and forwards retry once without local appending',
    (tester) async {
      final item = notificationRow(1);
      var retries = 0;
      await pumpNotificationFeed(
        tester,
        Mh17NotificationFeed(
          items: [item],
          hasData: true,
          hasMore: true,
          loadMoreErrorMessage: 'Không tải được trang tiếp theo.',
          onLoadMore: () => retries++,
        ),
      );
      expect(find.text(item.title), findsOneWidget);
      expect(find.text('Không tải được trang tiếp theo.'), findsOneWidget);
      await tester.tap(find.text('Thử lại'));
      await tester.pump();
      expect(retries, 1);
      expect(find.byType(NotificationTile), findsOneWidget);
    },
  );

  testWidgets(
    'load more pending, unavailable and exhausted obey parent flags',
    (tester) async {
      final rows = [notificationRow(1)];
      var calls = 0;
      await pumpNotificationFeed(
        tester,
        Mh17NotificationFeed(
          items: rows,
          hasData: true,
          hasMore: true,
          isLoadingMore: true,
          onLoadMore: () => calls++,
        ),
      );
      expect(find.bySemanticsLabel('Đang tải thêm thông báo'), findsOneWidget);
      expect(find.text('Tải thêm'), findsNothing);
      expect(calls, 0);
      await pumpNotificationFeed(
        tester,
        Mh17NotificationFeed(items: rows, hasData: true, hasMore: true),
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      await pumpNotificationFeed(
        tester,
        Mh17NotificationFeed(
          items: rows,
          hasData: true,
          hasMore: false,
          onLoadMore: () => calls++,
        ),
      );
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(NotificationTile), findsOneWidget);
    },
  );

  testWidgets('load more normal action is one deliberate callback', (
    tester,
  ) async {
    var calls = 0;
    await pumpNotificationFeed(
      tester,
      Mh17NotificationFeed(
        items: [notificationRow(1)],
        hasData: true,
        hasMore: true,
        onLoadMore: () => calls++,
      ),
    );
    final button = find.widgetWithText(OutlinedButton, 'Tải thêm');
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    await tester.tap(button);
    expect(calls, 1);
  });

  testWidgets(
    '45 rows and pagination footer remain reachable without nested scrolling',
    (tester) async {
      final rows = List.generate(45, (i) => notificationRow(i + 1, read: true));
      var loads = 0;
      await pumpNotificationFeed(
        tester,
        Mh17NotificationFeed(
          items: rows,
          hasData: true,
          hasMore: true,
          onLoadMore: () => loads++,
        ),
      );
      expect(find.byType(Scrollable), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(rows.last.title),
        500,
        maxScrolls: 70,
      );
      expect(find.text(rows.last.title), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Tải thêm'), 250);
      await tester.tap(find.text('Tải thêm'));
      expect(loads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.5, 2.0]) {
      testWidgets('long Vietnamese text accessible at $width / $scale', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        try {
          final title =
              'Thông báo đơn hàng cần kiểm tra với nội dung tiếng Việt đầy đủ';
          final body =
              'Nội dung cập nhật được máy chủ cung cấp để khách hàng đọc rõ trên màn hình nhỏ. ' *
              2;
          final item = notificationRow(1, title: title, body: body);
          await pumpNotificationFeed(
            tester,
            Mh17NotificationFeed(
              items: [item],
              hasData: true,
              onOpen: (_) {},
              onMarkRead: (_) {},
            ),
            width: width,
            scale: scale,
          );
          expect(find.text(title), findsOneWidget);
          expect(find.text(body), findsOneWidget);
          final node = tester.getSemantics(find.byKey(ValueKey(item.id)));
          // Existing tile merges descendant text with its explicit unread label.
          expect(node.label, startsWith('Chưa đọc. $title. Đơn hàng'));
          expect(node.label, contains(body));
          await tester.scrollUntilVisible(find.text('Đánh dấu đã đọc'), 150);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }
  }
}
