import 'dart:convert';
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

import '../../features/deliveries/fixtures/delivery_dtos.dart';
import '../../features/support/operational_supabase_fixture.dart';

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  for (var index = 0; index < 200; index++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (condition()) return;
  }
  fail('Navigation fixture did not reach the expected state');
}

void main() {
  testWidgets('shared router refreshes MH10 after MH11 and preserves filters', (
    tester,
  ) async {
    if (const bool.fromEnvironment('CAPTURE_MH10')) {
      await tester.runAsync(() async {
        final fontPath = Platform.environment['MH10_PREVIEW_FONT'];
        if (fontPath == null) {
          throw StateError('Set MH10_PREVIEW_FONT for capture');
        }
        final textFont = FontLoader('Roboto')
          ..addFont(
            Future.value(
              ByteData.sublistView(await File(fontPath).readAsBytes()),
            ),
          );
        await textFont.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                await File(
                  'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
                ).readAsBytes(),
              ),
            ),
          );
        await icons.load();
      });
    }
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Transport/session fixture only: no business action or live backend.
    var recipient = 'Minh trước cập nhật';
    final queries = <Map<String, dynamic>>[];
    final client = (await tester.runAsync(
      () => fixtureClient((request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        final row = currentTaskDto()..['destination_name'] = recipient;
        if (request.url.path.endsWith('/list_my_delivery_tasks')) {
          queries.add(jsonDecode(request.body) as Map<String, dynamic>);
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
            'as_of': '2026-10-23T03:00:00Z',
          });
        }
        if (request.url.path.endsWith('/read_my_delivery_tasks')) {
          return jsonResponse(request, [row]);
        }
        if (request.url.path.endsWith('/get_my_delivery_task')) {
          return jsonResponse(request, {
            'task': row,
            'items': [outboundItemDto()],
            'notes': null,
            'notes_source': 'unavailable_schema',
            'as_of': '2026-10-24T03:00:00Z',
          });
        }
        if (request.url.path.endsWith('/get_my_delivery_task')) {
          return jsonResponse(request, {
            'task': row,
            'items': [outboundItemDto()],
            'notes': null,
            'notes_source': 'unavailable_schema',
            'as_of': '2026-10-24T03:00:00Z',
          });
        }
        fail('Unexpected request in navigation fixture: ${request.url.path}');
      }),
    ))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseClientProvider.overrideWithValue(client)],
        child: const RepaintBoundary(
          key: ValueKey('mh10-fixture-preview'),
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
    await _until(tester, () => find.text(recipient).evaluate().isNotEmpty);
    if (const bool.fromEnvironment('CAPTURE_MH10')) {
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('mh10-fixture-preview')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build').create(recursive: true);
        await File('build/p023_mh10_preview.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await tester.enterText(
      find.byKey(const ValueKey('task-search-input')),
      'Minh',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _until(tester, () => queries.last['p_query'] == 'Minh');
    await tester.tap(find.byKey(const ValueKey('task-kind-outbound')));
    await _until(tester, () => queries.last['p_kind'] == 'outbound');
    await tester.tap(find.byKey(const ValueKey('task-group-waiting')));
    await _until(
      tester,
      () =>
          queries.last['p_state_group'] == 'waiting' &&
          find.text(recipient).evaluate().isNotEmpty,
    );

    final card = find.byKey(const ValueKey('delivery-task-$taskId'));
    await tester.ensureVisible(card);
    await tester.tap(card);
    await _until(
      tester,
      () => find.byKey(const ValueKey('mh11-outlet')).evaluate().isNotEmpty,
    );
    final beforeReturn = queries.length;
    expect(router.state.uri.path, '/shipper/tasks/$taskId');
    recipient = 'Minh sau cập nhật';
    router.pop();
    await _until(
      tester,
      () =>
          queries.length > beforeReturn &&
          find.text(recipient).evaluate().isNotEmpty,
    );
    expect(queries.last['p_query'], 'Minh');
    expect(queries.last['p_kind'], 'outbound');
    expect(queries.last['p_state_group'], 'waiting');
    expect(queries.last['p_cursor'], isNull);
    expect(find.text('Minh trước cập nhật'), findsNothing);
    expect(router.state.uri.path, '/shipper/tasks');
  });
}
