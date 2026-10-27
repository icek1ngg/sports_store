import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sports_store/features/notifications/domain/models/notification_item.dart';
import 'package:sports_store/features/notifications/presentation/widgets/notification_tile.dart';
import 'package:sports_store/features/notifications/presentation/widgets/unread_badge.dart';

const notificationId = '50000000-0000-4000-8000-000000000001';
const notificationRecipientId = '20000000-0000-4000-8000-000000000001';
const notificationEventId = '40000000-0000-4000-8000-000000000001';
const notificationSubjectId = '10000000-0000-4000-8000-000000000001';

NotificationItem _notification({DateTime? readAt}) {
  return NotificationItem(
    id: notificationId,
    recipientId: notificationRecipientId,
    eventId: notificationEventId,
    subjectType: NotificationSubjectType.order,
    subjectId: notificationSubjectId,
    title: 'Đơn hàng đã được xác nhận',
    body: 'Mở đơn để xem trạng thái hiện tại.',
    readAt: readAt,
    createdAt: DateTime.utc(2026, 10, 8, 3, 40),
  );
}

Widget _host(Widget child, {bool largeText = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(320, 900),
        textScaler: largeText ? TextScaler.linear(2) : TextScaler.noScaling,
      ),
      child: Scaffold(
        body: SingleChildScrollView(child: SizedBox(width: 320, child: child)),
      ),
    ),
  );
}

void main() {
  testWidgets('notification tile shows unread text and explicit read action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(NotificationTile(notification: _notification(), onMarkRead: () {})),
    );

    expect(find.text('Đơn hàng đã được xác nhận'), findsOneWidget);
    expect(find.text('Mở đơn để xem trạng thái hiện tại.'), findsOneWidget);
    expect(find.text('Đánh dấu đã đọc'), findsOneWidget);
    expect(find.text('Đơn hàng'), findsOneWidget);
  });

  testWidgets('read notification does not show read mutation action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        NotificationTile(
          notification: _notification(readAt: DateTime.utc(2026, 10, 8, 4)),
          onMarkRead: () {},
        ),
      ),
    );

    expect(find.text('Đánh dấu đã đọc'), findsNothing);
    expect(find.text('Chưa đọc'), findsNothing);
  });

  testWidgets('badge preserves full count in semantics and uses 99+ visually', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const UnreadBadge(count: 124)));

    expect(find.text('99+'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(UnreadBadge)),
      matchesSemantics(label: '124 thông báo chưa đọc'),
    );
  });

  testWidgets('notification tile fits 320 width at 2x text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        NotificationTile(notification: _notification(), onMarkRead: () {}),
        largeText: true,
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
