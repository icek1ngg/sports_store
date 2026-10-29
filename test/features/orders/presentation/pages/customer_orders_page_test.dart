import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/domain/models/order_page.dart';
import 'package:sports_store/features/orders/domain/models/order_query.dart';
import 'package:sports_store/features/orders/presentation/pages/customer_orders_page.dart';
import 'package:sports_store/features/orders/presentation/view_models/order_providers.dart';
import 'package:sports_store/shared/widgets/async_content.dart';

import '../../../../fixtures/order_list_page_fixtures.dart';

const _customerScope = SessionScope(
  userId: listFixtureCustomerId,
  role: 'customer',
  generation: 1,
);

ProviderContainer _container(OrderListFixtureRepository repository) {
  return ProviderContainer(
    overrides: [
      featureSessionScopeProvider.overrideWithValue(_customerScope),
      orderRepositoryProvider.overrideWithValue(repository),
    ],
  );
}

void _disposeAfterPump(WidgetTester tester, ProviderContainer container) {
  // Each test disposes its container in _finish before unmounting the tree.
}

Future<void> _finish(WidgetTester tester, ProviderContainer container) async {
  container.dispose();
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  await tester.pump();
}

Widget _host(
  ProviderContainer container,
  Widget child, {
  bool largeText = false,
  Size size = const Size(320, 900),
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: largeText
              ? const TextScaler.linear(2)
              : TextScaler.noScaling,
        ),
        child: child,
      ),
    ),
  );
}

Future<void> _pumpPage(
  WidgetTester tester,
  ProviderContainer container,
  CustomerOrdersPage page,
) async {
  await tester.pumpWidget(_host(container, page));
  await tester.pumpAndSettle();
}

Future<void> _requestCustomerLoadMoreIfVisible(WidgetTester tester) async {
  await tester.drag(find.byType(ListView).last, const Offset(0, -420));
  await tester.pump();
  final button = find.text('Tải thêm đơn hàng');
  if (button.evaluate().isNotEmpty) {
    await tester.ensureVisible(button);
    await tester.pump();
    if (button.evaluate().isNotEmpty) await tester.tap(button);
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders loading, empty and external error states', (
    tester,
  ) async {
    final loading = Completer<OrderPage>();
    final loadingRepository = OrderListFixtureRepository(
      customerPageLoader: (_) => loading.future,
    );
    final loadingContainer = _container(loadingRepository);
    _disposeAfterPump(tester, loadingContainer);
    await tester.pumpWidget(
      _host(loadingContainer, const CustomerOrdersPage(enablePolling: false)),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    loading.complete(
      listFixturePage(
        items: const [],
        totalCount: 0,
        counts: listFixtureCounts(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bạn chưa có đơn hàng'), findsOneWidget);

    final errorRepository = OrderListFixtureRepository(
      customerFailure: const AppFailure(
        code: AppFailure.externalDependencyUnavailable,
      ),
    );
    final errorContainer = _container(errorRepository);
    _disposeAfterPump(tester, errorContainer);
    await _pumpPage(
      tester,
      errorContainer,
      const CustomerOrdersPage(enablePolling: false),
    );
    loadingContainer.dispose();
    await tester.pump();
    expect(
      find.text('Thao tác hiện chưa khả dụng. Vui lòng thử lại sau.'),
      findsOneWidget,
    );
    await _finish(tester, errorContainer);
  });

  testWidgets('keeps canonical rows and count when refresh fails', (
    tester,
  ) async {
    final repository = OrderListFixtureRepository(
      customerPage: listFixturePage(
        totalCount: 3,
        counts: listFixtureCounts(pending: 3),
      ),
    );
    final container = _container(repository);
    _disposeAfterPump(tester, container);
    await _pumpPage(
      tester,
      container,
      const CustomerOrdersPage(enablePolling: false),
    );
    repository.customerFailure = const AppFailure(
      code: AppFailure.externalDependencyUnavailable,
    );
    await tester.tap(find.byTooltip('Làm mới đơn hàng'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text(listFixtureOrderId), findsOneWidget);
    expect(find.text('3 đơn hàng'), findsOneWidget);
    expect(find.text('Dữ liệu có thể chưa cập nhật'), findsAtLeastNWidgets(1));
    await _finish(tester, container);
  });

  testWidgets('debounces full server search and resets status cursor', (
    tester,
  ) async {
    final repository = OrderListFixtureRepository(
      customerPageLoader: (_) => listFixturePage(
        items: const [],
        totalCount: 0,
        counts: listFixtureCounts(),
      ),
    );
    final container = _container(repository);
    _disposeAfterPump(tester, container);
    await _pumpPage(
      tester,
      container,
      const CustomerOrdersPage(enablePolling: false),
    );
    repository.customerQueries.clear();
    await tester.enterText(find.byType(TextField), 'giày');
    await tester.pump(const Duration(milliseconds: 349));
    expect(repository.customerQueries, isEmpty);
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pumpAndSettle();
    expect(repository.customerQueries, isNotEmpty);
    expect(repository.customerQueries.last.search, 'giày');

    final queryCountBeforeLongInput = repository.customerQueries.length;
    await tester.enterText(find.byType(TextField), 'a' * 201);
    await tester.pump(const Duration(milliseconds: 351));
    expect(
      find.text('Từ khóa tìm kiếm tối đa 200 ký tự Unicode.'),
      findsOneWidget,
    );
    expect(repository.customerQueries.length, queryCountBeforeLongInput);

    await tester.tap(find.text('Chờ xác nhận'));
    await tester.pumpAndSettle();
    expect(repository.customerQueries.last.statuses, [
      OrderStatus.pendingConfirmation,
    ]);
    expect(repository.customerQueries.last.cursor, isNull);
    await _finish(tester, container);
  });

  testWidgets('appends a cursor page while keeping canonical count', (
    tester,
  ) async {
    final second = listFixtureSummary(
      id: listFixtureSecondOrderId,
      status: OrderStatus.preparing,
    );
    final repository = OrderListFixtureRepository(
      customerPageLoader: (query) {
        if (query.cursor == 'cursor-1') {
          return listFixturePage(
            items: [second],
            totalCount: 4,
            counts: listFixtureCounts(pending: 2, preparing: 2),
          );
        }
        return listFixturePage(
          nextCursor: 'cursor-1',
          totalCount: 4,
          counts: listFixtureCounts(pending: 2, preparing: 2),
        );
      },
    );
    final container = _container(repository);
    _disposeAfterPump(tester, container);
    await _pumpPage(
      tester,
      container,
      const CustomerOrdersPage(enablePolling: false),
    );
    await _requestCustomerLoadMoreIfVisible(tester);
    await tester.pumpAndSettle();
    expect(find.text(listFixtureSecondOrderId), findsOneWidget);
    expect(find.text('4 đơn hàng'), findsOneWidget);
    expect(
      repository.customerQueries.map((query) => query.cursor),
      contains('cursor-1'),
    );
    await _finish(tester, container);
  });

  testWidgets('clears customer rows when the next page loses private access', (
    tester,
  ) async {
    final repository = OrderListFixtureRepository(
      customerPageLoader: (query) {
        if (query.cursor != null) {
          throw const AppFailure(code: AppFailure.forbiddenOrUnavailable);
        }
        return listFixturePage(
          items: [
            listFixtureSummary(
              capabilities: listFixtureCapabilities(canCancelCustomer: true),
            ),
          ],
          nextCursor: 'cursor-private',
          counts: listFixtureCounts(pending: 1),
        );
      },
    );
    final container = _container(repository);
    _disposeAfterPump(tester, container);
    await _pumpPage(
      tester,
      container,
      const CustomerOrdersPage(enablePolling: false),
    );

    await _requestCustomerLoadMoreIfVisible(tester);
    await tester.pump();
    await tester.pump();

    expect(find.byType(SessionUnavailableState), findsOneWidget);
    expect(find.text(listFixtureOrderId), findsNothing);
    expect(find.text('1 đơn hàng'), findsNothing);
    expect(find.text('Hủy đơn'), findsNothing);
    expect(find.text('Tải lại trang tiếp theo'), findsNothing);
    await _finish(tester, container);
  });

  testWidgets(
    'does not restore rows from a head read already in flight after access loss',
    (tester) async {
      final lateHead = Completer<OrderPage>();
      final nextPage = Completer<OrderPage>();
      var canonicalReads = 0;
      final repository = OrderListFixtureRepository(
        customerPageLoader: (query) {
          if (query.cursor != null) return nextPage.future;
          canonicalReads++;
          if (canonicalReads == 1) {
            return listFixturePage(nextCursor: 'cursor-race');
          }
          return lateHead.future;
        },
      );
      final container = _container(repository);
      _disposeAfterPump(tester, container);
      await _pumpPage(
        tester,
        container,
        const CustomerOrdersPage(enablePolling: false),
      );

      await tester.drag(find.byType(ListView).last, const Offset(0, -420));
      await tester.pump();
      final loadMore = find.text('Tải thêm đơn hàng');
      if (loadMore.evaluate().isNotEmpty) {
        await tester.ensureVisible(loadMore);
        await tester.pump();
        if (loadMore.evaluate().isNotEmpty) await tester.tap(loadMore);
      }
      await tester.pump();

      final canonicalProvider = orderListFoundationProvider(OrderQuery());
      unawaited(container.read(canonicalProvider.notifier).refresh());
      await tester.pump();
      nextPage.completeError(
        const AppFailure(code: AppFailure.forbiddenOrUnavailable),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.byType(SessionUnavailableState), findsOneWidget);
      lateHead.complete(listFixturePage(nextCursor: 'cursor-race'));
      await tester.pumpAndSettle();

      expect(canonicalReads, greaterThanOrEqualTo(2));
      expect(find.byType(SessionUnavailableState), findsOneWidget);
      expect(find.text(listFixtureOrderId), findsNothing);
      await _finish(tester, container);
    },
  );

  testWidgets('resets an invalid customer cursor to the canonical head', (
    tester,
  ) async {
    var canonicalReads = 0;
    final repository = OrderListFixtureRepository(
      customerPageLoader: (query) {
        if (query.cursor != null) {
          throw const AppFailure(code: AppFailure.invalidCursor);
        }
        canonicalReads++;
        return listFixturePage(
          nextCursor: canonicalReads == 1 ? 'cursor-invalid' : null,
        );
      },
    );
    final container = _container(repository);
    _disposeAfterPump(tester, container);
    await _pumpPage(
      tester,
      container,
      const CustomerOrdersPage(enablePolling: false),
    );

    await _requestCustomerLoadMoreIfVisible(tester);

    expect(
      repository.customerQueries.where((query) => query.cursor != null),
      hasLength(1),
    );
    expect(repository.customerQueries.last.cursor, isNull);
    await _finish(tester, container);
  });

  testWidgets('keeps pagination enabled when refresh returns the same page', (
    tester,
  ) async {
    final page = listFixturePage(nextCursor: 'cursor-same');
    final repository = OrderListFixtureRepository(
      customerPageLoader: (query) {
        if (query.cursor != null) {
          throw const AppFailure(
            code: AppFailure.externalDependencyUnavailable,
          );
        }
        return page;
      },
    );
    final container = _container(repository);
    _disposeAfterPump(tester, container);
    await _pumpPage(
      tester,
      container,
      const CustomerOrdersPage(enablePolling: false),
    );
    await _requestCustomerLoadMoreIfVisible(tester);
    expect(find.text('Tải lại trang tiếp theo'), findsOneWidget);

    await tester.tap(find.byTooltip('Làm mới đơn hàng'));
    await tester.pumpAndSettle();

    await _requestCustomerLoadMoreIfVisible(tester);

    expect(find.text('Tải lại trang tiếp theo'), findsOneWidget);
    await _finish(tester, container);
  });

  testWidgets('role gate and session changes do not expose private rows', (
    tester,
  ) async {
    final repository = OrderListFixtureRepository(
      customerPage: listFixturePage(),
    );
    final container = ProviderContainer(
      overrides: [
        featureSessionScopeProvider.overrideWithValue(
          const SessionScope(
            userId: listFixtureCustomerId,
            role: 'manager',
            generation: 1,
          ),
        ),
        orderRepositoryProvider.overrideWithValue(repository),
      ],
    );
    _disposeAfterPump(tester, container);
    await tester.pumpWidget(
      _host(container, const CustomerOrdersPage(enablePolling: false)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SessionUnavailableState), findsOneWidget);
    expect(find.text(listFixtureOrderId), findsNothing);
    await _finish(tester, container);
  });

  testWidgets(
    'detail modal performs fresh aggregate read and return action can be unavailable',
    (tester) async {
      final delivered = listFixtureSummary(
        status: OrderStatus.delivered,
        capabilities: listFixtureCapabilities(canOpenReturnCreation: true),
      );
      final repository = OrderListFixtureRepository(
        customerPage: listFixturePage(
          items: [delivered],
          totalCount: 1,
          counts: listFixtureCounts(delivered: 1),
        ),
        details: listFixtureDetails(
          status: OrderStatus.delivered,
          capabilities: listFixtureCapabilities(canOpenReturnCreation: true),
        ),
      );
      final container = _container(repository);
      _disposeAfterPump(tester, container);
      await _pumpPage(
        tester,
        container,
        const CustomerOrdersPage(enablePolling: false),
      );
      expect(find.text('Yêu cầu trả hàng chưa khả dụng'), findsOneWidget);
      await tester.tap(find.text(listFixtureOrderId));
      await tester.pumpAndSettle();
      expect(find.textContaining('Chi tiết đơn hàng'), findsOneWidget);
      expect(find.text('Địa chỉ nhận hàng'), findsOneWidget);
      expect(repository.detailIds, [listFixtureOrderId]);
      await _finish(tester, container);
    },
  );

  testWidgets('active return navigation uses the server return id', (
    tester,
  ) async {
    String? openedReturnId;
    final repository = OrderListFixtureRepository(
      customerPage: listFixturePage(
        items: [
          listFixtureSummary(
            status: OrderStatus.delivered,
            returnSummary: listFixtureActiveReturn(),
          ),
        ],
        totalCount: 1,
        counts: listFixtureCounts(delivered: 1),
      ),
    );
    final container = _container(repository);
    _disposeAfterPump(tester, container);
    await _pumpPage(
      tester,
      container,
      CustomerOrdersPage(
        enablePolling: false,
        onOpenReturn: (returnId) => openedReturnId = returnId,
      ),
    );
    await tester.ensureVisible(find.text('Xem yêu cầu trả hàng'));
    await tester.pump();
    await tester.tap(find.text('Xem yêu cầu trả hàng'));
    expect(openedReturnId, listFixtureReturnId);
    await _finish(tester, container);
  });

  testWidgets('returning from detail keeps the active search query', (
    tester,
  ) async {
    final repository = OrderListFixtureRepository(
      customerPage: listFixturePage(),
      details: listFixtureDetails(),
    );
    final container = _container(repository);
    _disposeAfterPump(tester, container);
    await _pumpPage(
      tester,
      container,
      const CustomerOrdersPage(enablePolling: false),
    );
    repository.customerQueries.clear();
    await tester.enterText(find.byType(TextField), 'giày');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text(listFixtureOrderId), findsOneWidget);

    await tester.tap(find.text(listFixtureOrderId));
    await tester.pumpAndSettle();
    final detailContext = tester.element(
      find.textContaining('Chi tiết đơn hàng'),
    );
    Navigator.of(detailContext).pop();
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'giày',
    );
    expect(repository.customerQueries.last.search, 'giày');
    await _finish(tester, container);
  });

  testWidgets('detail sheet fails closed when the session changes', (
    tester,
  ) async {
    var scope = _customerScope;
    final repository = OrderListFixtureRepository(
      customerPage: listFixturePage(),
      details: listFixtureDetails(),
    );
    final container = ProviderContainer(
      overrides: [
        featureSessionScopeProvider.overrideWith((ref) => scope),
        orderRepositoryProvider.overrideWithValue(repository),
      ],
    );
    _disposeAfterPump(tester, container);
    await _pumpPage(
      tester,
      container,
      const CustomerOrdersPage(enablePolling: false),
    );
    await tester.tap(find.text(listFixtureOrderId));
    await tester.pumpAndSettle();
    expect(find.textContaining('Chi tiết đơn hàng'), findsOneWidget);
    expect(repository.detailIds, [listFixtureOrderId]);

    scope = const SessionScope(
      userId: '20000000-0000-4000-8000-000000000002',
      role: 'customer',
      generation: 2,
    );
    container.invalidate(featureSessionScopeProvider);
    await tester.pumpAndSettle();
    expect(find.text('Chi tiết đơn hàng hiện không khả dụng.'), findsOneWidget);
    expect(
      find.textContaining('Chi tiết đơn hàng\n$listFixtureOrderId'),
      findsNothing,
    );
    expect(repository.detailIds, [listFixtureOrderId]);
    await _finish(tester, container);
  });

  testWidgets(
    'return creation rechecks a fresh detail snapshot before navigation',
    (tester) async {
      String? openedOrderId;
      final deliveredCapabilities = listFixtureCapabilities(
        canOpenReturnCreation: true,
      );
      final repository = OrderListFixtureRepository(
        customerPage: listFixturePage(
          items: [
            listFixtureSummary(
              status: OrderStatus.delivered,
              capabilities: deliveredCapabilities,
            ),
          ],
          counts: listFixtureCounts(delivered: 1),
        ),
        details: listFixtureDetails(
          status: OrderStatus.delivered,
          capabilities: deliveredCapabilities,
        ),
      );
      final container = _container(repository);
      _disposeAfterPump(tester, container);
      await _pumpPage(
        tester,
        container,
        CustomerOrdersPage(
          enablePolling: false,
          onCreateReturn: (orderId) => openedOrderId = orderId,
        ),
      );
      await tester.tap(find.text(listFixtureOrderId));
      await tester.pumpAndSettle();
      final eligibleReturn = find.descendant(
        of: find.byType(ListView).last,
        matching: find.text('Yêu cầu trả hàng'),
      );
      await tester.scrollUntilVisible(
        eligibleReturn,
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(eligibleReturn, findsOneWidget);

      repository.detailFailure = const AppFailure(
        code: AppFailure.externalDependencyUnavailable,
      );
      final detailContainer = ProviderScope.containerOf(
        tester.element(find.byType(ListView).last),
      );
      detailContainer
          .read(epochCacheProvider)
          .invalidate('orders/detail/$listFixtureOrderId');
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pumpAndSettle();

      final unavailable = find.descendant(
        of: find.byType(ListView).last,
        matching: find.widgetWithText(
          OutlinedButton,
          'Yêu cầu trả hàng chưa khả dụng',
        ),
      );
      await tester.scrollUntilVisible(
        unavailable,
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(unavailable, findsOneWidget);
      expect(tester.widget<OutlinedButton>(unavailable).onPressed, isNull);
      await tester.tap(unavailable);
      expect(openedOrderId, isNull);
      await _finish(tester, container);
    },
  );

  testWidgets(
    'action dialog rechecks capability after canonical invalidation',
    (tester) async {
      final repository = OrderListFixtureRepository(
        customerPage: listFixturePage(
          counts: listFixtureCounts(pending: 1),
          items: [
            listFixtureSummary(
              capabilities: listFixtureCapabilities(canCancelCustomer: true),
            ),
          ],
        ),
      );
      final container = _container(repository);
      _disposeAfterPump(tester, container);
      await _pumpPage(
        tester,
        container,
        const CustomerOrdersPage(enablePolling: false),
      );
      await tester.ensureVisible(find.text('Hủy đơn'));
      await tester.pump();
      await tester.tap(find.text('Hủy đơn'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('order-action-submit')), findsOneWidget);
      container.read(epochCacheProvider).invalidatePrefix('orders/list/');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('order-action-submit')));
      await tester.pump();
      expect(
        find.text('Dữ liệu đã thay đổi. Làm mới trước khi tiếp tục.'),
        findsOneWidget,
      );
      await _finish(tester, container);
    },
  );

  testWidgets('customer page remains usable across responsive viewports', (
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
        customerPage: listFixturePage(),
      );
      final container = _container(repository);
      _disposeAfterPump(tester, container);
      await tester.pumpWidget(
        _host(
          container,
          const CustomerOrdersPage(enablePolling: false),
          largeText: true,
          size: viewport,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _finish(tester, container);
    }
  });
}
