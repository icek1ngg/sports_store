import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_order_details_page.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_order_card.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_status_chips.dart';

import '../../tool/ui_preview/mh08_manager_repository.dart';
import '../../tool/ui_preview/mh08_preview_environment.dart';
import 'mh08_preview_test_support.dart';

const _search = ValueKey('mh08-search-field');

Future<void> _typeSearch(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(_search), text);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'actual preview searches UUID/account but never product/recipient',
    (tester) async {
      final environment = Mh08PreviewEnvironment()..selectScreen('MH08');
      try {
        await pumpMh08Preview(tester, environment);
        await tester.pumpAndSettle();
        final id = environment.manager.summaries.first.order.id;
        await _typeSearch(tester, id);
        expect(find.byType(Mh08OrderCard), findsOneWidget);
        expect(
          tester
              .widget<Mh08OrderCard>(find.byType(Mh08OrderCard))
              .summary
              .order
              .id,
          id,
        );

        await _typeSearch(tester, '  nguyễn   minh anh  ');
        expect(find.byType(Mh08OrderCard), findsOneWidget);
        expect(find.text('Nguyễn Minh Anh'), findsOneWidget);

        for (final text in ['AirFlex', 'Người nhận đơn thể thao']) {
          await _typeSearch(tester, text);
          expect(find.byType(Mh08OrderCard), findsNothing);
        }
        await tester.tap(find.byTooltip('Xóa tìm kiếm'));
        await tester.pumpAndSettle();
        expect(environment.manager.managerReads.last.search, isNull);
        expect(environment.manager.managerReads.last.cursor, isNull);
        expect(find.byType(Mh08OrderCard), findsAtLeastNWidgets(1));
        expect(tester.takeException(), isNull);
      } finally {
        await disposeMh08Preview(tester, environment);
      }
    },
  );

  testWidgets(
    'MH09 return preserves editing/status and refreshes their exact query',
    (tester) async {
      final environment = Mh08PreviewEnvironment()..selectScreen('MH08');
      try {
        await pumpMh08Preview(tester, environment);
        await tester.pumpAndSettle();
        const input = '  Nguyễn Minh Anh  ';
        await _typeSearch(tester, input);
        await tester.tap(
          find.descendant(
            of: find.byType(Mh08StatusChips),
            matching: find.text('Chờ xác nhận'),
          ),
        );
        await tester.pumpAndSettle();
        final query = environment.manager.managerReads.last;
        expect(query.search, 'Nguyễn Minh Anh');
        expect(query.statuses, [OrderStatus.pendingConfirmation]);
        expect(query.cursor, isNull);
        final container = previewContainer(tester);
        final id = tester
            .widget<Mh08OrderCard>(find.byType(Mh08OrderCard))
            .summary
            .order
            .id;
        await openManagerDetails(tester);
        expect(find.byType(ManagerOrderDetailsPage), findsOneWidget);
        expect(environment.manager.managerDetailReads.last, id);
        // Existing MH09 onAccepted may invalidate lists while detail is open.
        final reads = environment.manager.managerReads.length;
        await tester.tap(find.byTooltip('Quay lại'));
        await tester.pumpAndSettle();
        expect(identical(previewContainer(tester), container), isTrue);
        expect(environment.manager.managerReads.length, reads + 1);
        expect(environment.manager.managerReads.last, query);
        expect(
          tester.widget<TextField>(find.byKey(_search)).controller!.text,
          input,
        );
        expect(
          tester
              .widget<Mh08StatusChips>(find.byType(Mh08StatusChips))
              .selectedStatus,
          OrderStatus.pendingConfirmation,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await disposeMh08Preview(tester, environment);
      }
    },
  );

  testWidgets(
    'late detail response and pop after expiry cannot refresh old manager scope',
    (tester) async {
      final environment = Mh08PreviewEnvironment()..selectScreen('MH08');
      try {
        await pumpMh08Preview(tester, environment);
        environment.selectScenario(Mh08PreviewScenario.loading);
        await tester.pumpAndSettle();
        final open = find.byKey(const ValueKey('mh08-open-order')).first;
        await ensureVisibleInList(tester, open);
        await tester.tap(open);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(environment.manager.managerDetailReads, isNotEmpty);
        environment.selectScenario(Mh08PreviewScenario.expired);
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.text('Nguyễn Minh Anh'), findsNothing);
        final reads = environment.manager.managerReads.length;
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(environment.manager.managerReads.length, reads);
        expect(find.byType(Mh08OrderCard), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await disposeMh08Preview(tester, environment);
      }
    },
  );
}
