import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mh09_page_test_support.dart';

void main() {
  testWidgets('forwards callback destinations from the current projection', (
    tester,
  ) async {
    String? openedCod;
    String? openedReturn;
    String? openedChat;
    String? calledPhone;
    final repository = Mh09PageOrders(
      () => mh09Details(
        status: 'delivered',
        buyer: {'id': fixtureCustomerId, 'full_name': 'Người mua minh họa'},
        deliverySummary: mh09DeliverySummary(),
        codSummary: mh09CodSummary(),
        returnSummaries: [mh09ReturnSummary()],
      ),
    );
    await tester.pumpWidget(
      mh09PageHost(
        repository: repository,
        onOpenCod: (orderId) => openedCod = orderId,
        onOpenReturn: (returnId) => openedReturn = returnId,
        onOpenChat: (customerId) => openedChat = customerId,
        onCallRecipient: (phone) => calledPhone = phone,
      ),
    );
    await tester.pumpAndSettle();

    final cod = find.text('Mở đối soát COD');
    await tester.ensureVisible(cod);
    await tester.tap(cod);
    await tester.pump();
    expect(openedCod, fixtureOrderId);

    final returnAction = find.text('Mở xử lý trả hàng');
    await tester.ensureVisible(returnAction);
    await tester.tap(returnAction);
    await tester.pump();
    expect(openedReturn, fixtureReturnId);

    final chat = find.byKey(const ValueKey('mh09-recipient-chat'));
    await tester.ensureVisible(chat);
    await tester.tap(chat);
    await tester.pump();
    expect(openedChat, fixtureCustomerId);

    final call = find.byKey(const ValueKey('mh09-recipient-call'));
    await tester.ensureVisible(call);
    await tester.tap(call);
    await tester.pump();
    expect(calledPhone, '0900000000');
  });

  testWidgets(
    'exceptional cancellation validates reason before unavailable dependency',
    (tester) async {
      final repository = Mh09PageOrders(
        () => mh09Details(capabilities: mh09Capabilities(managerCancel: true)),
      );
      await tester.pumpWidget(mh09PageHost(repository: repository));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Hủy ngoại lệ'));
      await tester.tap(find.text('Hủy ngoại lệ'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('order-action-reason')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('order-action-submit')));
      await tester.pump();
      expect(find.text('Vui lòng nhập lý do trước khi gửi.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('order-action-reason')),
        'Yêu cầu hủy ngoại lệ sau khi kiểm tra',
      );
      await tester.tap(find.byKey(const ValueKey('order-action-submit')));
      await tester.pump();
      expect(
        find.text('Thao tác hiện chưa khả dụng. Vui lòng thử lại sau.'),
        findsOneWidget,
      );
      expect(find.text('Đã hủy'), findsNothing);
    },
  );

  testWidgets('hides exceptional cancellation when capability is absent', (
    tester,
  ) async {
    final repository = Mh09PageOrders(() => mh09Details());
    await tester.pumpWidget(mh09PageHost(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('Hủy ngoại lệ'), findsNothing);
    expect(find.text('Đã hủy'), findsNothing);
  });
}
