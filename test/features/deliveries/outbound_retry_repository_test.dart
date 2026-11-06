import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/data/repositories/supabase_outbound_retry_repository.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_retry_command.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';

import '../support/operational_supabase_fixture.dart';

const _failedTaskId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _retryTaskId = '11111111-1111-4111-8111-111111111111';
const _orderId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const _requestId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const _eventId = 'ffffffff-ffff-4fff-8fff-ffffffffffff';

const _command = OutboundRetryCommand(
  taskId: _failedTaskId,
  requestId: _requestId,
);

Map<String, dynamic> _ack({
  String failedTaskId = _failedTaskId,
  String requestId = _requestId,
}) => {
  'task_id': _retryTaskId,
  'failed_task_id': failedTaskId,
  'retry_task_id': _retryTaskId,
  'order_id': _orderId,
  'operation': 'decide_outbound_retry',
  'decision': 'retry',
  'task_status': 'assigned',
  'order_status': 'awaiting_pickup',
  'attempt_number': 2,
  'delivery_attempt_count': 1,
  'holder_id': shipperA,
  'accepted_at': null,
  'started_at': null,
  'event_id': _eventId,
  'request_id': requestId,
};

Future<OperationalReadAccess> _access({
  required Future<http.Response> Function(http.Request request) handler,
}) async {
  final client = await fixtureClient(handler);
  final access = OperationalReadAccess(client);
  await Future<void>.delayed(Duration.zero);
  return access;
}

Future<void> _dispose(OperationalReadAccess access) async {
  final client = access.client;
  await access.dispose();
  await client.dispose();
}

void main() {
  test(
    'sends the task-based retry RPC once and parses the production receipt',
    () async {
      final requests = <http.Request>[];
      final access = await _access(
        handler: (request) async {
          requests.add(request);
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'role': 'shipper'},
            ]);
          }
          expect(
            request.url.path,
            endsWith('/rpc/retry_outbound_delivery_task'),
          );
          return jsonResponse(request, _ack());
        },
      );
      try {
        final result = await SupabaseOutboundRetryRepository(access: access)
            .execute(_command);

        expect(result.failedTaskId, _failedTaskId);
        expect(result.retryTaskId, _retryTaskId);
        expect(result.requestId, _requestId);
        final rpcRequests = requests
            .where(
              (request) => request.url.path.endsWith(
                '/rpc/retry_outbound_delivery_task',
              ),
            )
            .toList();
        expect(rpcRequests, hasLength(1));
        expect(jsonDecode(rpcRequests.single.body), {
          'p_task_id': _failedTaskId,
          'p_request_id': _requestId,
        });
      } finally {
        await _dispose(access);
      }
    },
  );

  test('rejects a receipt bound to another failed task or request', () async {
    for (final response in [
      _ack(failedTaskId: _retryTaskId),
      _ack(requestId: _retryTaskId),
    ]) {
      final access = await _access(
        handler: (request) async => request.url.path.endsWith('/profiles')
            ? jsonResponse(request, [
                {'role': 'shipper'},
              ])
            : jsonResponse(request, response),
      );
      try {
        await expectLater(
          SupabaseOutboundRetryRepository(access: access).execute(_command),
          throwsA(isA<OutboundAcknowledgementFailure>()),
        );
      } finally {
        await _dispose(access);
      }
    }
  });

  test('maps custody PT409 to a typed business failure', () async {
    final access = await _access(
      handler: (request) async => request.url.path.endsWith('/profiles')
          ? jsonResponse(request, [
              {'role': 'shipper'},
            ])
          : jsonResponse(request, {
              'code': 'PT409',
              'message': 'CUSTODY_UNRESOLVED',
            }, status: 409),
    );
    try {
      await expectLater(
        SupabaseOutboundRetryRepository(access: access).execute(_command),
        throwsA(
          isA<OutboundBusinessFailure>().having(
            (failure) => failure.businessCode,
            'businessCode',
            OutboundBusinessFailureCode.custodyUnresolved,
          ),
        ),
      );
    } finally {
      await _dispose(access);
    }
  });
}
