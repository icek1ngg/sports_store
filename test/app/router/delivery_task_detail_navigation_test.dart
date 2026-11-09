import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/router/app_router.dart';
import 'package:sports_store/app/sports_store_app.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';

import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';

import '../../features/deliveries/fixtures/delivery_dtos.dart';
import '../../features/support/operational_supabase_fixture.dart';

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  for (var index = 0; index < 200; index++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (condition()) return;
  }
  fail('Detail navigation fixture did not settle');
}

void main() {
  for (final revokeBeforeMap in [false, true]) {
    testWidgets('MH11 map rechecks permission (revoked=$revokeBeforeMap)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (const bool.fromEnvironment('CAPTURE_MH11')) {
        await tester.runAsync(() async {
          final fontPath = Platform.environment['MH11_PREVIEW_FONT'];
          if (fontPath == null) throw StateError('Set MH11_PREVIEW_FONT');
          for (final font in {
            'Roboto': fontPath,
            'MaterialIcons':
                'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
          }.entries) {
            final loader = FontLoader(font.key)
              ..addFont(
                Future.value(
                  ByteData.sublistView(await File(font.value).readAsBytes()),
                ),
              );
            await loader.load();
          }
        });
      }
      // SDK transport/session fixture only. This test executes no writes.
      var assigned = true;
      var taskReads = 0;
      var detailReads = 0;
      final row = currentTaskDto()
        ..['destination_name'] = 'Người nhận fixture MH11';
      var historyRow = row;
      final client = (await tester.runAsync(
        () => fixtureClient((request) async {
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'role': 'shipper'},
            ]);
          }
          if (request.url.path.endsWith('/read_my_delivery_tasks')) {
            taskReads++;
            return jsonResponse(request, assigned ? [row] : []);
          }
          if (request.url.path.endsWith('/list_my_delivery_tasks')) {
            return jsonResponse(request, {
              'items': [row],
              'next_cursor': null,
              'filtered_total': 1,
              'counts': {
                'waiting': 1,
                'in_transit': 0,
                'completed': 0,
                'ungrouped': 0,
              },
              'as_of': '2026-10-24T03:00:00Z',
            });
          }
          if (request.url.path.endsWith('/get_my_delivery_task_history')) {
            detailReads++;
            return jsonResponse(request, {
              'task': historyRow,
              'items': historyRow['snapshot_scope'] == 'current'
                  ? [outboundItemDto()]
                  : <Object>[],
              'notes': null,
              'notes_source': 'unavailable_schema',
              'as_of': '2026-10-24T03:00:00Z',
            });
          }
          if (request.url.path.endsWith('/get_my_delivery_task')) {
            return jsonResponse(request, {
              'task': row,
              'items': row['snapshot_scope'] == 'current'
                  ? [outboundItemDto()]
                  : <Object>[],
              'notes': null,
              'notes_source': 'unavailable_schema',
              'as_of': '2026-10-24T03:00:00Z',
            });
          }
          fail('Unexpected detail fixture request: ${request.url.path}');
        }),
      ))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [supabaseClientProvider.overrideWithValue(client)],
          child: const RepaintBoundary(
            key: ValueKey('mh11-preview'),
            child: SportsStoreApp(),
          ),
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await tester.runAsync(client.dispose);
      });
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SportsStoreApp)),
      );
      final router = container.read(appRouterProvider);
      router.go('/shipper/tasks');
      await _until(
        tester,
        () => find.byKey(const ValueKey('mh10-outlet')).evaluate().isNotEmpty,
      );
      expect(find.text(shipperA), findsOneWidget);
      unawaited(router.push('/shipper/tasks/$taskId'));
      await _until(
        tester,
        () => find.text('Người nhận fixture MH11').evaluate().isNotEmpty,
      );
      if (const bool.fromEnvironment('CAPTURE_MH11') && !revokeBeforeMap) {
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('mh11-preview')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('build/mh11_nike_readonly_20261024.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      final beforeMap = taskReads;
      if (revokeBeforeMap) assigned = false;
      final map = find.byKey(const ValueKey('task-detail-map'));
      await tester.ensureVisible(map);
      await tester.tap(map);
      await _until(
        tester,
        () =>
            taskReads > beforeMap &&
            (revokeBeforeMap
                ? find.byKey(const ValueKey('app-entry')).evaluate().isNotEmpty
                : find
                      .byKey(const ValueKey('mh18-outlet'))
                      .evaluate()
                      .isNotEmpty),
      );
      expect(
        router.state.uri.path,
        revokeBeforeMap ? '/' : '/shipper/tasks/$taskId/map',
      );
      expect(router.state.uri.query, isEmpty);
      if (revokeBeforeMap) {
        expect(find.text('Người nhận fixture MH11'), findsNothing);
        expect(find.byKey(const ValueKey('mh18-outlet')), findsNothing);
      } else {
        expect(find.text('Bản đồ'), findsOneWidget);
        // Reproduce a new authorization epoch while the pushed map is visible.
        container.read(operationalReadAccessProvider).refreshSession();
        await tester.pump();
        await _until(
          tester,
          () =>
              find.byKey(const ValueKey('mh18-outlet')).evaluate().isNotEmpty &&
              find
                  .byKey(const ValueKey('navigation-checking-access'))
                  .evaluate()
                  .isEmpty,
        );
        expect(router.state.uri.path, '/shipper/tasks/$taskId/map');
        expect(find.byType(BackButton), findsOneWidget);
        // A cancelled task is still a permitted historical task, so the
        // route guard alone cannot clear an old current-detail projection.
        final beforeReturn = detailReads;
        row
          ..clear()
          ..addAll(maskedTaskDto(status: 'cancelled', scope: 'history'));
        historyRow = currentTaskDto(status: 'cancelled')
          ..['snapshot_scope'] = 'history'
          ..['destination_name'] = 'Người nhận fixture MH11'
          ..['completed_at'] = '2026-10-24T04:00:00Z';
        router.pop();
        await _until(
          tester,
          () =>
              detailReads > beforeReturn &&
              find.text('Người nhận fixture MH11').evaluate().isNotEmpty &&
              find
                  .text(
                    'Thông tin lần giao này được lưu để xem lại. Nếu đủ điều kiện, bạn có thể tạo lần giao tiếp theo ở mục Giao lại đơn hàng.',
                  )
                  .evaluate()
                  .isNotEmpty,
        );
        expect(router.state.uri.path, '/shipper/tasks/$taskId');
        expect(find.text('Người nhận fixture MH11'), findsOneWidget);
        expect(find.text('0900000000'), findsOneWidget);
        expect(
          find.text('Thông tin người nhận và địa chỉ đã được giới hạn.'),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('task-detail-map')), findsNothing);
      }
    });
  }
}
