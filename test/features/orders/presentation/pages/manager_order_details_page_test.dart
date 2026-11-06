import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mh09/mh09_page_test_support.dart';

void main() {
  testWidgets(
    'renders manager snapshot and all independent unavailable states',
    (tester) async {
      final repository = Mh09PageOrders(
        () => mh09Details(
          buyer: {'id': fixtureCustomerId, 'full_name': 'Người mua minh họa'},
          timeline: [
            fixtureTimelineEntryJson(
              eventKind: 'order_placed',
              toState: 'pending_confirmation',
            ),
          ],
          historyComplete: false,
        ),
      );
      await tester.pumpWidget(mh09PageHost(repository: repository));
      await tester.pump();
      await tester.pump();

      expect(find.text('Người mua minh họa'), findsOneWidget);
      expect(find.text('Sản phẩm minh họa'), findsOneWidget);
      expect(find.text('Tổng COD'), findsOneWidget);
      expect(find.text('Chưa có dữ liệu giao hàng'), findsOneWidget);
      expect(find.text('Chưa có dữ liệu COD'), findsNWidgets(2));
      expect(find.text('Chưa có dữ liệu yêu cầu trả hàng'), findsOneWidget);
      expect(find.text('Đơn hàng được tạo'), findsOneWidget);
      expect(find.text('Lịch sử có thể chưa đầy đủ'), findsOneWidget);
    },
  );

  testWidgets('wraps long content at 320 width with 2x text', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = Mh09PageOrders(
      () => mh09Details(
        buyer: {
          'id': fixtureCustomerId,
          'full_name': List.filled(20, 'Người mua có tên rất dài').join(' '),
        },
      ),
    );
    await tester.pumpWidget(
      mh09PageHost(repository: repository, largeText: true),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('CHI TIẾT ĐƠN HÀNG'), findsOneWidget);
    for (final size in const [Size(360, 740), Size(412, 820), Size(640, 320)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Viewport $size');
    }
  });
}
