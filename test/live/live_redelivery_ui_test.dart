// Explicit opt-in real Supabase/Auth widget acceptance. No Admin key.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/redelivery_command.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';
import 'package:sports_store/features/deliveries/presentation/pages/delivery_task_detail_page.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/redelivery_view_model.dart';
import 'package:sports_store/features/deliveries/presentation/pages/delivery_task_map_page.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_task_map_view_model.dart';

class _LiveBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _LiveBinding();
  final env = Platform.environment;
  testWidgets('real Auth redelivery accept → start → outcome', (tester) async {
    late SupabaseClient client;
    final task = env['LIVE_TASK_ID']!;
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
    final c = ProviderContainer(
      overrides: [supabaseClientProvider.overrideWithValue(client)],
    );
    try {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.light,
            home: DeliveryTaskMapPage(taskId: task),
          ),
        ),
      );
      for (
        var i = 0;
        i < 300 &&
            find.byKey(const ValueKey('mh18-address')).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.byKey(const ValueKey('mh18-address')), findsOneWidget);
      final mapVm = c.read(deliveryTaskMapViewModelProvider(task).notifier);
      final checked = await tester.runAsync(() async {
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            return await mapVm.recheckAuthorizedDetails();
          } on OperationalFailure catch (error) {
            if (error.code != OperationalFailureCode.network || attempt == 2) {
              rethrow;
            }
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        }
        throw StateError('Read retry exhausted');
      });
      expect(checked?.task.destination, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(body: DeliveryTaskDetailPage(taskId: task)),
          ),
        ),
      );
      Future<void> wait(bool Function() condition) async {
        for (var i = 0; i < 400; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump(const Duration(milliseconds: 20));
          if (condition()) return;
        }
        final state = c.read(redeliveryViewModelProvider(task));
        fail(
          'Redelivery timeout: busy=${state.busy}, ack=${state.acknowledged}, confirmed=${state.confirmed}/${state.confirmedOperation}, status=${state.details.asData?.value.task.status}, canStart=${state.canStart}, canComplete=${state.canComplete}, error=${state.error?.code}, detailError=${state.details.hasError}',
        );
      }

      Future<void> tap(String key) async {
        final f = find.byKey(ValueKey(key));
        await wait(() => f.evaluate().isNotEmpty);
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        expect(f.hitTestable(), findsOneWidget);
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      await wait(() => c.read(redeliveryViewModelProvider(task)).canAccept);
      for (final operation in ['accept', 'start']) {
        await tap('redelivery-$operation-open');
        final confirm = find.byKey(ValueKey('redelivery-$operation-confirm'));
        expect(tester.widget<ButtonStyleButton>(confirm).onPressed, isNull);
        await tap('redelivery-$operation-all');
        await tap('redelivery-$operation-confirm');
        await wait(() {
          final state = c.read(redeliveryViewModelProvider(task));
          return state.confirmed &&
              state.confirmedOperation ==
                  (operation == 'accept'
                      ? RedeliveryOperation.accept
                      : RedeliveryOperation.start);
        });
        if (operation == 'accept') {
          await wait(() => c.read(redeliveryViewModelProvider(task)).canStart);
        }
      }
      await wait(() => c.read(redeliveryViewModelProvider(task)).canComplete);
      if (env['LIVE_REDELIVERY_FAILURE'] == '1') {
        await tap('redelivery-failure-open');
        await tap('redelivery-failure-reason');
        await tester.tap(find.text('Khác').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('redelivery-failure-description')),
          'Live UI: customer unavailable',
        );
        await tap('redelivery-failure-confirm');
      } else {
        await tap('redelivery-complete-open');
        await tap('redelivery-complete-all');
        await tap('redelivery-complete-confirm');
      }
      final expected = env['LIVE_REDELIVERY_FAILURE'] == '1'
          ? DeliveryTaskStatus.managerActionRequired
          : DeliveryTaskStatus.delivered;
      await wait(
        () =>
            c.read(redeliveryViewModelProvider(task)).confirmed &&
            c
                    .read(redeliveryViewModelProvider(task))
                    .details
                    .asData
                    ?.value
                    .task
                    .status ==
                expected,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      c.dispose();
      await tester.runAsync(() => client.dispose());
    }
  }, skip: env['LIVE_REDELIVERY_UI'] != '1');
}
