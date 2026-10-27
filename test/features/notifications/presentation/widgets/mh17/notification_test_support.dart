import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/features/notifications/domain/models/notification_item.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_notification_theme.dart';

/// Synthetic, immutable rows with distinct event identities per recipient.
NotificationItem notificationRow(
  int index, {
  bool read = false,
  String? title,
  String? body,
  NotificationSubjectType? type,
}) {
  final suffix = index.toString().padLeft(12, '0');
  final eventId = '60000000-0000-4000-8000-$suffix';
  final subjectType = type ?? NotificationSubjectType.order;
  return NotificationItem(
    id: '50000000-0000-4000-8000-$suffix',
    recipientId: '20000000-0000-4000-8000-000000000001',
    eventId: eventId,
    subjectType: subjectType,
    subjectId: subjectType == NotificationSubjectType.notificationOnly
        ? eventId
        : '10000000-0000-4000-8000-$suffix',
    title: title ?? 'Thông báo $index',
    body: body ?? 'Nội dung cập nhật $index từ cửa hàng.',
    readAt: read ? DateTime.utc(2026, 10, 21, 8) : null,
    createdAt: DateTime.utc(2026, 10, 21, 7),
  );
}

Future<void> pumpNotificationFeed(
  WidgetTester tester,
  Widget feed, {
  double width = 390,
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 844),
          textScaler: TextScaler.linear(scale),
        ),
        child: OrderNotificationTheme(child: Scaffold(body: feed)),
      ),
    ),
  );
  await tester.pump();
}
