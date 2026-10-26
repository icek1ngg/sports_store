// Opt-in real-network widget integration; not part of the offline test suite.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/presentation/pages/delivery_task_detail_page.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_task_detail_view_model.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_task_list_view_model.dart';
import 'package:sports_store/features/cod/presentation/view_models/shipper_cod_view_model.dart';

class _LiveBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _LiveBinding();
  final env = Platform.environment;
  testWidgets('real Auth → MH11 accept/start → authoritative MH10', (
    tester,
  ) async {
    late final SupabaseClient client;
    final taskId = env['LIVE_TASK_ID']!;
    try {
      await tester.runAsync(() async {
        client = SupabaseClient(
          env['LIVE_SUPABASE_URL']!,
          env['LIVE_PUBLISHABLE_KEY']!,
        );
        await client.auth.signInWithPassword(
          email: env['LIVE_TEST_EMAIL']!,
          password: env['LIVE_TEST_PASSWORD']!,
        );
      });
      final container = ProviderContainer(
        overrides: [supabaseClientProvider.overrideWithValue(client)],
      );
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(body: DeliveryTaskDetailPage(taskId: taskId)),
            ),
          ),
        );
        Future<void> waitFor(bool Function() done) async {
          for (var i = 0; i < 300; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            await tester.pump(const Duration(milliseconds: 20));
            if (done()) return;
          }
          fail('Live authoritative state did not settle; no credential output');
        }

        await waitFor(
          () => container
              .read(deliveryTaskDetailViewModelProvider(taskId))
              .hasValue,
        );
        expect(
          container
              .read(deliveryTaskDetailViewModelProvider(taskId))
              .requireValue
              .task
              .status,
          DeliveryTaskStatus.assigned,
        );
        expect(
          container
              .read(deliveryTaskDetailViewModelProvider(taskId))
              .requireValue
              .task
              .amountToCollectVnd,
          550000,
        );
        Future<void> confirm(String button) async {
          await tester.drag(
            find.byKey(const ValueKey('task-detail-scroll')),
            const Offset(0, -1400),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byKey(ValueKey(button)));
          await tester.tap(find.byKey(ValueKey(button)));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('outbound-confirm-custody')),
          );
          await tester.pump();
          await tester.tap(
            find.byKey(const ValueKey('outbound-confirm-submit')),
          );
          await tester.pump();
        }

        await confirm('outbound-accept-goods');
        debugPrint('LIVE UI: accept confirmed manually');
        await waitFor(
          () =>
              container
                      .read(deliveryTaskDetailViewModelProvider(taskId))
                      .asData
                      ?.value
                      .task
                      .status ==
                  DeliveryTaskStatus.accepted &&
              find
                  .byKey(const ValueKey('outbound-start-delivery'))
                  .evaluate()
                  .isNotEmpty &&
              tester
                      .widget<ButtonStyleButton>(
                        find.byKey(const ValueKey('outbound-start-delivery')),
                      )
                      .onPressed !=
                  null,
        );
        await confirm('outbound-start-delivery');
        debugPrint('LIVE UI: start confirmed manually');
        await waitFor(
          () =>
              container
                      .read(deliveryTaskDetailViewModelProvider(taskId))
                      .asData
                      ?.value
                      .task
                      .status ==
                  DeliveryTaskStatus.inTransit &&
              container
                      .read(deliveryTaskListViewModelProvider)
                      .counts
                      ?.inTransit ==
                  1,
        );
        expect(container.read(deliveryTaskListViewModelProvider).error, isNull);
        if (env['LIVE_COMPLETE'] == '1') {
          final codSubscription = container.listen(
            shipperCodViewModelProvider(null),
            (_, _) {},
          );
          await waitFor(
            () => container.read(shipperCodViewModelProvider(null)).heldTotalVnd == 0,
          );
          await waitFor(
            () => find
                .byKey(const ValueKey('completion-open'))
                .evaluate()
                .isNotEmpty,
          );
          final open = find.byKey(const ValueKey('completion-open'));
          await tester.drag(find.byKey(const ValueKey('task-detail-scroll')),const Offset(0,-1400));
          await tester.pumpAndSettle();
          await tester.ensureVisible(open);
          await tester.pumpAndSettle();
          await tester.tap(open);
          await tester.pumpAndSettle();
          expect(find.text('550.000 đ'), findsWidgets);
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const ValueKey('completion-confirm')),
                )
                .onPressed,
            isNull,
          );
          await tester.tap(find.byKey(const ValueKey('completion-goods')));
          await tester.tap(find.byKey(const ValueKey('completion-money')));
          await tester.pump();
          await tester.tap(find.byKey(const ValueKey('completion-confirm')));
          await tester.pump();
          await waitFor(
            () =>
                container
                        .read(deliveryTaskDetailViewModelProvider(taskId))
                        .asData
                        ?.value
                        .task
                        .status ==
                    DeliveryTaskStatus.delivered &&
                container
                        .read(deliveryTaskListViewModelProvider)
                        .counts
                        ?.completed ==
                    1 &&
                container.read(shipperCodViewModelProvider(null)).heldTotalVnd ==
                    550000,
          );
          expect(
            container.read(shipperCodViewModelProvider(null)).items,
            hasLength(1),
          );
          expect(container.read(shipperCodViewModelProvider(null)).error, isNull);
          codSubscription.close();
          debugPrint(
            'LIVE UI: delivered, MH10 completed and held COD550000 verified',
          );
        }
        debugPrint('LIVE UI: authoritative detail/list verified');
        await tester.pumpWidget(const SizedBox.shrink());
        debugPrint('LIVE UI: widget unmounted');
      } finally {
        container.dispose();
        debugPrint('LIVE UI: providers disposed');
      }
    } finally {
      await tester.runAsync(() => client.dispose());
      debugPrint('LIVE UI: client disposed');
    }
  }, skip: env['LIVE_OUTBOUND_UI'] != '1');
}

