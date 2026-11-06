import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/data/repositories/supabase_outbound_completion_repository.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_completion_command.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_completion_failure.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';

import '../support/operational_supabase_fixture.dart';

const command = OutboundCompletionCommand(
  taskId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  requestId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
  receivedAllItems: true,
  reportedCollectedAmountVnd: 550000,
);
Map<String, dynamic> ack() => {
  'task_id': command.taskId,
  'request_id': command.requestId,
  'order_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  'event_id': 'ffffffff-ffff-4fff-8fff-ffffffffffff',
  'operation': 'complete',
  'task_status': 'delivered',
  'order_status': 'delivered',
  'attempt_number': 1,
  'delivery_attempt_count': 1,
  'collected_amount_vnd': 550000,
  'completed_at': '2026-10-26T08:00:00Z',
};
void main() {
  test('production adapter sends exactly approved inputs; transport retry disabled', () async {
    final bodies = <Object?>[];
    var fail = true;
    final client = await fixtureClient((request) async {
      if (request.url.path.endsWith('/profiles')) {
        return jsonResponse(request, [
          {'role': 'shipper'},
        ]);
      }
      expect(request.url.path, endsWith('/rpc/complete_outbound_delivery'));
      bodies.add(jsonDecode(request.body));
      if (fail) {
        return jsonResponse(request, {
          'code': '503',
          'message': 'unavailable',
        }, status: 503);
      }
      return jsonResponse(request, ack());
    }, userId: shipperA);
    final access = OperationalReadAccess(client);
    addTearDown(() async {
      await access.dispose();
      await client.dispose();
    });
    final repo = SupabaseOutboundCompletionRepository(access: access);
    await expectLater(repo.execute(command), throwsA(anything));
    expect(bodies, hasLength(1));
    fail = false;
    await repo.execute(command);
    expect(bodies, hasLength(2));
    expect(bodies.first, bodies.last);
    expect(bodies.last, {
      'p_task_id': command.taskId,
      'p_request_id': command.requestId,
      'p_received_all_items': true,
      'p_collected_amount_vnd': 550000,
    });
  });
  for (final field in [
    'collected_amount_vnd',
    'completed_at',
    'delivery_attempt_count',
  ]) {
    test('reject malformed ACK $field without fake success', () async {
      final response = ack();
      response[field] = switch (field) {
        'completed_at' => '2026-02-30T08:00:00Z',
        'delivery_attempt_count' => 1.5,
        _ => 520000,
      };
      final client = await fixtureClient(
        (request) async => request.url.path.endsWith('/profiles')
            ? jsonResponse(request, [
                {'role': 'shipper'},
              ])
            : jsonResponse(request, response),
        userId: shipperA,
      );
      final access = OperationalReadAccess(client);
      addTearDown(() async {
        await access.dispose();
        await client.dispose();
      });
      await expectLater(
        SupabaseOutboundCompletionRepository(access: access).execute(command),
        throwsA(isA<OutboundAcknowledgementFailure>()),
      );
    });
  }
  test('server business error stays typed and safe', () async {
    final client = await fixtureClient(
      (request) async => request.url.path.endsWith('/profiles')
          ? jsonResponse(request, [
              {'role': 'shipper'},
            ])
          : jsonResponse(request, {
              'code': 'PT409',
              'message': 'AMOUNT_MISMATCH',
            }, status: 409),
      userId: shipperA,
    );
    final access = OperationalReadAccess(client);
    addTearDown(() async {
      await access.dispose();
      await client.dispose();
    });
    await expectLater(
      SupabaseOutboundCompletionRepository(access: access).execute(command),
      throwsA(isA<OutboundCompletionBusinessFailure>()),
    );
  });
  test(
    'same-user refresh after dispatch retains uncertain command semantics',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      final client = await fixtureClient((request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        started.complete();
        await release.future;
        return jsonResponse(request, ack());
      }, userId: shipperA);
      final access = OperationalReadAccess(client);
      addTearDown(() async {
        await access.dispose();
        await client.dispose();
      });
      final pending = SupabaseOutboundCompletionRepository(access: access)
          .execute(command);
      await started.future;
      access.refreshSession();
      release.complete();
      await expectLater(
        pending,
        throwsA(isA<OutboundAcknowledgementFailure>()),
      );
    },
  );
}
