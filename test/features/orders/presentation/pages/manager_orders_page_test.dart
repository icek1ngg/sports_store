import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/features/orders/domain/models/order_page.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_orders_page.dart';

import '../../../../fixtures/order_list_page_fixtures.dart';
import 'mh08/mh08_page_test_support.dart';

void main() {
  testWidgets('renders manager counters from canonical page, not loaded rows', (
    tester,
  ) async {
    final repository = OrderListFixtureRepository(
      managerPage: listFixturePage(
        totalCount: 6,
        counts: listFixtureCounts(pending: 2, delivering: 3),
      ),
    );
    final container = createMh08Container(repository);
    await pumpMh08Page(
      tester,
      container,
      const ManagerOrdersPage(enablePolling: false),
    );
    expect(find.text('6 đơn hàng'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mh08-kpi-value-Chờ xác nhận')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mh08-kpi-value-Đang giao')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    await finishMh08Test(tester, container);
  });

  testWidgets('handles loading and unavailable error states', (tester) async {
    final completer = Completer<OrderPage>();
    final loadingRepository = OrderListFixtureRepository(
      managerPageLoader: (_) => completer.future,
    );
    final loadingContainer = createMh08Container(loadingRepository);
    await tester.pumpWidget(
      mh08Host(loadingContainer, const ManagerOrdersPage(enablePolling: false)),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    completer.complete(
      listFixturePage(
        items: const [],
        totalCount: 0,
        counts: listFixtureCounts(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chưa có đơn hàng cần xử lý'), findsOneWidget);

    final errorRepository = OrderListFixtureRepository(
      managerFailure: const AppFailure(
        code: AppFailure.externalDependencyUnavailable,
      ),
    );
    final errorContainer = createMh08Container(errorRepository);
    await pumpMh08Page(
      tester,
      errorContainer,
      const ManagerOrdersPage(enablePolling: false),
    );
    loadingContainer.dispose();
    await tester.pump();
    expect(
      find.text('Thao tác hiện chưa khả dụng. Vui lòng thử lại sau.'),
      findsOneWidget,
    );
    await finishMh08Test(tester, errorContainer);
  });

  testWidgets('manager page remains usable across responsive viewports', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const viewports = [
      Size(320, 640),
      Size(360, 740),
      Size(412, 820),
      Size(640, 320),
    ];
    for (final viewport in viewports) {
      tester.view
        ..physicalSize = viewport
        ..devicePixelRatio = 1;
      final repository = OrderListFixtureRepository(
        managerPage: listFixturePage(),
      );
      final container = createMh08Container(repository);
      await tester.pumpWidget(
        mh08Host(
          container,
          const ManagerOrdersPage(enablePolling: false),
          size: viewport,
          largeText: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await finishMh08Test(tester, container);
    }
  });
}
