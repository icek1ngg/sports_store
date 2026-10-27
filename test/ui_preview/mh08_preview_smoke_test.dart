import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/presentation/pages/customer_orders_page.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_orders_page.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_order_card.dart';

import '../../tool/ui_preview/main.dart' as preview_entrypoint;
import '../../tool/ui_preview/mh08_manager_repository.dart';
import '../../tool/ui_preview/mh08_preview_environment.dart';

import 'mh08_preview_test_support.dart';

void main() {
  testWidgets('preview entrypoint defaults to MH07', (tester) async {
    preview_entrypoint.main();
    try {
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(CustomerOrdersPage), findsOneWidget);
      expect(find.byType(ManagerOrdersPage), findsNothing);
      expect(find.byTooltip('Chọn màn hình'), findsOneWidget);
      expect(find.text('DEMO UI · dữ liệu kiểm thử'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('MH07 ↔ MH08 keeps one provider container and manager scope', (
    tester,
  ) async {
    final environment = Mh08PreviewEnvironment();
    try {
      await pumpMh08Preview(tester, environment);
      await tester.pumpAndSettle();
      expect(find.byKey(previewScopeKey), findsOneWidget);
      final container = previewContainer(tester);

      await selectPreviewScreen(tester, 'MH08');
      expect(find.byType(ManagerOrdersPage), findsOneWidget);
      expect(find.byType(Mh08OrderCard), findsAtLeastNWidgets(1));
      expect(environment.scope.role, 'manager');
      expect(environment.scope.canReadPrivateData, isTrue);
      expect(identical(container, previewContainer(tester)), isTrue);
      expect(find.byTooltip('Chọn trạng thái'), findsOneWidget);
      await selectPreviewScenario(tester, Mh08PreviewScenario.empty);
      await tester.pumpAndSettle();
      expect(find.text('Chưa có đơn hàng cần xử lý'), findsOneWidget);
      await selectPreviewScenario(tester, Mh08PreviewScenario.data);
      await tester.pumpAndSettle();
      expect(find.byType(Mh08OrderCard), findsAtLeastNWidgets(1));

      final first = environment.manager.summaries[0];
      final second = environment.manager.summaries[1];
      final third = environment.manager.summaries[2];
      expect(first.order.status, OrderStatus.pendingConfirmation);
      expect(first.capabilities.canConfirm, isTrue);
      expect(second.order.status, OrderStatus.pendingConfirmation);
      expect(second.capabilities.canConfirm, isFalse);
      expect(third.order.status, OrderStatus.preparing);
      expect(third.capabilities.canConfirm, isFalse);

      for (final name in ['Nguyễn Minh Anh', 'Trần Quốc Bảo', 'Lê Hoàng Nam']) {
        final finder = find.text(name);
        await ensureVisibleInList(tester, finder);
        expect(finder, findsOneWidget);
      }

      await selectPreviewScreen(tester, 'MH07');
      expect(find.byType(CustomerOrdersPage), findsOneWidget);
      expect(find.byType(ManagerOrdersPage), findsNothing);
      expect(environment.scope.role, 'customer');
      expect(identical(container, previewContainer(tester)), isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      await disposeMh08Preview(tester, environment);
    }
  });
}
