import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_order_details_page.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_order_card.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_status_chips.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_items_section.dart';

import '../../tool/ui_preview/mh08_preview_environment.dart';
import '../../tool/ui_preview/mh08_manager_repository.dart';
import '../../tool/ui_preview/mh09_preview_scenario.dart';
import 'mh08_preview_test_support.dart';

void main() {
  testWidgets(
    'Back preserves denied scope until explicit demo recovery and never refreshes old manager',
    (tester) async {
      final env = Mh08PreviewEnvironment()..selectScreen('MH08');
      try {
        await pumpMh08Preview(tester, env);
        await tester.pumpAndSettle();
        for (final scene in [
          Mh09PreviewScenario.expired,
          Mh09PreviewScenario.unauthorized,
          Mh09PreviewScenario.unresolved,
        ]) {
          await openManagerDetails(tester);
          env.selectMh09Scenario(scene);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          final scope = env.scope;
          final reads = env.manager.managerReads.length;
          expect(await tester.binding.handlePopRoute(), isTrue);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pump(const Duration(milliseconds: 500));
          expect(
            find.byType(ManagerOrderDetailsPage),
            findsNothing,
            reason: scene.name,
          );
          expect(env.scope, scope);
          expect(env.manager.managerReads.length, reads);
          expect(find.byType(Mh08OrderCard), findsNothing);
          env.selectScenario(Mh08PreviewScenario.data);
          await tester.pumpAndSettle();
          expect(env.scope.role, 'manager');
          expect(env.scope.canReadPrivateData, isTrue);
          expect(find.byType(Mh08OrderCard), findsWidgets);
          expect(tester.takeException(), isNull);
        }
      } finally {
        await disposeMh08Preview(tester, env);
      }
    },
  );

  for (final systemBack in [false, true]) {
    testWidgets(
      '${systemBack ? 'framework system' : 'header'} Back preserves exact query over three cycles',
      (tester) async {
        final env = Mh08PreviewEnvironment()..selectScreen('MH08');
        try {
          await pumpMh08Preview(tester, env);
          await tester.pumpAndSettle();
          final id = env.manager.summaries.first.order.id;
          final container = previewContainer(tester);
          final cache = container.read(epochCacheProvider);
          await tester.enterText(
            find.byKey(const ValueKey('mh08-search-field')),
            id,
          );
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pumpAndSettle();
          await tester.tap(
            find.descendant(
              of: find.byType(Mh08StatusChips),
              matching: find.text('Chờ xác nhận'),
            ),
          );
          await tester.pumpAndSettle();
          final query = env.manager.managerReads.last;
          final nextReads = env.manager.managerReads
              .where((q) => q.cursor != null)
              .length;
          for (var cycle = 0; cycle < 3; cycle++) {
            await openManagerDetails(tester);
            expect(find.byType(ManagerOrderDetailsPage), findsOneWidget);
            expect(env.manager.managerDetailReads.last, id);
            expect(find.text(id), findsOneWidget);
            if (cycle == 1) {
              env.selectMh09Scenario(Mh09PreviewScenario.large);
              await tester.pumpAndSettle();
              expect(
                tester
                    .widget<Mh09ItemsSection>(find.byType(Mh09ItemsSection))
                    .items,
                hasLength(40),
              );
              expect(
                identical(container.read(epochCacheProvider), cache),
                isTrue,
              );
            }
            final reads = env.manager.managerReads.length;
            if (systemBack) {
              expect(await tester.binding.handlePopRoute(), isTrue);
            } else {
              expect(find.byTooltip('Quay lại'), findsOneWidget);
              await tester.tap(find.byTooltip('Quay lại'));
            }
            await tester.pumpAndSettle();
            expect(find.byType(ManagerOrderDetailsPage), findsNothing);
            expect(find.byType(Mh08OrderCard), findsOneWidget);
            expect(identical(previewContainer(tester), container), isTrue);
            expect(
              identical(container.read(epochCacheProvider), cache),
              isTrue,
            );
            expect(env.manager.managerReads.length, reads + 1);
            expect(env.manager.managerReads.last, query);
            expect(env.manager.managerReads.last.cursor, isNull);
            expect(
              env.manager.managerReads.where((q) => q.cursor != null),
              hasLength(nextReads),
            );
            expect(
              tester
                  .widget<TextField>(
                    find.byKey(const ValueKey('mh08-search-field')),
                  )
                  .controller!
                  .text,
              id,
            );
            expect(
              tester
                  .widget<Mh08StatusChips>(find.byType(Mh08StatusChips))
                  .selectedStatus,
              OrderStatus.pendingConfirmation,
            );
            final card = tester.widget<Mh08OrderCard>(
              find.byType(Mh08OrderCard),
            );
            expect(
              card.summary.itemLineCount,
              env.manager.summaries.first.itemLineCount,
            );
            expect(env.mh09.activeOrderId, isNull);
            expect(env.mh09.scenario, Mh09PreviewScenario.canonical);
            expect(tester.takeException(), isNull);
          }
        } finally {
          await disposeMh08Preview(tester, env);
        }
      },
    );
  }

  testWidgets(
    'framework Back closes modal before detail and never exits MH08',
    (tester) async {
      final env = Mh08PreviewEnvironment()..selectScreen('MH08');
      try {
        await pumpMh08Preview(tester, env);
        await tester.pumpAndSettle();
        await openManagerDetails(tester);
        await tester.tap(find.text('Xác nhận đơn hàng'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(await tester.binding.handlePopRoute(), isTrue);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(ManagerOrderDetailsPage), findsOneWidget);
        expect(await tester.binding.handlePopRoute(), isTrue);
        await tester.pumpAndSettle();
        expect(find.byType(ManagerOrderDetailsPage), findsNothing);
        expect(find.byType(Mh08OrderCard), findsWidgets);
        expect(tester.takeException(), isNull);
      } finally {
        await disposeMh08Preview(tester, env);
      }
    },
  );
}
