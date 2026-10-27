import 'mh17_characterization_support.dart';

void main() {
  testWidgets(
    'available read, pending read hit and rapid body taps keep ack separate from authorized opens',
    (tester) async {
      final repository = PageNotifications();
      final ack = Completer<NotificationItem>();
      var reads = 0, navigations = 0;
      repository.markReadHandler = (_) {
        reads++;
        return ack.future;
      };
      final resolver = PageTargetResolver(availableOrderDecision);
      await tester.pumpWidget(
        host(
          repository,
          resolver: resolver,
          onNavigate: (_) async {
            navigations++;
            return true;
          },
        ),
      );
      await settle(tester);
      repository.requests.single.result.complete(page([row1]));
      repository.countRequests.single.complete(41);
      await settle(tester);
      await tester.tap(find.text('Đánh dấu đã đọc'));
      await settle(tester);
      expect(reads, 1);
      expect(resolver.calls, isEmpty);
      expect(navigations, 0);
      expect(row1.isRead, isFalse);
      expect(find.text('41'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Đánh dấu đã đọc'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Đánh dấu đã đọc'));
      await settle(tester);
      expect(reads, 1);
      expect(resolver.calls, [row1.id]);
      expect(navigations, 1);
      await tester.tap(find.text(row1.title));
      await tester.tap(find.text(row1.title));
      await settle(tester);
      expect(reads, 1);
      expect(resolver.calls, [row1.id, row1.id, row1.id]);
      expect(navigations, 3);
      expect(find.text('41'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      ack.complete(row1Read);
      await settle(tester);
      expect(navigations, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stale page removes explicit read and disables body open', (
    tester,
  ) async {
    final repository = PageNotifications();
    var reads = 0, navigations = 0;
    repository.markReadHandler = (_) async {
      reads++;
      return row1Read;
    };
    final resolver = PageTargetResolver(availableOrderDecision);
    await tester.pumpWidget(
      host(
        repository,
        resolver: resolver,
        onNavigate: (_) async {
          navigations++;
          return true;
        },
      ),
    );
    await settle(tester);
    repository.requests.single.result.complete(page([row1]));
    repository.countRequests.single.complete(41);
    await settle(tester);
    await tester.tap(find.byTooltip('Làm mới'));
    await settle(tester);
    repository.requests.last.result.completeError(
      const AppFailure(code: AppFailure.network),
    );
    repository.countRequests.last.complete(41);
    await settle(tester);
    expect(find.text('Dữ liệu có thể chưa cập nhật'), findsWidgets);
    expect(find.text('Đánh dấu đã đọc'), findsNothing);
    final tile = tester.widget<NotificationTile>(find.byType(NotificationTile));
    expect(tile.onTap, isNull);
    expect(tile.onMarkRead, isNull);
    await tester.tap(find.text(row1.title));
    await settle(tester);
    expect(reads, 0);
    expect(navigations, 0);
    expect(resolver.calls, isEmpty);
  });

  testWidgets(
    'captured read and open callbacks after page disposal fail closed',
    (tester) async {
      final repository = PageNotifications();
      var reads = 0, navigations = 0;
      repository.markReadHandler = (_) async {
        reads++;
        return row1Read;
      };
      final resolver = PageTargetResolver(availableOrderDecision);
      await tester.pumpWidget(
        host(
          repository,
          resolver: resolver,
          onNavigate: (_) async {
            navigations++;
            return true;
          },
        ),
      );
      await settle(tester);
      repository.requests.single.result.complete(page([row1]));
      repository.countRequests.single.complete(41);
      await settle(tester);
      final tile = tester.widget<NotificationTile>(
        find.byType(NotificationTile),
      );
      expect(tile.onTap, isNotNull);
      expect(tile.onMarkRead, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
      tile.onTap!();
      tile.onMarkRead!();
      await settle(tester);
      expect(reads, 0);
      expect(navigations, 0);
      expect(resolver.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
