import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/features/orders/domain/models/order_details.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_order_details_page.dart';
import 'package:sports_store/features/orders/presentation/view_models/order_providers.dart';

import 'mh09_page_test_support.dart';

void main() {
  testWidgets('keeps delivery, COD and return lifecycles separate', (
    tester,
  ) async {
    final repository = Mh09PageOrders(
      () => mh09Details(
        status: 'delivered',
        deliverySummary: mh09DeliverySummary(),
        codSummary: mh09CodSummary(),
        returnSummaries: [mh09ReturnSummary()],
      ),
    );
    await tester.pumpWidget(mh09PageHost(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('Đã giao hàng'), findsOneWidget);
    expect(find.text('Giao thất bại'), findsOneWidget);
    expect(find.text('Shipper đã thu'), findsOneWidget);
    expect(find.text('Chờ duyệt'), findsOneWidget);
    expect(find.text('Không liên lạc được người nhận'), findsNWidgets(2));
    expect(find.text('Đã hủy'), findsNothing);
  });

  testWidgets('shows loading then safe error without placeholder details', (
    tester,
  ) async {
    final completer = Completer<OrderDetails>();
    final repository = Mh09PageOrders(() => completer.future);
    await tester.pumpWidget(mh09PageHost(repository: repository));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining(fixtureOrderId), findsNothing);

    completer.completeError(const AppFailure(code: AppFailure.network));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Không thể kết nối. Kiểm tra mạng và thử lại.'),
      findsOneWidget,
    );
    expect(find.textContaining(fixtureOrderId), findsNothing);
  });

  testWidgets('fails closed for customer even when the order belongs to them', (
    tester,
  ) async {
    final repository = Mh09PageOrders(() => mh09Details());
    await tester.pumpWidget(
      mh09PageHost(repository: repository, scope: mh09CustomerScope),
    );
    await tester.pumpAndSettle();

    expect(find.text('Không thể truy cập dữ liệu'), findsOneWidget);
    expect(find.text('Đang tải dữ liệu'), findsNothing);
    expect(repository.detailCalls, 0);
  });

  testWidgets(
    'refresh failure retains read-only detail then denial clears it',
    (tester) async {
      final repository = Mh09PageOrders(
        () => mh09Details(capabilities: mh09Capabilities(confirm: true)),
      );
      await tester.pumpWidget(mh09PageHost(repository: repository));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ManagerOrderDetailsPage)),
      );
      final notifier = container.read(
        orderDetailsFoundationProvider(fixtureOrderId).notifier,
      );
      final pending = Completer<OrderDetails>();
      repository.result = () => pending.future;
      final refresh = notifier.refresh();
      await tester.pump();
      expect(find.text('Sản phẩm minh họa'), findsOneWidget);
      final confirm = find.byKey(const ValueKey('mh09-action-confirm'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      pending.completeError(const AppFailure(code: AppFailure.network));
      await refresh;
      await tester.pump();
      expect(find.text('Dữ liệu có thể chưa cập nhật'), findsOneWidget);
      expect(find.text('Sản phẩm minh họa'), findsOneWidget);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      repository.result = () =>
          throw const AppFailure(code: AppFailure.forbiddenOrUnavailable);
      await notifier.refresh();
      await tester.pump();
      expect(find.text('Sản phẩm minh họa'), findsNothing);
      expect(find.textContaining(fixtureOrderId), findsNothing);
      expect(find.text('Không thể truy cập dữ liệu'), findsOneWidget);
    },
  );
}
