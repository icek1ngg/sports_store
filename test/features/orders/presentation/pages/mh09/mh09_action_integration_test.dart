import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/features/orders/domain/models/order_details.dart';
import 'package:sports_store/features/orders/domain/models/order_operation.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_order_details_page.dart';
import 'package:sports_store/features/orders/presentation/pages/mh09/mh09_detail_body.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_action_footer.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_header.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_action_dialog.dart';
import 'package:sports_store/features/orders/presentation/view_models/order_providers.dart';

import 'mh09_page_test_support.dart';

void main() {
  final operationCases = <OrderOperation, Map<String, Object?>>{
    OrderOperation.confirm: mh09Capabilities(confirm: true),
    OrderOperation.reject: mh09Capabilities(reject: true),
    OrderOperation.managerCancel: mh09Capabilities(managerCancel: true),
  };

  for (final entry in operationCases.entries) {
    testWidgets(
      '${entry.key.wireValue} renders only its eligible footer action',
      (tester) async {
        final repository = Mh09PageOrders(
          () => mh09Details(capabilities: entry.value),
        );
        await tester.pumpWidget(mh09PageHost(repository: repository));
        await tester.pumpAndSettle();

        expect(find.byType(Mh09ActionFooter), findsOneWidget);
        final keys = {
          OrderOperation.confirm: const ValueKey('mh09-action-confirm'),
          OrderOperation.reject: const ValueKey('mh09-action-reject'),
          OrderOperation.managerCancel: const ValueKey(
            'mh09-action-manager-cancel',
          ),
        };
        expect(find.byKey(keys[entry.key]!), findsOneWidget);
        for (final other in keys.entries) {
          if (other.key != entry.key) {
            expect(find.byKey(other.value), findsNothing);
          }
        }

        await tester.tap(find.byKey(keys[entry.key]!));
        await tester.pumpAndSettle();
        final dialog = tester.widget<OrderActionDialog>(
          find.byType(OrderActionDialog),
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(ManagerOrderDetailsPage)),
        );
        expect(dialog.operation, entry.key);
        expect(dialog.submittedScope, mh09ManagerScope);
        expect(dialog.sourceCache, same(container.read(epochCacheProvider)));
        await tester.tap(find.text('Đóng'));
        await tester.pumpAndSettle();
        expect(find.byType(OrderActionDialog), findsNothing);
      },
    );
  }

  testWidgets('pending order without command capabilities has no footer', (
    tester,
  ) async {
    final repository = Mh09PageOrders(() => mh09Details());
    await tester.pumpWidget(mh09PageHost(repository: repository));
    await tester.pumpAndSettle();

    expect(find.byType(Mh09ActionFooter), findsNothing);
    expect(find.byKey(const ValueKey('mh09-action-confirm')), findsNothing);
    expect(find.byKey(const ValueKey('mh09-action-reject')), findsNothing);
    expect(
      find.byKey(const ValueKey('mh09-action-manager-cancel')),
      findsNothing,
    );
  });

  testWidgets(
    'captured footer action fails closed after capability revocation',
    (tester) async {
      final repository = Mh09PageOrders(
        () => mh09Details(capabilities: mh09Capabilities(confirm: true)),
      );
      await tester.pumpWidget(mh09PageHost(repository: repository));
      await tester.pumpAndSettle();
      final captured = tester
          .widget<Mh09ActionFooter>(find.byType(Mh09ActionFooter))
          .onAction!;
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ManagerOrderDetailsPage)),
      );
      repository.result = () => mh09Details();
      await container
          .read(orderDetailsFoundationProvider(fixtureOrderId).notifier)
          .refresh();
      await tester.pumpAndSettle();

      expect(find.byType(Mh09ActionFooter), findsNothing);
      captured(OrderOperation.confirm);
      await tester.pump();
      expect(find.byType(OrderActionDialog), findsNothing);
    },
  );

  testWidgets(
    'captured footer action cannot open while read is busy and stale',
    (tester) async {
      final details = mh09Details(
        capabilities: mh09Capabilities(confirm: true),
      );
      final pending = Completer<OrderDetails>();
      final repository = Mh09PageOrders(() => details);
      await tester.pumpWidget(mh09PageHost(repository: repository));
      await tester.pumpAndSettle();
      final captured = tester
          .widget<Mh09ActionFooter>(find.byType(Mh09ActionFooter))
          .onAction!;
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ManagerOrderDetailsPage)),
      );
      // Keep the first accepted projection while the next read is pending.
      repository.result = () => pending.future;
      final refresh = container
          .read(orderDetailsFoundationProvider(fixtureOrderId).notifier)
          .refresh();
      await tester.pump();

      final footer = tester.widget<Mh09ActionFooter>(
        find.byType(Mh09ActionFooter),
      );
      expect(footer.isBusy, isTrue);
      expect(footer.isActionStateFresh, isFalse);
      captured(OrderOperation.confirm);
      await tester.pump();
      expect(find.byType(OrderActionDialog), findsNothing);

      pending.complete(details);
      await refresh;
      await tester.pumpAndSettle();
      expect(find.byType(OrderActionDialog), findsNothing);
      expect(repository.detailCalls, 2);
    },
  );

  testWidgets('header and body refresh share one in-flight read', (
    tester,
  ) async {
    final details = mh09Details();
    final pending = Completer<OrderDetails>();
    final repository = Mh09PageOrders(() => details);
    await tester.pumpWidget(mh09PageHost(repository: repository));
    await tester.pumpAndSettle();
    final header = tester.widget<Mh09Header>(find.byType(Mh09Header));
    final body = tester.widget<Mh09DetailBody>(find.byType(Mh09DetailBody));
    repository.result = () => pending.future;

    header.onRefresh!();
    final bodyRefresh = body.onRefresh();
    await tester.pump();
    expect(repository.detailCalls, 2);
    await bodyRefresh;
    expect(repository.detailCalls, 2);

    pending.complete(details);
    await tester.pumpAndSettle();
    expect(repository.detailCalls, 2);
  });

  testWidgets('confirm and reject can reopen for three validation cycles', (
    tester,
  ) async {
    final repository = Mh09PageOrders(
      () => mh09Details(
        capabilities: mh09Capabilities(confirm: true, reject: true),
      ),
    );
    await tester.pumpWidget(mh09PageHost(repository: repository));
    await tester.pumpAndSettle();

    for (var cycle = 0; cycle < 3; cycle++) {
      await tester.tap(find.byKey(const ValueKey('mh09-action-confirm')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('order-action-submit')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey('order-action-submit')));
      await tester.pump();
      expect(
        find.text('Thao tác hiện chưa khả dụng. Vui lòng thử lại sau.'),
        findsOneWidget,
      );
      expect(find.text('Đã xác nhận'), findsNothing);
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('mh09-action-reject')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('order-action-submit')));
      await tester.pump();
      expect(find.text('Vui lòng nhập lý do trước khi gửi.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('order-action-reason')),
        'Lý do hợp lệ cho chu kỳ $cycle',
      );
      await tester.tap(find.byKey(const ValueKey('order-action-submit')));
      await tester.pump();
      expect(
        find.text('Thao tác hiện chưa khả dụng. Vui lòng thử lại sau.'),
        findsOneWidget,
      );
      expect(find.text('Đã từ chối'), findsNothing);
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
    }

    expect(repository.detailCalls, 1);
    expect(find.byType(OrderActionDialog), findsNothing);
  });
}
