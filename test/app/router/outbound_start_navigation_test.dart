import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sports_store/app/router/app_router.dart';
import 'package:sports_store/app/sports_store_app.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';

import '../../features/deliveries/fixtures/delivery_dtos.dart';
import '../../features/support/operational_supabase_fixture.dart';

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 250; attempt++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for outbound start navigation state');
}

Map<String, dynamic> _detail(Map<String, dynamic> task) => {
  'task': task,
  'items': [outboundItemDto()],
  'notes': null,
  'notes_source': 'unavailable_schema',
  'as_of': '2026-10-31T03:00:00Z',
};

Map<String, dynamic> _page(Map<String, dynamic> task) {
  final inTransit = task['status'] == 'in_transit';
  return {
    'items': [task],
    'next_cursor': null,
    'filtered_total': 1,
    'counts': {
      'waiting': inTransit ? 0 : 1,
      'in_transit': inTransit ? 1 : 0,
      'completed': 0,
      'ungrouped': 0,
    },
    'as_of': '2026-10-31T03:00:00Z',
  };
}

void main() {
  testWidgets(
    'MH11 start confirmation calls RPC once and renders authoritative in-transit state',
    (tester) async {
      var task = currentTaskDto(
        status: 'accepted',
        acceptedAt: '2026-10-31T09:00:00Z',
      );
      var startCalls = 0;
      var detailReads = 0;
      var listReads = 0;
      final client = (await tester.runAsync(
        () => fixtureClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'role': 'shipper'},
            ]);
          }
          if (path.endsWith('/read_my_delivery_tasks')) {
            return jsonResponse(request, [task]);
          }
          if (path.endsWith('/get_my_delivery_task_history')) {
            detailReads++;
            return jsonResponse(request, _detail(task));
          }
          if (path.endsWith('/get_my_delivery_task')) {
            return jsonResponse(request, _detail(task));
          }
          if (path.endsWith('/list_my_delivery_tasks')) {
            listReads++;
            return jsonResponse(request, _page(task));
          }
          if (path.endsWith('/start_delivery_task')) {
            startCalls++;
            expect(
              (jsonDecode(request.body) as Map<String, dynamic>).keys,
              containsAll(<String>['p_task_id', 'p_request_id']),
            );
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final requestId = body['p_request_id'] as String;
            task = currentTaskDto(
              status: 'in_transit',
              acceptedAt: '2026-10-31T09:00:00Z',
              startedAt: '2026-10-31T09:01:00Z',
            );
            return jsonResponse(request, {
              'task_id': taskId,
              'order_id': orderId,
              'operation': 'start',
              'task_status': 'in_transit',
              'order_status': 'delivering',
              'attempt_number': 1,
              'delivery_attempt_count': 1,
              'accepted_at': '2026-10-31T09:00:00Z',
              'started_at': '2026-10-31T09:01:00Z',
              'dispatch_event_id': '55555555-5555-4555-8555-555555555555',
              'event_id': '66666666-6666-4666-8666-666666666666',
              'request_id': requestId,
            });
          }
          return jsonResponse(request, const <Object>[]);
        }),
      ))!;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await tester.runAsync(client.dispose);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [supabaseClientProvider.overrideWithValue(client)],
          child: const SportsStoreApp(),
        ),
      );
      _currentRouter(tester).go('/shipper/tasks');

      await _until(
        tester,
        () => find
            .byKey(const ValueKey('delivery-task-$taskId'))
            .evaluate()
            .isNotEmpty,
      );
      await tester.tap(find.byKey(const ValueKey('delivery-task-$taskId')));

      await _until(tester, () {
        final finder = find.byKey(const ValueKey('outbound-start-delivery'));
        if (finder.evaluate().isEmpty) return false;
        return tester.widget<ButtonStyleButton>(finder).onPressed != null;
      });
      expect(_currentRouter(tester).state.uri.path, '/shipper/tasks/$taskId');
      expect(detailReads, greaterThanOrEqualTo(1));

      // Returning from MH18 must reactivate the MH11 action controller.  The
      // detail route remains in the navigator stack while the map is pushed,
      // so Riverpod can pause and resume the auto-dispose action provider.
      for (var cycle = 0; cycle < 2; cycle++) {
        final mapButton = find.byKey(const ValueKey('task-detail-map'));
        await tester.ensureVisible(mapButton);
        await tester.tap(mapButton);
        await _until(
          tester,
          () => find.byKey(const ValueKey('mh18-outlet')).evaluate().isNotEmpty,
        );
        await tester.pump(const Duration(milliseconds: 400));
        final detailReadsBeforeReturn = detailReads;
        _currentRouter(tester).pop();
        await _until(tester, () {
          final finder = find.byKey(const ValueKey('outbound-start-delivery'));
          return detailReads > detailReadsBeforeReturn &&
              finder.evaluate().isNotEmpty &&
              tester.widget<ButtonStyleButton>(finder).onPressed != null;
        });
      }

      final start = find.byKey(const ValueKey('outbound-start-delivery'));
      await tester.drag(
        find.byKey(const ValueKey('task-detail-scroll')),
        const Offset(0, -1000),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(start);
      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('outbound-confirm-custody')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('outbound-confirm-custody')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('outbound-confirm-submit')));
      await tester.pump();

      await _until(
        tester,
        () =>
            startCalls == 1 &&
            find.text('Đang vận chuyển').evaluate().isNotEmpty &&
            find
                .byKey(const ValueKey('outbound-start-delivery'))
                .evaluate()
                .isEmpty,
      );
      expect(startCalls, 1);
      expect(listReads, greaterThanOrEqualTo(1));
      expect(
        find.byKey(const ValueKey('outbound-start-delivery')),
        findsNothing,
      );
    },
  );
}

GoRouter _currentRouter(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(SportsStoreApp)))
        .read(appRouterProvider);
