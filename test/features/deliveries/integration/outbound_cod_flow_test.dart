import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/cod/presentation/pages/cod_route_page.dart';
import 'package:sports_store/features/cod/presentation/pages/shipper_cod_page.dart';
import 'package:sports_store/features/cod/presentation/view_models/cod_providers.dart';
import 'package:sports_store/features/cod/presentation/view_models/shipper_cod_view_model.dart';
import 'package:sports_store/features/cod/presentation/widgets/manager_cod_panel.dart';
import 'package:sports_store/features/deliveries/presentation/pages/delivery_route_pages.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/outbound_completion_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/operational_supabase_fixture.dart';
import '../fixtures/delivery_dtos.dart';

const _managerId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _shipperId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _completionRequestId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _receiptRequestId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const _eventId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const _notificationId = 'ffffffff-ffff-4fff-8fff-ffffffffffff';

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Offline transport only: production Supabase adapters and ViewModels call
/// this HTTP fixture. No repository or production write adapter is replaced.
final class _OfflineTransportFixture {
  late final SupabaseClient client;

  var delivered = false;
  var received = false;
  var completionCalls = 0;
  var receiptCalls = 0;
  var taskListCalls = 0;
  final requests = <http.Request>[];
  final completionBodies = <Map<String, dynamic>>[];
  final receiptBodies = <Map<String, dynamic>>[];
  final codQueryBodies = <Map<String, dynamic>>[];

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    if (path.endsWith('/profiles')) return _profile(request);
    if (path.endsWith('/rpc/get_my_delivery_task')) {
      return jsonResponse(request, _detailPayload());
    }
    if (path.endsWith('/rpc/list_my_delivery_tasks')) {
      taskListCalls++;
      return jsonResponse(request, _taskListPayload());
    }
    if (path.endsWith('/rpc/complete_outbound_delivery')) {
      return _completeOutbound(request);
    }
    if (path.endsWith('/rpc/list_cod_collections')) {
      return _listCod(request);
    }
    if (path.endsWith('/rpc/confirm_cod_received')) {
      return _confirmCod(request);
    }
    throw StateError('Unexpected offline transport request: $path');
  }

  http.Response _profile(http.Request request) {
    final role = switch (client.auth.currentUser?.id) {
      _managerId => 'manager',
      _shipperId => 'shipper',
      _ => 'customer',
    };
    return jsonResponse(request, [
      <String, dynamic>{'role': role},
    ]);
  }

  Map<String, dynamic> _requestBody(http.Request request) {
    if (request.body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(request.body);
    if (decoded is! Map) {
      throw StateError('Expected JSON object request body for ${request.url}');
    }
    return Map<String, dynamic>.from(decoded);
  }

  http.Response _completeOutbound(http.Request request) {
    final body = _requestBody(request);
    completionCalls++;
    completionBodies.add(Map<String, dynamic>.from(body));
    if (client.auth.currentUser?.id != _shipperId) {
      return jsonResponse(request, <String, dynamic>{
        'code': '42501',
        'message': 'permission denied',
      }, status: 403);
    }
    if (body.keys.toSet().difference(const {
          'p_task_id',
          'p_request_id',
          'p_received_all_items',
          'p_collected_amount_vnd',
        }).isNotEmpty ||
        body['p_task_id'] != taskId ||
        body['p_request_id'] != _completionRequestId ||
        body['p_received_all_items'] != true ||
        body['p_collected_amount_vnd'] != 550000) {
      return jsonResponse(request, <String, dynamic>{
        'code': '22023',
        'message': 'invalid command',
      }, status: 400);
    }
    delivered = true;
    return jsonResponse(request, <String, dynamic>{
      'request_id': _completionRequestId,
      'task_id': taskId,
      'order_id': orderId,
      'operation': 'complete',
      'task_status': 'delivered',
      'order_status': 'delivered',
      'attempt_number': 1,
      'delivery_attempt_count': 1,
      'collected_amount_vnd': 550000,
      'completed_at': '2026-10-28T09:00:00Z',
      'event_id': _eventId,
    });
  }

  http.Response _listCod(http.Request request) {
    final body = _requestBody(request);
    codQueryBodies.add(Map<String, dynamic>.from(body));
    final expectedScope = client.auth.currentUser?.id == _managerId
        ? null
        : _shipperId;
    if (body['p_shipper_id'] != expectedScope) {
      return jsonResponse(request, {
        'code': '42501',
        'message': 'fixture scope denied',
      }, status: 403);
    }
    final statuses = (body['p_statuses'] as List<dynamic>?)
        ?.whereType<String>()
        .toSet();
    final rowStatus = received
        ? 'received'
        : delivered
        ? 'collected'
        : 'uncollected';
    final selected = statuses == null || statuses.contains(rowStatus);
    final row = _codRow();
    return jsonResponse(request, <String, dynamic>{
      'items': selected ? [row] : <Map<String, dynamic>>[],
      'next_cursor': null,
      'filtered_total': selected ? 1 : 0,
      'counts': <String, dynamic>{
        'all': 1,
        'uncollected': delivered ? 0 : 1,
        'collected': delivered && !received ? 1 : 0,
        'received': received ? 1 : 0,
      },
      'outstanding_vnd': delivered && !received ? 550000 : 0,
      'as_of': '2026-10-28T09:05:00Z',
    });
  }

  http.Response _confirmCod(http.Request request) {
    final body = _requestBody(request);
    receiptCalls++;
    receiptBodies.add(Map<String, dynamic>.from(body));
    if (client.auth.currentUser?.id != _managerId) {
      return jsonResponse(request, <String, dynamic>{
        'code': '42501',
        'message': 'permission denied',
      }, status: 403);
    }
    if (body.keys.toSet().difference(const {
          'p_order_id',
          'p_received_amount_vnd',
          'p_request_id',
        }).isNotEmpty ||
        body['p_order_id'] != orderId ||
        body['p_received_amount_vnd'] != 550000 ||
        body['p_request_id'] != _receiptRequestId) {
      return jsonResponse(request, <String, dynamic>{
        'code': '22023',
        'message': 'invalid receipt',
      }, status: 400);
    }
    received = true;
    return jsonResponse(request, <String, dynamic>{
      'order_id': orderId,
      'status': 'received',
      'received_amount_vnd': 550000,
      'received_by': _managerId,
      'received_at': '2026-10-28T09:10:00Z',
      'handed_over_at': '2026-10-28T09:10:00Z',
      'event_id': _eventId,
      'notification_id': _notificationId,
    });
  }

  Map<String, dynamic> _detailPayload() {
    final task = delivered
        ? maskedTaskDto(status: 'delivered', scope: 'history')
        : currentTaskDto(
            status: 'in_transit',
            acceptedAt: '2026-10-28T08:30:00Z',
            startedAt: '2026-10-28T08:40:00Z',
          );
    return <String, dynamic>{
      'task': task,
      'items': delivered ? <Object>[] : [outboundItemDto()],
      'notes': null,
      'notes_source': 'unavailable_schema',
      'as_of': '2026-10-28T09:00:00Z',
    };
  }

  Map<String, dynamic> _taskListPayload() {
    final task = delivered
        ? maskedTaskDto(status: 'delivered', scope: 'history')
        : currentTaskDto(
            status: 'in_transit',
            acceptedAt: '2026-10-28T08:30:00Z',
            startedAt: '2026-10-28T08:40:00Z',
          );
    return <String, dynamic>{
      'items': [task],
      'next_cursor': null,
      'filtered_total': 1,
      'counts': <String, dynamic>{
        'waiting': 0,
        'in_transit': delivered ? 0 : 1,
        'completed': delivered ? 1 : 0,
        'ungrouped': 0,
      },
      'as_of': '2026-10-28T09:00:00Z',
    };
  }

  Map<String, dynamic> _codRow() => <String, dynamic>{
    'order_id': orderId,
    'order_code': orderId,
    'order_code_source': 'order_uuid',
    'shipper_id': _shipperId,
    'status': received ? 'received' : 'collected',
    'expected_amount_vnd': 550000,
    'collected_amount_vnd': 550000,
    'received_amount_vnd': received ? 550000 : 0,
    'collected_by': _shipperId,
    'received_by': received ? _managerId : null,
    'collected_at': '2026-10-28T08:55:00Z',
    'handed_over_at': received ? '2026-10-28T09:10:00Z' : null,
    'received_at': received ? '2026-10-28T09:10:00Z' : null,
    'created_at': '2026-10-28T08:00:00Z',
    'updated_at': received ? '2026-10-28T09:10:00Z' : '2026-10-28T08:55:00Z',
  };
}

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  for (var index = 0; index < 250; index++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 10));
    if (condition()) return;
  }
  fail('Offline outbound/COD flow did not settle');
}

Future<void> _tapOnce(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  testWidgets(
    'P10.2 offline production flow completes outbound then reconciles COD',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = _OfflineTransportFixture();
      final client = (await tester.runAsync(
        () => fixtureClient(fixture.handle, userId: _shipperId),
      ))!;
      fixture.client = client;
      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          outboundCompletionRequestIdProvider.overrideWithValue(
            () => _completionRequestId,
          ),
          codReceiptRequestIdProvider.overrideWithValue(
            () => _receiptRequestId,
          ),
        ],
      );
      final route = ValueNotifier<Widget>(
        const DeliveryTaskRoutePage(taskId: taskId),
      );
      final codSubscription = container.listen(
        shipperCodViewModelProvider(null),
        (_, _) {},
      );

      var disposed = false;
      Future<void> disposeFixture() async {
        if (disposed) return;
        disposed = true;
        codSubscription.close();
        route.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        container.dispose();
        await tester.runAsync(client.dispose);
        await tester.pump();
      }

      addTearDown(disposeFixture);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: ValueListenableBuilder<Widget>(
              valueListenable: route,
              builder: (_, page, _) => Scaffold(body: page),
            ),
          ),
        ),
      );
      // MH11: server-backed detail, guarded full-goods/full-COD confirmation.
      await _until(
        tester,
        () =>
            container.read(shipperCodViewModelProvider(null)).heldTotalVnd == 0,
      );
      await _until(
        tester,
        () =>
            find.byKey(const ValueKey('completion-open')).evaluate().isNotEmpty,
      );
      await _tapOnce(tester, find.byKey(const ValueKey('completion-open')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('completion-dialog-amount')),
            )
            .data,
        '550.000 đ',
      );
      expect(find.byType(TextField), findsNothing);
      await _tapOnce(tester, find.byKey(const ValueKey('completion-goods')));
      await _tapOnce(tester, find.byKey(const ValueKey('completion-money')));
      await _tapOnce(tester, find.byKey(const ValueKey('completion-confirm')));
      await tester.pumpAndSettle();
      await _until(
        tester,
        () => find
            .byKey(const ValueKey('completion-confirmed'))
            .evaluate()
            .isNotEmpty,
      );

      expect(fixture.completionCalls, 1, reason: 'one UI confirmation tap');
      await _until(
        tester,
        () =>
            container.read(shipperCodViewModelProvider(null)).heldTotalVnd ==
            550000,
      );
      expect(fixture.completionBodies.single.keys.toSet(), {
        'p_task_id',
        'p_request_id',
        'p_received_all_items',
        'p_collected_amount_vnd',
      });
      expect(fixture.completionBodies.single, {
        'p_task_id': taskId,
        'p_request_id': _completionRequestId,
        'p_received_all_items': true,
        'p_collected_amount_vnd': 550000,
      });
      expect(
        _uuid.hasMatch(fixture.completionBodies.single['p_task_id'] as String),
        true,
      );
      expect(
        _uuid.hasMatch(
          fixture.completionBodies.single['p_request_id'] as String,
        ),
        true,
      );

      // MH10 authoritative refresh: the completed task comes from the list RPC.
      route.value = const DeliveryTasksRoutePage();
      await tester.pumpAndSettle();
      await _until(
        tester,
        () =>
            find.byKey(ValueKey('delivery-task-$taskId')).evaluate().isNotEmpty,
      );
      expect(find.text('Đã giao thành công'), findsOneWidget);
      expect(fixture.taskListCalls, greaterThan(0));

      // MH12 shipper view: COD is collected and the server total is 550,000 VND.
      route.value = const CodRoutePage();
      await tester.pumpAndSettle();
      await _until(
        tester,
        () => find.byType(ShipperCodPage).evaluate().isNotEmpty,
      );
      await _until(
        tester,
        () =>
            find.byKey(const ValueKey('cod-held-total')).evaluate().isNotEmpty,
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('cod-held-total'))).data,
        '550.000 đ',
      );
      final shipperQuery = fixture.codQueryBodies.last;
      expect(shipperQuery['p_shipper_id'], _shipperId);
      expect(shipperQuery['p_statuses'], ['collected']);

      // Role switch: the same provider container must discard the shipper view
      // and re-authorize MH12 as manager from the server profile projection.
      final beforeManagerQueries = fixture.codQueryBodies.length;
      await tester.runAsync(() => recoverFixtureSession(client, _managerId));
      route.value = const CodRoutePage();
      await tester.pumpAndSettle();
      await _until(
        tester,
        () => find.byType(ManagerCodPanel).evaluate().isNotEmpty,
      );
      await _until(
        tester,
        () => fixture.codQueryBodies.length > beforeManagerQueries,
      );
      expect(fixture.codQueryBodies.last['p_shipper_id'], isNull);
      expect(fixture.codQueryBodies.last['p_statuses'], ['collected']);
      await _until(
        tester,
        () => find
            .byKey(ValueKey('manager-cod-open-$orderId'))
            .evaluate()
            .isNotEmpty,
      );
      await _tapOnce(tester, find.byKey(ValueKey('manager-cod-open-$orderId')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('manager-cod-confirm-amount')),
            )
            .data,
        '550.000 đ',
      );
      await _tapOnce(
        tester,
        find.byKey(const ValueKey('manager-cod-received-full')),
      );
      await _tapOnce(tester, find.byKey(const ValueKey('manager-cod-confirm')));
      await tester.pumpAndSettle();
      await _until(
        tester,
        () =>
            find
                .byKey(const ValueKey('manager-cod-held-total'))
                .evaluate()
                .isNotEmpty &&
            find.text('0 đ').evaluate().isNotEmpty,
      );

      expect(fixture.receiptCalls, 1, reason: 'one manager receipt tap');
      expect(fixture.receiptBodies.single.keys.toSet(), {
        'p_order_id',
        'p_received_amount_vnd',
        'p_request_id',
      });
      expect(fixture.receiptBodies.single, {
        'p_order_id': orderId,
        'p_received_amount_vnd': 550000,
        'p_request_id': _receiptRequestId,
      });
      expect(
        _uuid.hasMatch(fixture.receiptBodies.single['p_order_id'] as String),
        true,
      );
      expect(
        _uuid.hasMatch(fixture.receiptBodies.single['p_request_id'] as String),
        true,
      );
      expect(find.byKey(ValueKey('manager-cod-open-$orderId')), findsNothing);

      // Return to shipper: received row is visible only in reconciled group,
      // held total is zero, and no manager action leaks across the role epoch.
      await tester.runAsync(() => recoverFixtureSession(client, _shipperId));
      route.value = const CodRoutePage();
      await tester.pumpAndSettle();
      await _until(
        tester,
        () => find.byType(ShipperCodPage).evaluate().isNotEmpty,
      );
      await _until(
        tester,
        () =>
            find.byKey(const ValueKey('cod-held-total')).evaluate().isNotEmpty,
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('cod-held-total'))).data,
        '0 đ',
      );
      expect(find.byKey(ValueKey('manager-cod-confirm')), findsNothing);
      expect(find.byKey(ValueKey('manager-cod-open-$orderId')), findsNothing);
      await _tapOnce(tester, find.byKey(const ValueKey('cod-reconciled')));
      await tester.pumpAndSettle();
      await _until(
        tester,
        () => find.byKey(ValueKey('cod-record-$orderId')).evaluate().isNotEmpty,
      );
      expect(find.text('Đã đối soát'), findsOneWidget);
      expect(fixture.codQueryBodies.last['p_statuses'], ['received']);
      expect(fixture.codQueryBodies.last['p_shipper_id'], _shipperId);
      await disposeFixture();
    },
  );
}
