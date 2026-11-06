// Opt-in real-network widget integration for the P08.2 pickup boundary.
// The parent Node runner supplies only an ephemeral shipper password and the
// publishable Supabase key. This test never receives the Auth Admin secret.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/return_pickup_command.dart';
import 'package:sports_store/features/deliveries/presentation/pages/delivery_task_detail_page.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/return_pickup_view_model.dart';

class _LiveBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _LiveBinding();
  final env = Platform.environment;

  testWidgets('real Auth → MH11 collect full plan → report pickup handover', (
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

        Future<void> waitFor(bool Function() done, String description) async {
          for (var i = 0; i < 300; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            await tester.pump(const Duration(milliseconds: 20));
            if (done()) return;
          }
          final timedOut = container.read(
            returnPickupViewModelProvider(taskId),
          );
          debugPrint(
            'LIVE pickup timeout [$description]: '
            'busy=${timedOut.busy} acknowledged=${timedOut.acknowledged} '
            'confirmed=${timedOut.confirmed}/${timedOut.confirmedOperation} '
            'requiresReadRetry=${timedOut.requiresReadRetry} '
            'details=${timedOut.details.hasValue ? timedOut.details.requireValue.task.status : timedOut.details.error} '
            'marker=${timedOut.handoverStatus.hasValue ? timedOut.handoverStatus.requireValue.reported : timedOut.handoverStatus.error} '
            'error=${timedOut.error}',
          );
          final state = container.read(returnPickupViewModelProvider(taskId));
          fail(
            'Live pickup UI did not settle: $description; '
            'busy=${state.busy}, confirmed=${state.confirmed}, ack=${state.acknowledged}, '
            'pending=${state.pendingCommand?.operation.name}, retry=${state.requiresReadRetry}, '
            'error=${state.error?.code.name}, task=${state.details.asData?.value.task.status.name}, '
            'detailError=${state.details.hasError}, markerError=${state.handoverStatus.hasError}, '
            'marker=${state.handoverStatus.asData?.value.reported}',
          );
        }

        Future<void> reveal(Finder finder) async {
          if (finder.evaluate().isEmpty) {
            final scroll = find.byKey(const ValueKey('task-detail-scroll'));
            if (scroll.evaluate().isNotEmpty) {
              await tester.drag(scroll, const Offset(0, -1800));
              await tester.pumpAndSettle();
            }
          }
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          expect(finder.hitTestable(), findsOneWidget);
        }

        await waitFor(() {
          final state = container.read(returnPickupViewModelProvider(taskId));
          // The marker RPC intentionally accepts only a current in-transit
          // pickup with custody proof; an assigned task must not be probed.
          return state.details.hasValue;
        }, 'assigned task details');
        final initial = container.read(returnPickupViewModelProvider(taskId));
        expect(
          initial.details.requireValue.task.kind,
          DeliveryTaskKind.returnPickup,
        );
        expect(
          initial.details.requireValue.task.status,
          DeliveryTaskStatus.assigned,
        );

        final collectOpen = find.byKey(const ValueKey('pickup-collect-open'));
        await reveal(collectOpen);
        await tester.tap(collectOpen);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('pickup-collect-confirm')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('pickup-collect-confirm')),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.byKey(const ValueKey('pickup-collect-all')));
        await tester.pump();
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('pickup-collect-confirm')),
              )
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.byKey(const ValueKey('pickup-collect-confirm')));
        await tester.pump();

        await waitFor(() {
          final state = container.read(returnPickupViewModelProvider(taskId));
          return state.confirmed &&
              state.confirmedOperation == ReturnPickupOperation.collect &&
              state.details.asData?.value.task.status ==
                  DeliveryTaskStatus.inTransit &&
              state.handoverStatus.hasValue &&
              !state.handoverReported;
        }, 'full-plan collection acknowledgement');

        final handoverOpen = find.byKey(const ValueKey('pickup-handover-open'));
        await waitFor(
          () => handoverOpen.evaluate().isNotEmpty,
          'pickup handover action',
        );
        await reveal(handoverOpen);
        await tester.tap(handoverOpen);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('pickup-handover-confirmation')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('pickup-handover-confirm')),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(
          find.byKey(const ValueKey('pickup-handover-confirmation')),
        );
        await tester.pump();
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('pickup-handover-confirm')),
              )
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.byKey(const ValueKey('pickup-handover-confirm')));
        await tester.pump();

        await waitFor(() {
          final state = container.read(returnPickupViewModelProvider(taskId));
          return state.confirmed &&
              state.confirmedOperation == ReturnPickupOperation.handover &&
              state.handoverStatus.hasValue &&
              state.handoverReported;
        }, 'pickup handover acknowledgement and marker read');
        expect(
          find.byKey(const ValueKey('pickup-handover-reported')),
          findsOneWidget,
        );
        expect(
          container
              .read(returnPickupViewModelProvider(taskId))
              .details
              .requireValue
              .task
              .status,
          DeliveryTaskStatus.inTransit,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        container.dispose();
      }
    } finally {
      await tester.runAsync(() => client.dispose());
    }
  }, skip: env['LIVE_PICKUP_HANDOVER_UI'] != '1');
}
