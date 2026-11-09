import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/features/orders/presentation/view_models/order_providers.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_order_details_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/domain/repositories/manager_dispatch_repository.dart';
import 'package:sports_store/features/orders/presentation/view_models/manager_dispatch_providers.dart';
import 'package:sports_store/features/orders/presentation/widgets/prepare_dispatch_dialog.dart';

import 'presentation/pages/mh09/mh09_page_test_support.dart';

class PageDispatch implements ManagerDispatchRepository {
  PageDispatch(this.orders);
  final Mh09PageOrders orders;
  int calls = 0;
  @override
  Future<List<DispatchShipper>> loadShippers() async => const [
    DispatchShipper(id: fixtureShipperId, name: 'Shipper giao hàng'),
  ];
  @override
  Future<void> prepareAndAssign({
    required String orderId,
    required String shipperId,
    required String requestId,
  }) async {
    calls++;
    orders.result = () => mh09Details(
      status: 'awaiting_pickup',
      capabilities: mh09Capabilities(managerCancel: true),
    );
  }
}

void main() {
  testWidgets('preparing page dispatches then refreshes to awaiting pickup', (
    tester,
  ) async {
    final orders = Mh09PageOrders(
      () => mh09Details(
        status: 'preparing',
        capabilities: mh09Capabilities(assign: true, managerCancel: true),
      ),
    );
    final dispatch = PageDispatch(orders);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          managerDispatchRepositoryProvider.overrideWithValue(dispatch),
          featureSessionScopeProvider.overrideWithValue(mh09ManagerScope),
          orderRepositoryProvider.overrideWithValue(orders),
          orderCommandControllerProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(
          home: ManagerOrderDetailsPage(
            orderId: fixtureOrderId,
            enablePolling: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chuẩn bị xong & phân công giao'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('mh09-action-prepare-dispatch')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shipper giao hàng').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xác nhận bàn giao'));
    await tester.pumpAndSettle();
    expect(dispatch.calls, 1);
    expect(find.byType(PrepareDispatchDialog), findsNothing);
    expect(find.text('Chờ shipper nhận hàng'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mh09-action-prepare-dispatch')),
      findsNothing,
    );
    expect(orders.detailCalls, greaterThan(1));
  });
}
