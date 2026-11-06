import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/data/repositories/supabase_outbound_failure_repository.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_failure_command.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';

import '../support/operational_supabase_fixture.dart';

const _taskId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _orderId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const _requestId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const _eventId = 'ffffffff-ffff-4fff-8fff-ffffffffffff';

const _command = OutboundFailureCommand(
  taskId: _taskId,
  requestId: _requestId,
  attemptNumber: 1,
  reason: OutboundFailureReason.unreachable,
);

Map<String, dynamic> _ack({int attemptNumber = 1, String? description}) => {
  'task_id': _taskId,
  'order_id': _orderId,
  'operation': 'fail',
  'task_status': 'failed',
  'order_status': attemptNumber == 1
      ? 'awaiting_redelivery'
      : 'awaiting_store_return',
  'attempt_number': attemptNumber,
  'delivery_attempt_count': attemptNumber,
  'failure_reason_code': _command.reason.value,
  'failure_reason_description': description,
  'failed_at': '2026-10-27T08:00:00.123456Z',
  'event_id': _eventId,
  'request_id': _requestId,
};

Future<OperationalReadAccess> _access({
  required Future<dynamic> Function(dynamic request) handler,
  Duration readTimeout = const Duration(seconds: 2),
}) async {
  final client = await fixtureClient((request) async {
    final response = await handler(request);
    return response;
  });
  final access = OperationalReadAccess(client, readTimeout: readTimeout);
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
    'sends only approved RPC inputs and returns the validated ACK',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final access = await _access(
        handler: (request) async {
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'role': 'shipper'},
            ]);
          }
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          expect(request.url.path, endsWith('/rpc/fail_delivery_task'));
          return jsonResponse(request, _ack());
        },
      );
      try {
        final result = await SupabaseOutboundFailureRepository(access: access)
            .execute(_command);
        expect(result.taskId, _taskId);
        expect(result.requestId, _requestId);
        expect(result.attemptNumber, 1);
        expect(result.disposition, OutboundFailureDisposition.managerDecision);
        expect(bodies, [
          {
            'p_task_id': _taskId,
            'p_request_id': _requestId,
            'p_reason_code': 'unreachable',
            'p_description': null,
          },
        ]);
      } finally {
        await _dispose(access);
      }
    },
  );

  test(
    'trims description before transport and requires it for other',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final command = const OutboundFailureCommand(
        taskId: _taskId,
        requestId: _requestId,
        attemptNumber: 1,
        reason: OutboundFailureReason.other,
        description: '  gate closed  ',
      );
      final access = await _access(
        handler: (request) async {
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'role': 'shipper'},
            ]);
          }
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return jsonResponse(request, {
            ..._ack(description: 'gate closed'),
            'failure_reason_code': 'other',
          });
        },
      );
      try {
        final result = await SupabaseOutboundFailureRepository(access: access)
            .execute(command);
        expect(result.disposition, OutboundFailureDisposition.managerDecision);
        expect(bodies.single['p_reason_code'], 'other');
        expect(bodies.single['p_description'], 'gate closed');
      } finally {
        await _dispose(access);
      }
    },
  );

  test('invalid command fails before profile or RPC access', () async {
    var requests = 0;
    final access = await _access(
      handler: (request) async {
        requests++;
        return jsonResponse(request, [
          {'role': 'shipper'},
        ]);
      },
    );
    try {
      await expectLater(
        SupabaseOutboundFailureRepository(access: access).execute(
          const OutboundFailureCommand(
            taskId: 'not-a-uuid',
            requestId: _requestId,
            attemptNumber: 1,
            reason: OutboundFailureReason.unreachable,
          ),
        ),
        throwsA(
          isA<OperationalFailure>().having(
            (failure) => failure.code,
            'code',
            OperationalFailureCode.invalidData,
          ),
        ),
      );
      expect(requests, 0);
    } finally {
      await _dispose(access);
    }
  });

  test('other without a description is rejected before transport', () async {
    final access = await _access(
      handler: (request) async => jsonResponse(request, [
        {'role': 'shipper'},
      ]),
    );
    try {
      await expectLater(
        SupabaseOutboundFailureRepository(access: access).execute(
          const OutboundFailureCommand(
            taskId: _taskId,
            requestId: _requestId,
            attemptNumber: 1,
            reason: OutboundFailureReason.other,
            description: '  ',
          ),
        ),
        throwsA(
          isA<OperationalFailure>().having(
            (failure) => failure.code,
            'code',
            OperationalFailureCode.invalidData,
          ),
        ),
      );
    } finally {
      await _dispose(access);
    }
  });

  test('role denial is handled before the failure RPC', () async {
    var rpcCalled = false;
    final access = await _access(
      handler: (request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'manager'},
          ]);
        }
        rpcCalled = true;
        return jsonResponse(request, _ack());
      },
    );
    try {
      await expectLater(
        SupabaseOutboundFailureRepository(access: access).execute(_command),
        throwsA(
          isA<OperationalFailure>().having(
            (failure) => failure.code,
            'code',
            OperationalFailureCode.permissionDenied,
          ),
        ),
      );
      expect(rpcCalled, isFalse);
    } finally {
      await _dispose(access);
    }
  });

  test(
    'documented PT409 markers map to safe typed business failures',
    () async {
      const markers = <String, OutboundBusinessFailureCode>{
        'STATE_CONFLICT': OutboundBusinessFailureCode.stateConflict,
        'IDEMPOTENCY_CONFLICT': OutboundBusinessFailureCode.idempotencyConflict,
        'CUSTODY_UNRESOLVED': OutboundBusinessFailureCode.custodyUnresolved,
        'ITEMS_MISMATCH': OutboundBusinessFailureCode.itemsMismatch,
        'STOCK_CONFLICT': OutboundBusinessFailureCode.stockConflict,
        'COD_CONFLICT': OutboundBusinessFailureCode.codConflict,
        'AMOUNT_MISMATCH': OutboundBusinessFailureCode.codConflict,
        'ATTEMPT_LIMIT': OutboundBusinessFailureCode.attemptLimit,
        'DISPATCH_CONFLICT': OutboundBusinessFailureCode.dispatchConflict,
      };

      for (final entry in markers.entries) {
        final access = await _access(
          handler: (request) async {
            if (request.url.path.endsWith('/profiles')) {
              return jsonResponse(request, [
                {'role': 'shipper'},
              ]);
            }
            return jsonResponse(request, {
              'code': 'PT409',
              'message': entry.key,
            }, status: 409);
          },
        );
        try {
          await expectLater(
            SupabaseOutboundFailureRepository(access: access).execute(_command),
            throwsA(
              isA<OutboundBusinessFailure>().having(
                (failure) => failure.businessCode,
                'businessCode',
                entry.value,
              ),
            ),
          );
        } finally {
          await _dispose(access);
        }
      }
    },
  );

  test('unknown PT409 text is unexpected and never exposed', () async {
    final access = await _access(
      handler: (request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        return jsonResponse(request, {
          'code': 'PT409',
          'message': 'STATE_CONFLICT: private detail',
        }, status: 409);
      },
    );
    try {
      await expectLater(
        SupabaseOutboundFailureRepository(access: access).execute(_command),
        throwsA(
          isA<OperationalFailure>().having(
            (failure) => failure.code,
            'code',
            OperationalFailureCode.unexpected,
          ),
        ),
      );
    } finally {
      await _dispose(access);
    }
  });

  test('missing RPC is backend unavailable with no read fallback', () async {
    final requests = <String>[];
    final access = await _access(
      handler: (request) async {
        requests.add(request.url.path);
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        return jsonResponse(request, {
          'code': 'PGRST202',
          'message': 'function does not exist',
        }, status: 404);
      },
    );
    try {
      await expectLater(
        SupabaseOutboundFailureRepository(access: access).execute(_command),
        throwsA(
          isA<OperationalFailure>().having(
            (failure) => failure.code,
            'code',
            OperationalFailureCode.backendUnavailable,
          ),
        ),
      );
      expect(
        requests.where((path) => path.contains('/delivery_tasks')),
        isEmpty,
      );
    } finally {
      await _dispose(access);
    }
  });

  for (final malformed in <String, Map<String, dynamic>>{
    'wrong task identity': _ack()..['task_id'] = _orderId,
    'wrong request identity': _ack()..['request_id'] = _orderId,
    'wrong operation': _ack()..['operation'] = 'complete',
    'wrong task status': _ack()..['task_status'] = 'in_transit',
    'wrong order status': _ack()..['order_status'] = 'delivering',
    'wrong attempt': _ack()..['attempt_number'] = 2,
    'wrong attempt count': _ack()..['delivery_attempt_count'] = 2,
    'wrong reason': _ack()..['failure_reason_code'] = 'refusal',
    'invalid event UUID': _ack()..['event_id'] = 'not-a-uuid',
    'invalid failed timestamp': _ack()..['failed_at'] = '2026-02-30T08:00:00Z',
    'missing description': _ack()..remove('failure_reason_description'),
  }.entries) {
    test('malformed ACK rejects ${malformed.key}', () async {
      final access = await _access(
        handler: (request) async {
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'role': 'shipper'},
            ]);
          }
          return jsonResponse(request, malformed.value);
        },
      );
      try {
        await expectLater(
          SupabaseOutboundFailureRepository(access: access).execute(_command),
          throwsA(isA<OutboundAcknowledgementFailure>()),
        );
      } finally {
        await _dispose(access);
      }
    });
  }

  test(
    'same-user refresh after dispatch retains the uncertain request key',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final access = await _access(
        handler: (request) async {
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'role': 'shipper'},
            ]);
          }
          started.complete();
          await release.future;
          return jsonResponse(request, _ack());
        },
      );
      try {
        final pending = SupabaseOutboundFailureRepository(access: access)
            .execute(_command);
        await started.future;
        access.refreshSession();
        release.complete();
        await expectLater(
          pending,
          throwsA(isA<OutboundAcknowledgementFailure>()),
        );
      } finally {
        if (!release.isCompleted) release.complete();
        await _dispose(access);
      }
    },
  );

  test(
    'second attempt validates store-return disposition and status',
    () async {
      const command = OutboundFailureCommand(
        taskId: _taskId,
        requestId: _requestId,
        attemptNumber: 2,
        reason: OutboundFailureReason.refusal,
      );
      final access = await _access(
        handler: (request) async {
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'role': 'shipper'},
            ]);
          }
          return jsonResponse(request, {
            ..._ack(attemptNumber: 2),
            'failure_reason_code': 'refusal',
          });
        },
      );
      try {
        final result = await SupabaseOutboundFailureRepository(access: access)
            .execute(command);
        expect(result.attemptNumber, 2);
        expect(
          result.disposition,
          OutboundFailureDisposition.storeReturnPending,
        );
      } finally {
        await _dispose(access);
      }
    },
  );
}
