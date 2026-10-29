import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_order_details_page.dart';
import 'package:sports_store/features/orders/presentation/view_models/order_providers.dart';

import 'mh09_page_test_support.dart';

void main() {
  testWidgets('validates reject reason and reports unavailable dependency', (
    tester,
  ) async {
    final repository = Mh09PageOrders(
      () => mh09Details(capabilities: mh09Capabilities(reject: true)),
    );
    await tester.pumpWidget(mh09PageHost(repository: repository));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Từ chối đơn'));
    await tester.tap(find.text('Từ chối đơn'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('order-action-reason')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('order-action-submit')));
    await tester.pump();
    expect(find.text('Vui lòng nhập lý do trước khi gửi.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('order-action-reason')),
      'Hết hàng sau khi kiểm tra',
    );
    await tester.tap(find.byKey(const ValueKey('order-action-submit')));
    await tester.pump();
    expect(
      find.text('Thao tác hiện chưa khả dụng. Vui lòng thử lại sau.'),
      findsOneWidget,
    );
    expect(find.text('Đã từ chối'), findsNothing);
  });

  testWidgets(
    'keeps external actions disabled and callback destinations safe',
    (tester) async {
      final repository = Mh09PageOrders(
        () => mh09Details(
          deliverySummary: mh09DeliverySummary(),
          codSummary: mh09CodSummary(),
          returnSummaries: [mh09ReturnSummary()],
          capabilities: mh09Capabilities(
            assign: true,
            reassign: true,
            retry: true,
            earlyReturn: true,
            receive: true,
          ),
        ),
      );
      await tester.pumpWidget(mh09PageHost(repository: repository));
      await tester.pumpAndSettle();

      expect(
        find.text('Chưa khả dụng: Dịch vụ giao hàng chưa sẵn sàng.'),
        findsNWidgets(4),
      );
      expect(find.text('Phân công'), findsOneWidget);
      expect(find.text('Phân công lại'), findsOneWidget);
      expect(find.text('Giao lần hai'), findsOneWidget);
      expect(find.text('Hoàn hàng sớm'), findsOneWidget);
      expect(find.text('Nhận và kiểm tra hàng'), findsOneWidget);
      expect(
        find.text('Điều hướng đối soát COD chưa khả dụng'),
        findsOneWidget,
      );
      expect(
        find.text('Điều hướng xử lý trả hàng chưa khả dụng'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Điều hướng trò chuyện chưa khả dụng.'),
        findsOneWidget,
      );

      final disabled = tester.widgetList<OutlinedButton>(
        find.byType(OutlinedButton),
      );
      expect(disabled.any((button) => button.onPressed == null), isTrue);
    },
  );

  testWidgets('dialog checks refreshed capability before continuing', (
    tester,
  ) async {
    final repository = Mh09PageOrders(
      () => mh09Details(capabilities: mh09Capabilities(confirm: true)),
    );
    await tester.pumpWidget(mh09PageHost(repository: repository));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ManagerOrderDetailsPage)),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('mh09-action-confirm')),
    );
    await tester.tap(find.byKey(const ValueKey('mh09-action-confirm')));
    await tester.pumpAndSettle();
    repository.result = () => mh09Details(capabilities: mh09Capabilities());
    await container
        .read(orderDetailsFoundationProvider(fixtureOrderId).notifier)
        .refresh();
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
    expect(repository.detailCalls, 2);
  });
}
