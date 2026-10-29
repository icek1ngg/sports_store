import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_action_dialog.dart';

import '../../../../fixtures/order_notification_fixtures.dart';

void main() {
  const manager = SessionScope(
    userId: fixtureManagerId,
    role: 'manager',
    generation: 1,
  );

  testWidgets(
    'dialog wraps at 320px/text 2 and rejects oversized Unicode reason',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = ProviderContainer(
        overrides: [featureSessionScopeProvider.overrideWithValue(manager)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: OrderActionDialog(
                orderId: fixtureOrderId,
                operation: OrderOperation.reject,
                submittedScope: manager,
                isStillAllowed: () => true,
              ),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('order-action-reason')),
        List.filled(1001, 'a').join(),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('order-action-submit')),
      );
      await tester.tap(find.byKey(const ValueKey('order-action-submit')));
      await tester.pump();
      expect(find.text('Lý do không vượt quá 1.000 ký tự.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  Future<void> show(
    WidgetTester tester,
    ProviderContainer container,
    OrderOperation operation,
    bool Function() allowed,
  ) => tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: OrderActionDialog(
            orderId: fixtureOrderId,
            operation: operation,
            submittedScope: container.read(featureSessionScopeProvider),
            isStillAllowed: allowed,
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'reason required, preserved, validated before unavailable command',
    (tester) async {
      final container = ProviderContainer(
        overrides: [featureSessionScopeProvider.overrideWithValue(manager)],
      );
      addTearDown(container.dispose);
      await show(tester, container, OrderOperation.reject, () => true);
      await tester.tap(find.byKey(const ValueKey('order-action-submit')));
      await tester.pump();
      expect(find.text('Vui lòng nhập lý do trước khi gửi.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('order-action-reason')),
        'Lý do hợp lệ',
      );
      await tester.tap(find.byKey(const ValueKey('order-action-submit')));
      await tester.pump();
      expect(
        find.text('Thao tác hiện chưa khả dụng. Vui lòng thử lại sau.'),
        findsOneWidget,
      );
      expect(find.text('Lý do hợp lệ'), findsOneWidget);
    },
  );

  testWidgets(
    'submit rechecks current capability instead of dialog opening snapshot',
    (tester) async {
      var allowed = true;
      final container = ProviderContainer(
        overrides: [featureSessionScopeProvider.overrideWithValue(manager)],
      );
      addTearDown(container.dispose);
      await show(tester, container, OrderOperation.confirm, () => allowed);
      allowed = false;
      await tester.tap(find.byKey(const ValueKey('order-action-submit')));
      await tester.pump();
      expect(
        find.text('Dữ liệu đã thay đổi. Làm mới trước khi tiếp tục.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'switching accounts while dialog open removes old order and reason',
    (tester) async {
      final container = ProviderContainer(
        overrides: [featureSessionScopeProvider.overrideWithValue(manager)],
      );
      addTearDown(container.dispose);
      await show(tester, container, OrderOperation.managerCancel, () => true);
      await tester.enterText(
        find.byKey(const ValueKey('order-action-reason')),
        'Private old reason',
      );
      container.updateOverrides([
        featureSessionScopeProvider.overrideWithValue(
          const SessionScope(
            userId: fixtureCustomerId,
            role: 'customer',
            generation: 2,
          ),
        ),
      ]);
      await tester.pump();
      expect(find.text(fixtureOrderId), findsNothing);
      expect(find.text('Private old reason'), findsNothing);
      expect(
        find.text('Phiên đăng nhập đã thay đổi. Vui lòng mở lại đơn hàng.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('invalidated confirmation requires reopening a fresh dialog', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [featureSessionScopeProvider.overrideWithValue(manager)],
    );
    addTearDown(container.dispose);
    await show(tester, container, OrderOperation.confirm, () => true);
    final cache = container.read(epochCacheProvider);
    cache.invalidate('orders/detail/$fixtureOrderId');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('order-action-submit')),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.text('Dữ liệu đã thay đổi. Làm mới trước khi tiếp tục.'),
      findsOneWidget,
    );
    final freshToken = cache.begin('orders/detail/$fixtureOrderId');
    cache.accept(freshToken, 'fresh');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('order-action-submit')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'expiry hides the entire dialog including private input and submit',
    (tester) async {
      final container = ProviderContainer(
        overrides: [featureSessionScopeProvider.overrideWithValue(manager)],
      );
      addTearDown(container.dispose);
      await show(tester, container, OrderOperation.reject, () => true);
      await tester.enterText(
        find.byKey(const ValueKey('order-action-reason')),
        'Private reason',
      );
      final cache = container.read(epochCacheProvider);
      cache.begin('order');
      cache.blockSession();
      await tester.pump();
      expect(find.text('Private reason'), findsNothing);
      expect(find.text(fixtureOrderId), findsNothing);
      expect(find.byKey(const ValueKey('order-action-submit')), findsNothing);
      expect(find.text('Phiên đăng nhập đã hết hạn'), findsOneWidget);
    },
  );
}
