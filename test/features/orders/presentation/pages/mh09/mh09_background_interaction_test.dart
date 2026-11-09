import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_order_details_page.dart';
import 'package:sports_store/features/orders/presentation/view_models/order_providers.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_action_dialog.dart';
import 'package:sports_store/features/orders/data/models/order_dto.dart';

import 'mh09_page_test_support.dart';

void main() {
  testWidgets(
    'background refresh preserves reason and unchanged decision; real revocation blocks',
    (tester) async {
      final repository = Mh09PageOrders(
        () => mh09Details(capabilities: mh09Capabilities(reject: true)),
      );
      await tester.pumpWidget(
        mh09PageHost(
          repository: repository,
          pageOverride: const ManagerOrderDetailsPage(orderId: fixtureOrderId),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ManagerOrderDetailsPage)),
      );
      var listInvalidations = 0;
      final cache = container.read(epochCacheProvider);
      cache.begin('orders/list/observed');
      final cancel = cache.listen((key) {
        if (key == 'orders/list/observed') listInvalidations++;
      });
      addTearDown(cancel);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 31));
        await tester.pumpAndSettle();
      }
      expect(repository.detailCalls, greaterThanOrEqualTo(4));
      expect(listInvalidations, 0);
      await tester.tap(find.byKey(const ValueKey('mh09-action-reject')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('order-action-reason')),
        'Giữ nguyên lý do đang nhập',
      );
      final before = repository.detailCalls;
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 31));
        await tester.pumpAndSettle();
      }
      expect(repository.detailCalls, before);
      container.read(epochCacheProvider).invalidate('orders/list/unrelated');
      await tester.pumpAndSettle();
      expect(
        find.text('Dữ liệu đã thay đổi. Làm mới trước khi tiếp tục.'),
        findsNothing,
      );
      await container
          .read(orderDetailsFoundationProvider(fixtureOrderId).notifier)
          .refresh();
      await tester.pumpAndSettle();
      expect(find.byType(OrderActionDialog), findsOneWidget);
      expect(find.text('Giữ nguyên lý do đang nhập'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('order-action-submit')),
            )
            .onPressed,
        isNotNull,
      );
      final revised = fixtureOrderDetailsJson();
      (revised['order'] as Map)['updated_at'] = '2026-10-15T08:00:00Z';
      repository.result = () => OrderDetailsDto.fromJson(revised).domain;
      await container
          .read(orderDetailsFoundationProvider(fixtureOrderId).notifier)
          .refresh();
      await tester.pumpAndSettle();
      expect(listInvalidations, 1);
      repository.result = () => mh09Details(capabilities: mh09Capabilities());
      await container
          .read(orderDetailsFoundationProvider(fixtureOrderId).notifier)
          .refresh();
      await tester.pumpAndSettle();
      expect(
        find.text('Dữ liệu đã thay đổi. Làm mới trước khi tiếp tục.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('order-action-submit')),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Giữ nguyên lý do đang nhập'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
