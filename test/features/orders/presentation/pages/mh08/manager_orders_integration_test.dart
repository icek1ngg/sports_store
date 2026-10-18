import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/orders/domain/models/order_page.dart';
import 'package:sports_store/features/orders/domain/models/order_query.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_orders_page.dart';
import 'package:sports_store/features/orders/presentation/view_models/order_providers.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_buyer_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_card_actions.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_header.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_item_preview.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_kpi_strip.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_order_card.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_search_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_status_chips.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_payment_section.dart';
import 'package:sports_store/shared/widgets/async_content.dart';

import '../../../../../fixtures/order_list_page_fixtures.dart';
import 'mh08_page_test_support.dart';

const _secondManagerScope = SessionScope(
  userId: '90000000-0000-4000-8000-000000000002',
  role: 'manager',
  generation: 2,
);

void main() {
  testWidgets('uses provider wiring and renders the MH08 composition', (
    tester,
  ) async {
    final repository = OrderListFixtureRepository(
      managerPage: listFixturePage(
        counts: listFixtureCounts(pending: 1, delivering: 2),
        items: [
          listFixtureSummary(
            capabilities: listFixtureCapabilities(
              canConfirm: true,
              canReject: true,
            ),
          ),
        ],
      ),
    );
    final container = createMh08Container(repository);
    await pumpMh08Page(
      tester,
      container,
      const ManagerOrdersPage(enablePolling: false),
    );

    expect(repository.managerQueries, isNotEmpty);
    expect(find.byType(Mh08Header), findsOneWidget);
    expect(find.byType(Mh08SearchSection), findsOneWidget);
    expect(find.byType(Mh08KpiStrip), findsOneWidget);
    expect(find.byType(Mh08StatusChips), findsOneWidget);
    expect(find.byType(Mh08OrderCard), findsOneWidget);
    expect(find.byType(Mh08BuyerSection), findsOneWidget);
    expect(find.byType(Mh08ItemPreview), findsOneWidget);
    expect(find.byType(Mh08PaymentSection), findsOneWidget);
    expect(find.byType(Mh08CardActions), findsOneWidget);
    await finishMh08Test(tester, container);
  });

  testWidgets(
    'echoes edits immediately, debounces the query, clears search, and keeps cursor canonical',
    (tester) async {
      final repository = OrderListFixtureRepository(
        managerPageLoader: (_) => listFixturePage(
          nextCursor: 'cursor-query',
          counts: listFixtureCounts(delivering: 1),
        ),
      );
      final container = createMh08Container(repository);
      await pumpMh08Page(
        tester,
        container,
        const ManagerOrdersPage(enablePolling: false),
      );
      repository.managerQueries.clear();

      final field = find.byKey(const ValueKey('mh08-search-field'));
      await tester.enterText(field, 'buyer');
      expect(tester.widget<TextField>(field).controller!.text, 'buyer');
      await tester.pump(const Duration(milliseconds: 349));
      expect(repository.managerQueries, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(repository.managerQueries.last.search, 'buyer');
      expect(repository.managerQueries.last.cursor, isNull);

      final statusFilter = find.widgetWithText(FilterChip, 'Đang giao');
      await tester.ensureVisible(statusFilter);
      await tester.tap(statusFilter);
      await tester.pumpAndSettle();
      expect(repository.managerQueries.last.statuses, [OrderStatus.delivering]);
      expect(repository.managerQueries.last.cursor, isNull);

      await tester.tap(find.byTooltip('Xóa tìm kiếm'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(repository.managerQueries.last.search, isNull);
      expect(repository.managerQueries.last.statuses, [OrderStatus.delivering]);
      expect(repository.managerQueries.last.cursor, isNull);
      await tester.tap(statusFilter);
      await tester.pumpAndSettle();
      expect(repository.managerQueries.last.statuses, isEmpty);
      expect(repository.managerQueries.last.cursor, isNull);
      await finishMh08Test(tester, container);
    },
  );

  testWidgets('rejects a 201-scalar Unicode search without querying', (
    tester,
  ) async {
    final repository = OrderListFixtureRepository(
      managerPage: listFixturePage(),
    );
    final container = createMh08Container(repository);
    await pumpMh08Page(
      tester,
      container,
      const ManagerOrdersPage(enablePolling: false),
    );
    repository.managerQueries.clear();
    final oversized = String.fromCharCodes(List.filled(201, 0x1f600));
    final field = find.byKey(const ValueKey('mh08-search-field'));
    await tester.enterText(field, oversized);
    expect(tester.widget<TextField>(field).controller!.text, oversized);
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      find.text('Từ khóa tìm kiếm tối đa 200 ký tự Unicode.'),
      findsOneWidget,
    );
    expect(repository.managerQueries, isEmpty);
    await finishMh08Test(tester, container);
  });

  testWidgets('capability false keeps decision actions closed', (tester) async {
    final repository = OrderListFixtureRepository(
      managerPage: listFixturePage(),
    );
    final container = createMh08Container(repository);
    await pumpMh08Page(
      tester,
      container,
      const ManagerOrdersPage(enablePolling: false),
    );

    final confirm = find.byKey(const ValueKey('mh08-confirm'));
    final reject = find.byKey(const ValueKey('mh08-reject'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(tester.widget<FilledButton>(reject).onPressed, isNull);
    await tester.ensureVisible(confirm);
    await tester.pump();
    await tester.tap(confirm);
    await tester.ensureVisible(reject);
    await tester.pump();
    await tester.tap(reject);
    await tester.pump();
    expect(find.byKey(const ValueKey('order-action-submit')), findsNothing);
    await finishMh08Test(tester, container);
  });

  testWidgets('opens the exact UUID supplied by the order summary', (
    tester,
  ) async {
    String? openedOrderId;
    final repository = OrderListFixtureRepository(
      managerPage: listFixturePage(),
    );
    final container = createMh08Container(repository);
    await pumpMh08Page(
      tester,
      container,
      ManagerOrdersPage(
        enablePolling: false,
        onOpenOrder: (orderId) => openedOrderId = orderId,
      ),
    );

    final detail = find.text('Xem chi tiết đơn hàng');
    await tester.ensureVisible(detail);
    await tester.pump();
    await tester.tap(detail);
    expect(openedOrderId, listFixtureOrderId);
    await finishMh08Test(tester, container);
  });

  testWidgets('dialog fails closed after list cache invalidation', (
    tester,
  ) async {
    final repository = OrderListFixtureRepository(
      managerPage: listFixturePage(
        items: [
          listFixtureSummary(
            capabilities: listFixtureCapabilities(
              canConfirm: true,
              canReject: true,
            ),
          ),
        ],
      ),
    );
    final container = createMh08Container(repository);
    await pumpMh08Page(
      tester,
      container,
      const ManagerOrdersPage(enablePolling: false),
    );
    final confirm = find.byKey(const ValueKey('mh08-confirm'));
    await tester.ensureVisible(confirm);
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('order-action-submit')), findsOneWidget);

    container.read(epochCacheProvider).invalidatePrefix('orders/list/');
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
    await finishMh08Test(tester, container);
  });

  testWidgets(
    'dialog expiry hides private content without disposed ref errors',
    (tester) async {
      final repository = OrderListFixtureRepository(
        managerPage: listFixturePage(
          items: [
            listFixtureSummary(
              capabilities: listFixtureCapabilities(
                canConfirm: true,
                canReject: true,
              ),
            ),
          ],
        ),
      );
      final container = createMh08Container(repository);
      await pumpMh08Page(
        tester,
        container,
        const ManagerOrdersPage(enablePolling: false),
      );
      final reject = find.byKey(const ValueKey('mh08-reject'));
      await tester.ensureVisible(reject);
      await tester.pump();
      await tester.tap(reject);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('order-action-reason')),
        'Private reason',
      );
      final cache = container.read(epochCacheProvider);
      cache.blockSession();
      await tester.pump();
      expect(find.text('Private reason'), findsNothing);
      expect(find.byKey(const ValueKey('order-action-submit')), findsNothing);
      expect(find.byType(SessionExpiredState), findsAtLeastNWidgets(1));

      await tester.pumpWidget(const SizedBox());
      cache.invalidatePrefix('orders/');
      await tester.pump();
      expect(tester.takeException(), isNull);
      await finishMh08Test(tester, container);
    },
  );

  testWidgets(
    'session switch drops late canonical and next private responses',
    (tester) async {
      var scope = mh08ManagerScope;
      final lateCanonical = Completer<OrderPage>();
      final lateNext = Completer<OrderPage>();
      final newCanonical = Completer<OrderPage>();
      var canonicalReads = 0;
      var lateCanonicalStarted = false;
      var lateNextStarted = false;
      final repository = OrderListFixtureRepository(
        managerPageLoader: (query) {
          if (query.cursor != null) {
            lateNextStarted = true;
            return lateNext.future;
          }
          canonicalReads++;
          if (scope == mh08ManagerScope && canonicalReads == 1) {
            return listFixturePage(nextCursor: 'cursor-old');
          }
          if (scope == mh08ManagerScope) {
            lateCanonicalStarted = true;
            return lateCanonical.future;
          }
          return newCanonical.future;
        },
      );
      final container = createMh08Container(
        repository,
        scopeFactory: () => scope,
      );
      await pumpMh08Page(
        tester,
        container,
        const ManagerOrdersPage(enablePolling: false),
      );
      expect(find.text(listFixtureOrderId), findsOneWidget);

      await requestMh08LoadMoreIfVisible(tester);
      expect(lateNextStarted, isTrue);
      unawaited(
        container
            .read(orderListFoundationProvider(OrderQuery()).notifier)
            .refresh(),
      );
      await tester.pump();
      expect(lateCanonicalStarted, isTrue);

      scope = _secondManagerScope;
      container.invalidate(featureSessionScopeProvider);
      await tester.pump();
      await tester.pump();
      expect(find.text(listFixtureOrderId), findsNothing);

      lateCanonical.complete(listFixturePage(items: [listFixtureSummary()]));
      lateNext.complete(
        listFixturePage(
          items: [
            listFixtureSummary(
              id: listFixtureThirdOrderId,
              status: OrderStatus.preparing,
            ),
          ],
        ),
      );
      await tester.pump();
      expect(find.text(listFixtureOrderId), findsNothing);
      expect(find.text(listFixtureThirdOrderId), findsNothing);

      newCanonical.complete(
        listFixturePage(
          items: [
            listFixtureSummary(
              id: listFixtureSecondOrderId,
              status: OrderStatus.delivering,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(listFixtureOrderId), findsNothing);
      expect(find.text(listFixtureSecondOrderId), findsOneWidget);
      await finishMh08Test(tester, container);
    },
  );
}
