import 'mh17_page_test_support.dart';

export 'mh17_page_test_support.dart';

const availableOrderDecision = NotificationTargetDecision(
  available: true,
  screen: NotificationTargetScreen.customerOrder,
  entityId: fixtureOrderId,
  mode: NotificationTargetMode.order,
);

/// Reuses the page fakes while allowing the test to change the trusted scope.
Future<void> mountScopedPage(
  WidgetTester tester,
  ProviderContainer container, {
  Future<bool> Function(NotificationTargetDecision)? onNavigate,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: NotificationsPage(enablePolling: false, onNavigate: onNavigate),
      ),
    ),
  );
  await settle(tester);
}

NotificationItem scopedNotification(SessionScope scope, int index) {
  final suffix = index.toString().padLeft(12, '0');
  final eventId = '60000000-0000-4000-8000-$suffix';
  return NotificationItem(
    id: '50000000-0000-4000-8000-$suffix',
    recipientId: scope.userId!,
    eventId: eventId,
    subjectType: NotificationSubjectType.notificationOnly,
    subjectId: eventId,
    title: 'Thông báo riêng $index',
    body: 'Nội dung riêng $index',
    readAt: null,
    createdAt: DateTime.utc(2026, 10, 21, 8),
  );
}
