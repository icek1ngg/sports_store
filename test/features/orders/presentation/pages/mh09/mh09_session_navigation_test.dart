import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/orders/domain/models/order_details.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_order_details_page.dart';

import 'mh09_page_test_support.dart';

void main() {
  testWidgets('dialog fails closed when its source page is unmounted', (
    tester,
  ) async {
    final showPage = ValueNotifier(true);
    addTearDown(showPage.dispose);
    final repository = Mh09PageOrders(
      () => mh09Details(capabilities: mh09Capabilities(confirm: true)),
    );
    await tester.pumpWidget(
      mh09PageHost(
        repository: repository,
        pageOverride: ValueListenableBuilder<bool>(
          valueListenable: showPage,
          builder: (_, visible, _) => visible
              ? const ManagerOrderDetailsPage(
                  orderId: fixtureOrderId,
                  enablePolling: false,
                )
              : const Scaffold(body: Text('Source page removed')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mh09-action-confirm')));
    await tester.pumpAndSettle();
    final submit = find.byKey(const ValueKey('order-action-submit'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);

    showPage.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(ManagerOrderDetailsPage), findsNothing);
    expect(submit, findsOneWidget);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.text('Dữ liệu đã thay đổi. Làm mới trước khi tiếp tục.'),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    expect(repository.detailCalls, 1);
  });

  testWidgets('session expiry clears an open dialog and private detail', (
    tester,
  ) async {
    final repository = Mh09PageOrders(
      () => mh09Details(capabilities: mh09Capabilities(reject: true)),
    );
    await tester.pumpWidget(mh09PageHost(repository: repository));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ManagerOrderDetailsPage)),
    );
    await tester.tap(find.text('Từ chối đơn'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('order-action-reason')),
      'Private reason from manager session',
    );
    await tester.pumpWidget(
      mh09PageHost(
        repository: repository,
        scope: const SessionScope(userId: null, role: null, generation: 2),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp))),
      same(container),
    );
    expect(find.text('Không thể tiếp tục thao tác'), findsOneWidget);
    expect(find.byKey(const ValueKey('order-action-submit')), findsNothing);
    expect(find.text('Private reason from manager session'), findsNothing);
    expect(find.text('Sản phẩm minh họa'), findsNothing);
    expect(find.textContaining(fixtureOrderId), findsNothing);
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    expect(find.text('Phiên đăng nhập đã hết hạn'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late detail cannot reveal data after session expiry', (
    tester,
  ) async {
    final pending = Completer<OrderDetails>();
    final repository = Mh09PageOrders(() => pending.future);
    await tester.pumpWidget(mh09PageHost(repository: repository));
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ManagerOrderDetailsPage)),
    );
    expect(repository.detailCalls, 1);
    await tester.pumpWidget(
      mh09PageHost(
        repository: repository,
        scope: const SessionScope(userId: null, role: null, generation: 2),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp))),
      same(container),
    );
    pending.complete(mh09Details());
    await tester.pumpAndSettle();
    expect(find.text('Phiên đăng nhập đã hết hạn'), findsOneWidget);
    expect(find.text('Sản phẩm minh họa'), findsNothing);
    expect(find.textContaining(fixtureOrderId), findsNothing);
    expect(repository.detailCalls, 1);
    expect(tester.takeException(), isNull);
  });
}
