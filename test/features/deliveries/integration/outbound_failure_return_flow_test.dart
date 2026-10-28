// P10.2 OFFLINE transport fixture: real repositories/providers, no database.
// Manager retry is an explicitly modeled RPC boundary, not an MH09 UI.
// P10.1 SQL suites separately prove locks, stock and financial invariants.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_failure_command.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_providers.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_reporting_view_model.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_task_list_view_model.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/outbound_failure_view_model.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/outbound_task_actions_view_model.dart';

import '../../support/operational_supabase_fixture.dart';
import '../fixtures/delivery_dtos.dart';

const _manager = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _task2 = '55555555-5555-4555-8555-555555555555';
const _event = '66666666-6666-4666-8666-666666666666';
const _stamp = '2026-10-28T03:00:00Z';

class _TransportFixture {
  String actor = shipperA;
  String orderStatus = 'delivering';
  final states = <String, String>{taskId: 'in_transit'};
  final writes = <String>[];
  final requests = <String>[];
  bool handedOver = false;
  int listReads = 0;

  Map<String, dynamic> row(String id) {
    final status = states[id]!;
    final attempt = id == taskId ? 1 : 2;
    if (status == 'failed') {
      return maskedTaskDto()
        ..['task_id'] = id
        ..['attempt_number'] = attempt;
    }
    return currentTaskDto(
      task: id,
      status: status,
      acceptedAt: status == 'assigned' ? null : _stamp,
      startedAt: status == 'in_transit' ? _stamp : null,
    )..['attempt_number'] = attempt;
  }

  Future<http.Response> handle(http.Request request) async {
    final name = request.url.pathSegments.last;
    if (name == 'profiles') {
      return jsonResponse(request, [
        {'role': actor == _manager ? 'manager' : 'shipper'},
      ]);
    }
    final p = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    if (name == 'get_my_delivery_task') {
      final id = p['p_task_id'] as String;
      return jsonResponse(request, {
        'task': row(id),
        'items': states[id] == 'failed' ? [] : [outboundItemDto()],
        'notes': null,
        'notes_source': 'unavailable_schema',
        'as_of': _stamp,
      });
    }
    if (name == 'list_my_delivery_tasks') {
      listReads++;
      final rows = states.keys.map(row).toList();
      return jsonResponse(request, {
        'items': rows,
        'next_cursor': null,
        'filtered_total': rows.length,
        'counts': {
          'waiting': states.values
              .where((s) => s == 'assigned' || s == 'accepted')
              .length,
          'in_transit': states.values.where((s) => s == 'in_transit').length,
          'completed': 0,
          'ungrouped': states.values.where((s) => s == 'failed').length,
        },
        'as_of': _stamp,
      });
    }
    if (name == 'read_my_delivery_tasks') {
      return jsonResponse(request, states.keys.map(row).toList());
    }
    if (name == 'assign_delivery_task') {
      // Approved contract forbids changing holder after physical acceptance.
      expect(p['p_shipper_id'], shipperB);
      return jsonResponse(request, {
        'code': 'PT409',
        'message': 'CUSTODY_UNRESOLVED',
      }, status: 409);
    }
    if (name == 'decide_outbound_retry') {
      expect(actor, _manager);
      expect(p['p_decision'], 'retry');
      expect(p['p_expected_failed_task_id'], taskId);
      states[_task2] = 'assigned';
      orderStatus = 'awaiting_pickup';
      writes.add(name);
      return jsonResponse(request, {
        'task_id': _task2,
        'assigned_shipper_id': shipperA,
      });
    }
    final id = p['p_task_id'] as String;
    final attempt = id == taskId ? 1 : 2;
    if (name == 'get_my_delivery_reporting_context') {
      return jsonResponse(request, {
        'task_id': id,
        'task_status': states[id],
        'order_status': orderStatus,
        'can_handover': orderStatus == 'awaiting_store_return' && !handedOver,
        'can_incident': true,
        'handover_reported': handedOver,
        'handover_block_reason': null,
        'incident_block_reason': null,
        'items': [
          {
            'order_item_id': itemId,
            'product_name': 'Bóng đá',
            'variant_label': 'Size 5',
            'quantity': 2,
          },
        ],
      });
    }
    expect(actor, shipperA);
    writes.add(name);
    requests.add(p['p_request_id'] as String);
    if (name == 'fail_delivery_task') {
      expect(p.keys.toSet(), {
        'p_task_id',
        'p_request_id',
        'p_reason_code',
        'p_description',
      });
      states[id] = 'failed';
      orderStatus = attempt == 1
          ? 'awaiting_redelivery'
          : 'awaiting_store_return';
      return jsonResponse(request, {
        'task_id': id,
        'order_id': orderId,
        'operation': 'fail',
        'task_status': 'failed',
        'order_status': orderStatus,
        'attempt_number': attempt,
        'delivery_attempt_count': attempt,
        'failure_reason_code': p['p_reason_code'],
        'failure_reason_description': p['p_description'],
        'failed_at': _stamp,
        'event_id': _event,
        'request_id': p['p_request_id'],
      });
    }
    if (name == 'accept_delivery_task' || name == 'start_delivery_task') {
      final accept = name == 'accept_delivery_task';
      expect(p.keys.toSet(), {'p_task_id', 'p_request_id'});
      states[id] = accept ? 'accepted' : 'in_transit';
      orderStatus = accept ? 'awaiting_pickup' : 'delivering';
      return jsonResponse(request, {
        'task_id': id,
        'order_id': orderId,
        'operation': accept ? 'accept' : 'start',
        'task_status': states[id],
        'order_status': orderStatus,
        'attempt_number': 2,
        'delivery_attempt_count': accept ? 1 : 2,
        'accepted_at': _stamp,
        'started_at': accept ? null : _stamp,
        'dispatch_event_id': _event,
        'event_id': _event,
        'request_id': p['p_request_id'],
      });
    }
    if (name == 'report_store_handover') {
      expect(p.keys.toSet(), {'p_task_id', 'p_request_id', 'p_items'});
      expect(p['p_items'], [
        {'order_item_id': itemId, 'quantity': 2},
      ]);
      handedOver = true;
      return jsonResponse(request, {
        'task_id': id,
        'order_id': orderId,
        'operation': name,
        'request_id': p['p_request_id'],
        'event_id': _event,
        'reported_at': _stamp,
        'task_status': 'failed',
        'order_status': 'awaiting_store_return',
      });
    }
    fail('Unexpected fixture endpoint: $name');
  }
}

Future<void> _until(ProviderContainer c, bool Function() ready) async {
  for (var i = 0; i < 300; i++) {
    await Future<void>.delayed(Duration.zero);
    await c.pump();
    if (ready()) return;
  }
  fail('P10.2 fixture providers did not settle');
}

void main() {
  test(
    'fixture integration: fail1 → same-holder task2 → fail2 → handover report',
    () async {
      final backend = _TransportFixture();
      final client = await fixtureClient(backend.handle);
      final c = ProviderContainer(
        overrides: [supabaseClientProvider.overrideWithValue(client)],
      );
      addTearDown(() async {
        c.dispose();
        await client.dispose();
      });
      final list = c.listen(deliveryTaskListViewModelProvider, (_, _) {});
      final first = c.listen(
        outboundFailureViewModelProvider(taskId),
        (_, _) {},
      );
      addTearDown(list.close);
      addTearDown(first.close);
      await _until(
        c,
        () => c.read(outboundFailureViewModelProvider(taskId)).canFail,
      );
      final firstVm = c.read(outboundFailureViewModelProvider(taskId).notifier);
      await firstVm.submit(
        reason: OutboundFailureReason.unreachable,
        sessionRevision: firstVm.sessionRevisionForConfirmation,
      );
      expect(
        c.read(outboundFailureViewModelProvider(taskId)).confirmed,
        isTrue,
      );
      expect(
        c.read(outboundFailureViewModelProvider(taskId)).disposition,
        OutboundFailureDisposition.forAttempt(1),
      );
      expect(
        c.read(deliveryTaskListViewModelProvider).items.single.destination,
        isNull,
      );

      backend.actor = _manager;
      await recoverFixtureSession(client, _manager);
      await expectLater(
        client.rpc(
          'assign_delivery_task',
          params: {
            'p_order_id': orderId,
            'p_shipper_id': shipperB,
            'p_request_id': _event,
            'p_expected_task_id': taskId,
            'p_expected_shipper_id': shipperA,
          },
        ),
        throwsA(
          isA<PostgrestException>().having(
            (e) => e.message,
            'code',
            'CUSTODY_UNRESOLVED',
          ),
        ),
      );
      await client.rpc(
        'decide_outbound_retry',
        params: {
          'p_order_id': orderId,
          'p_request_id': _event,
          'p_decision': 'retry',
          'p_expected_failed_task_id': taskId,
          'p_expected_retry_task_id': null,
        },
      );
      backend.actor = shipperA;
      await recoverFixtureSession(client, shipperA);
      final actions = c.listen(
        outboundTaskActionsViewModelProvider(_task2),
        (_, _) {},
      );
      addTearDown(actions.close);
      await _until(c, () {
        final task = c
            .read(deliveryTaskDetailsProvider(_task2))
            .asData
            ?.value
            .task;
        return task != null &&
            c
                .read(outboundTaskActionsViewModelProvider(_task2).notifier)
                .canExecute(OutboundTaskAction.acceptGoods, task);
      });
      final vm = c.read(outboundTaskActionsViewModelProvider(_task2).notifier);
      final details = c.read(deliveryTaskDetailsProvider(_task2)).requireValue;
      await vm.submit(
        OutboundTaskAction.acceptGoods,
        expectedTask: details.task,
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      await _until(c, () {
        final task = c
            .read(deliveryTaskDetailsProvider(_task2))
            .asData
            ?.value
            .task;
        return task != null &&
            c
                .read(outboundTaskActionsViewModelProvider(_task2).notifier)
                .canExecute(OutboundTaskAction.startDelivery, task);
      });
      await vm.submit(
        OutboundTaskAction.startDelivery,
        expectedTask: c
            .read(deliveryTaskDetailsProvider(_task2))
            .requireValue
            .task,
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      final second = c.listen(
        outboundFailureViewModelProvider(_task2),
        (_, _) {},
      );
      addTearDown(second.close);
      await _until(
        c,
        () => c.read(outboundFailureViewModelProvider(_task2)).canFail,
      );
      final secondVm = c.read(
        outboundFailureViewModelProvider(_task2).notifier,
      );
      await secondVm.submit(
        reason: OutboundFailureReason.refusal,
        sessionRevision: secondVm.sessionRevisionForConfirmation,
      );
      expect(
        c.read(outboundFailureViewModelProvider(_task2)).disposition,
        OutboundFailureDisposition.forAttempt(2),
      );
      final reporting = c.listen(
        deliveryReportingViewModelProvider(_task2),
        (_, _) {},
      );
      addTearDown(reporting.close);
      await _until(
        c,
        () => c.read(deliveryReportingViewModelProvider(_task2)).canHandover,
      );
      final reportVm = c.read(
        deliveryReportingViewModelProvider(_task2).notifier,
      );
      await reportVm.submitHandover(
        sessionRevision: reportVm.sessionRevisionForConfirmation,
      );
      expect(
        c.read(deliveryReportingViewModelProvider(_task2)).handoverReported,
        isTrue,
      );
      expect(backend.orderStatus, 'awaiting_store_return');
      expect(backend.states[_task2], 'failed');
      expect(backend.writes, [
        'fail_delivery_task',
        'decide_outbound_retry',
        'accept_delivery_task',
        'start_delivery_task',
        'fail_delivery_task',
        'report_store_handover',
      ]);
      expect(backend.requests.toSet().length, 5);
      expect(backend.listReads, greaterThanOrEqualTo(5));
      expect(
        c.read(deliveryTaskDetailsProvider(_task2)).requireValue.task.status,
        DeliveryTaskStatus.failed,
      );
      expect(
        c
            .read(deliveryTaskDetailsProvider(_task2))
            .requireValue
            .task
            .destination,
        isNull,
      );
      expect(c.read(deliveryTaskListViewModelProvider).items, hasLength(2));
      expect(
        c
            .read(deliveryTaskListViewModelProvider)
            .items
            .every((task) => task.destination == null),
        isTrue,
      );
    },
  );
}
