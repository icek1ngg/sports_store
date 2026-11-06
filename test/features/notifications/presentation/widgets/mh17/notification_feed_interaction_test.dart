import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/notifications/presentation/widgets/mh17/notification_feed.dart';
import 'package:sports_store/features/notifications/presentation/widgets/notification_tile.dart';

import 'notification_test_support.dart';

void main() {
  testWidgets(
    'open and explicit read forward exact items independently without optimistic changes',
    (tester) async {
      final item = notificationRow(1);
      final opened = <String>[], read = <String>[];
      await pumpNotificationFeed(
        tester,
        Mh17NotificationFeed(
          items: [item],
          hasData: true,
          onOpen: (row) => opened.add(row.id),
          onMarkRead: (row) => read.add(row.id),
        ),
      );
      await tester.tap(find.text(item.title));
      await tester.pump();
      expect(opened, [item.id]);
      expect(read, isEmpty);
      await tester.tap(find.text('Đánh dấu đã đọc'));
      await tester.pump();
      expect(read, [item.id]);
      expect(opened, [item.id]);
      expect(item.isRead, isFalse);
      expect(find.text('Đánh dấu đã đọc'), findsOneWidget);
    },
  );

  testWidgets(
    'pending read disables only explicit read and preserves open callback',
    (tester) async {
      final item = notificationRow(1);
      var opens = 0, reads = 0;
      await pumpNotificationFeed(
        tester,
        Mh17NotificationFeed(
          items: [item],
          hasData: true,
          pendingReadIds: {item.id},
          onOpen: (_) => opens++,
          onMarkRead: (_) => reads++,
        ),
      );
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Đánh dấu đã đọc'));
      // The protected tile's disabled inner button lets its outer tap handle
      // this location. Preserve that behavior without issuing a read callback.
      expect(opens, 1);
      expect(reads, 0);
      await tester.tap(find.text(item.title));
      expect(reads, 0);
      expect(opens, 2);
      expect(item.isRead, isFalse);
    },
  );

  testWidgets('null item callbacks render a noninteractive tile', (
    tester,
  ) async {
    await pumpNotificationFeed(
      tester,
      Mh17NotificationFeed(items: [notificationRow(1)], hasData: true),
    );
    final tile = tester.widget<NotificationTile>(find.byType(NotificationTile));
    expect(tile.onTap, isNull);
    expect(tile.onMarkRead, isNull);
    expect(find.text('Đánh dấu đã đọc'), findsNothing);
  });

  testWidgets(
    'pull refresh delegates Future and does not imply new canonical data',
    (tester) async {
      final completion = Completer<void>();
      var refreshes = 0;
      final item = notificationRow(1);
      await pumpNotificationFeed(
        tester,
        Mh17NotificationFeed(
          items: [item],
          hasData: true,
          onRefresh: () {
            refreshes++;
            return completion.future;
          },
        ),
      );
      await tester.dragFrom(const Offset(180, 80), const Offset(0, 600));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(refreshes, 1);
      expect(item.isRead, isFalse);
      expect(find.text(item.title), findsOneWidget);
      completion.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'defensive snapshots are immutable and owner removal leaves no retained rows',
    (tester) async {
      final item = notificationRow(1);
      final input = [item];
      final pending = {item.id};
      final feed = Mh17NotificationFeed(
        items: input,
        hasData: true,
        pendingReadIds: pending,
      );
      input.clear();
      pending.clear();
      expect(feed.items, [item]);
      expect(feed.pendingReadIds, {item.id});
      expect(() => feed.items.clear(), throwsUnsupportedError);
      expect(() => feed.pendingReadIds.clear(), throwsUnsupportedError);
      await pumpNotificationFeed(tester, feed);
      await pumpNotificationFeed(
        tester,
        Mh17NotificationFeed(items: [], hasData: true),
      );
      expect(find.text(item.title), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
