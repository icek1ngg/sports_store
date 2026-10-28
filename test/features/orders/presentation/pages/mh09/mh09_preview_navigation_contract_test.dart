import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_order_details_page.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_order_card.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_status_chips.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_header.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_order_identity.dart';

import '../../../../../ui_preview/mh08_preview_test_support.dart';
import '../../../../../../tool/ui_preview/mh08_preview_environment.dart';

void main() {
  testWidgets(
    'existing Preview preserves exact query through the integrated header back',
    (tester) async {
      final environment = Mh08PreviewEnvironment()..selectScreen('MH08');
      try {
        await pumpMh08Preview(tester, environment);
        await tester.pumpAndSettle();
        const search = ValueKey('mh08-search-field');
        const input = '  Nguyễn Minh Anh  ';
        await tester.enterText(find.byKey(search), input);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(Mh08StatusChips),
            matching: find.text('Chờ xác nhận'),
          ),
        );
        await tester.pumpAndSettle();
        final query = environment.manager.managerReads.last;
        final container = previewContainer(tester);
        final id = tester
            .widget<Mh08OrderCard>(find.byType(Mh08OrderCard))
            .summary
            .order
            .id;
        expect(query.search, 'Nguyễn Minh Anh');
        expect(query.statuses, [OrderStatus.pendingConfirmation]);
        await openManagerDetails(tester);
        expect(find.byType(ManagerOrderDetailsPage), findsOneWidget);
        expect(environment.manager.managerDetailReads.last, id);
        expect(
          tester
              .widget<Mh09OrderIdentity>(find.byType(Mh09OrderIdentity))
              .order
              .id,
          id,
        );
        expect(find.text(id), findsOneWidget);
        expect(
          tester.widget<Mh09Header>(find.byType(Mh09Header)).canPop,
          isTrue,
        );
        final reads = environment.manager.managerReads.length;
        final nextReads = environment.manager.managerReads
            .where((q) => q.cursor != null)
            .length;
        await tester.tap(find.byTooltip('Quay lại'));
        await tester.pumpAndSettle();
        expect(previewContainer(tester), same(container));
        expect(environment.manager.managerReads.length, reads + 1);
        expect(environment.manager.managerReads.last, query);
        expect(environment.manager.managerReads.last.cursor, isNull);
        expect(
          environment.manager.managerReads
              .where((q) => q.cursor != null)
              .length,
          nextReads,
        );
        expect(
          tester.widget<TextField>(find.byKey(search)).controller!.text,
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
}
