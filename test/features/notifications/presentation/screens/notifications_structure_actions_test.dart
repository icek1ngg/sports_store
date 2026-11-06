import '../pages/mh17/mh17_modal_integration_support.dart';
import '../view_models/mh17/notification_actions_test_support.dart'
    as actions_test;

import 'package:sports_store/features/notifications/presentation/providers/notification_page_actions.dart';

import 'package:sports_store/features/notifications/data/models/notification_dto.dart';
import 'package:sports_store/features/notifications/presentation/screens/notifications_screen.dart'
    as canonical_screen;
import 'package:sports_store/features/notifications/presentation/pages/notifications_page.dart'
    as legacy_screen;
import 'package:sports_store/features/notifications/presentation/providers/notification_providers.dart'
    as canonical;
import 'package:sports_store/features/notifications/presentation/view_models/notification_providers.dart'
    as legacy;
import 'package:sports_store/features/notifications/presentation/widgets/mh17/notification_feed.dart';
import 'package:sports_store/features/notifications/presentation/widgets/notifications_content.dart';
import 'package:sports_store/features/notifications/presentation/widgets/notifications_header.dart';
import 'package:sports_store/app/theme/app_theme.dart';

void main() {
  test('Actions forwards the exact canonical context row and namespace synchronously', () async {
    final rig = actions_test.ActionRig();
    try {
      final item = actions_test.actionItem(
        type: 'notification_only',
        read: true,
      );
      final submitted = rig.seed(item);
      final base = rig.ports;
      var contexts = 0;
      final NotificationActionPorts ports = (
        isActive: base.isActive,
        reads: base.reads,
        query: base.query,
        interaction: base.interaction,
        state: base.state,
        navigation: base.navigation,
        message: base.message,
        context: (namespace, actual) {
          contexts++;
          expect(namespace, submitted);
          expect(actual, same(item));
        },
      );
      final opened = rig.actions.open(item, submitted, ports);
      expect(contexts, 1); // No asynchronous row reconstruction or fallback.
      await opened;
    } finally {
      rig.dispose();
    }
  });
  test('legacy imports preserve the SAME screen/provider identities', () {
    expect(
      legacy_screen.NotificationsPage,
      canonical_screen.NotificationsScreen,
    );
    expect(
      identical(
        canonical.notificationPageFoundationProvider,
        legacy.notificationPageFoundationProvider,
      ),
      true,
    );
    expect(
      identical(
        canonical.unreadCountFoundationProvider,
        legacy.unreadCountFoundationProvider,
      ),
      true,
    );
  });

  for (final foreign in [false, true]) {
    testWidgets(
      'Actions context rejects nonaccepted row identity, foreign=$foreign',
      (tester) async {
        final rig = PageModalRig();
        try {
          await rig.mount(tester);
          final accepted = tester
              .widget<NotificationTile>(find.byType(NotificationTile))
              .notification;
          final forgedProjection = NotificationDto.fromJson({
            ...accepted.toMap(),
            'recipient_id': foreign ? otherContextOwner : accepted.recipientId,
            'body': 'Nội dung không nằm trong accepted feed',
          }).domain;
          tester
              .widget<Mh17NotificationFeed>(find.byType(Mh17NotificationFeed))
              .onOpen!(forgedProjection);
          await tester.pumpAndSettle();
          expect(find.byType(Mh17NotificationContextModal), findsNothing);
          expect(find.text(forgedProjection.body), findsNothing);
          expect(rig.repository.markCalls, 0);
          // The actual canonical object still opens the independent modal owner.
          await rig.open(tester);
          expect(find.byType(Mh17NotificationContextSheet), findsOneWidget);
          expect(rig.handle(tester).isRevoked, false);
        } finally {
          await rig.cleanup(tester);
        }
      },
    );
  }

  for (final code in [
    AppFailure.unauthenticated,
    AppFailure.forbiddenOrUnavailable,
  ]) {
    testWidgets(
      'content substitutes safe session state for denied feed: $code',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NotificationsContent(
                filter: NotificationFilter.all,
                onFilterChanged: (_) {},
                onRefresh: () {},
                failure: AppFailure(code: code),
                feed: const Text('PRIVATE FEED'),
              ),
            ),
          ),
        );
        expect(find.text('PRIVATE FEED'), findsNothing);
        expect(find.text('Tất cả'), findsOneWidget);
        expect(find.text('Chưa đọc'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'header uses shared ThemeData and preserves exact-count semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AppTheme.notificationsScope(
            child: Scaffold(appBar: notificationsHeader(unreadCount: 1207)),
          ),
        ),
      );
      expect(find.text('Thông báo'), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
      expect(find.bySemanticsLabel('1207 thông báo chưa đọc'), findsOneWidget);
      final themed = Theme.of(tester.element(find.text('Thông báo')));
      expect(themed.textTheme.bodyMedium!.fontFamily, 'Inter');
      expect(themed.appBarTheme.toolbarHeight, 64);
      expect(themed.cardTheme.elevation, 0);
      expect(themed.colorScheme.surface, Colors.white);
      semantics.dispose();
    },
  );
}
