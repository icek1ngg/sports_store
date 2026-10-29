import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/data/repositories/supabase_outbound_task_command_repository.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';

import '../support/operational_supabase_fixture.dart';

const _shipperId = shipperA;
const _otherShipperId = shipperB;
const _taskId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _orderId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const _requestId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const _dispatchEventId = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
const _eventId = '99999999-9999-4999-8999-999999999999';

void main() {
  test(
    'accept sends only the production RPC parameters and validates its ACK',
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
          return jsonResponse(request, _ack());
        },
      );
      try {
        await _repository(access).execute(_command());

        final rpc = requests.singleWhere(
          (request) => request.url.path.endsWith('/rpc/accept_delivery_task'),
        );
        expect(jsonDecode(rpc.body), {
          'p_task_id': _taskId,
          'p_request_id': _requestId,
        });
        expect(
          requests.any(
            (request) => request.url.path.contains('/delivery_tasks'),
          ),
          isFalse,
        );
      } finally {
        await _dispose(access);
      }
    },
  );

  test(
    'start selects the start RPC and validates delivering/attempt state',
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
          return jsonResponse(
            request,
            _ack(action: OutboundTaskAction.startDelivery),
          );
        },
      );
      try {
        await _repository(access)
            .execute(_command(action: OutboundTaskAction.startDelivery));
        final rpc = requests.singleWhere(
          (request) => request.url.path.endsWith('/rpc/start_delivery_task'),
        );
        expect(jsonDecode(rpc.body), {
          'p_task_id': _taskId,
          'p_request_id': _requestId,
        });
      } finally {
        await _dispose(access);
      }
    },
  );

  test(
    'invalid command UUIDs fail before session/profile or RPC access',
    () async {
      final requests = <http.Request>[];
      final access = await _access(
        handler: (request) async {
          requests.add(request);
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        },
      );
      try {
        await expectLater(
          _repository(access).execute(
            const OutboundTaskCommand(
              taskId: 'not-a-uuid',
              requestId: _requestId,
              action: OutboundTaskAction.acceptGoods,
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
        expect(requests, isEmpty);
      } finally {
        await _dispose(access);
      }
    },
  );

  test(
    'role denial is mapped by shared operational access before the RPC',
    () async {
      final requests = <http.Request>[];
      final access = await _access(
        handler: (request) async {
          requests.add(request);
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'role': 'manager'},
            ]);
          }
          return jsonResponse(request, _ack());
        },
      );
      try {
        await expectLater(
          _repository(access).execute(_command()),
          throwsA(
            isA<OperationalFailure>().having(
              (failure) => failure.code,
              'code',
              OperationalFailureCode.permissionDenied,
            ),
          ),
        );
        expect(
          requests.where(
            (request) => request.url.path.endsWith('/rpc/accept_delivery_task'),
          ),
          isEmpty,
        );
      } finally {
        await _dispose(access);
      }
    },
  );

  test(
    'each documented PT409 marker is a typed safe business failure',
    () async {
      const markers = <String, OutboundBusinessFailureCode>{
        'STATE_CONFLICT': OutboundBusinessFailureCode.stateConflict,
        'IDEMPOTENCY_CONFLICT': OutboundBusinessFailureCode.idempotencyConflict,
        'CUSTODY_UNRESOLVED': OutboundBusinessFailureCode.custodyUnresolved,
        'ITEMS_MISMATCH': OutboundBusinessFailureCode.itemsMismatch,
        'STOCK_CONFLICT': OutboundBusinessFailureCode.stockConflict,
        'COD_CONFLICT': OutboundBusinessFailureCode.codConflict,
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
            _repository(access).execute(_command()),
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

  test(
    'unknown PT409 text is unexpected and never exposed as a business code',
    () async {
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
          _repository(access).execute(_command()),
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
    },
  );

  test('authorization code wins over a misleading conflict message', () async {
    final access = await _access(
      handler: (request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        return jsonResponse(request, {
          'code': '42501',
          'message': 'STATE_CONFLICT',
        }, status: 403);
      },
    );
    try {
      await expectLater(
        _repository(access).execute(_command()),
        throwsA(
          isA<OperationalFailure>().having(
            (failure) => failure.code,
            'code',
            OperationalFailureCode.permissionDenied,
          ),
        ),
      );
    } finally {
      await _dispose(access);
    }
  });

  test(
    'missing RPC is backend unavailable and has no table-read fallback',
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
          return jsonResponse(request, {
            'code': 'PGRST202',
            'message': 'function does not exist',
          }, status: 404);
        },
      );
      try {
        await expectLater(
          _repository(access).execute(_command()),
          throwsA(
            isA<OperationalFailure>().having(
              (failure) => failure.code,
              'code',
              OperationalFailureCode.backendUnavailable,
            ),
          ),
        );
        expect(
          requests.any(
            (request) => request.url.path.contains('/delivery_tasks'),
          ),
          isFalse,
        );
      } finally {
        await _dispose(access);
      }
    },
  );

  test('RPC timeout maps to network without SDK retry', () async {
    var rpcCalls = 0;
    final access = await _access(
      readTimeout: const Duration(milliseconds: 15),
      handler: (request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        rpcCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return jsonResponse(request, _ack());
      },
    );
    try {
      await expectLater(
        _repository(access).execute(_command()),
        throwsA(
          isA<OperationalFailure>().having(
            (failure) => failure.code,
            'code',
            OperationalFailureCode.network,
          ),
        ),
      );
      expect(rpcCalls, 1);
    } finally {
      await _dispose(access);
    }
  });

  test(
    'malformed successful ACK is typed and replay keeps the same request ID',
    () async {
      var rpcCalls = 0;
      final bodies = <Map<String, dynamic>>[];
      final access = await _access(
        handler: (request) async {
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'role': 'shipper'},
            ]);
          }
          rpcCalls++;
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (rpcCalls == 1) {
            return jsonResponse(request, {
              'task_id': _taskId,
              'request_id': _requestId,
              'operation': 'accept',
            });
          }
          return jsonResponse(request, _ack());
        },
      );
      try {
        final repository = _repository(access);
        await expectLater(
          repository.execute(_command()),
          throwsA(
            isA<OutboundAcknowledgementFailure>().having(
              (failure) => failure.code,
              'code',
              OutboundCommandFailureCode.invalidData,
            ),
          ),
        );
        await repository.execute(_command());
        expect(bodies, hasLength(2));
        expect(bodies[0]['p_request_id'], _requestId);
        expect(bodies[1]['p_request_id'], _requestId);
      } finally {
        await _dispose(access);
      }
    },
  );

  for (final sameActor in [false, true]) {
    test(
      'late response after session change preserves only same actor key ($sameActor)',
      () async {
        final rpcStarted = Completer<void>();
        final rpcResponse = Completer<http.Response>();
        http.Request? rpcRequest;
        final access = await _access(
          handler: (request) async {
            if (request.url.path.endsWith('/profiles')) {
              return jsonResponse(request, [
                {'role': 'shipper'},
              ]);
            }
            rpcRequest = request;
            if (!rpcStarted.isCompleted) rpcStarted.complete();
            return rpcResponse.future;
          },
        );
        try {
          final pending = _repository(access).execute(_command());
          await rpcStarted.future;
          await recoverFixtureSession(
            access.client,
            sameActor ? _shipperId : _otherShipperId,
          );
          if (sameActor) access.refreshSession();
          rpcResponse.complete(jsonResponse(rpcRequest!, _ack()));
          await expectLater(
            pending,
            throwsA(
              sameActor
                  ? isA<OutboundAcknowledgementFailure>()
                  : isA<OperationalFailure>().having(
                      (failure) => failure.code,
                      'code',
                      OperationalFailureCode.sessionExpired,
                    ),
            ),
          );
        } finally {
          if (!rpcResponse.isCompleted) {
            rpcResponse.completeError(StateError('test cleanup'));
          }
          await _dispose(access);
        }
      },
    );
  }

  for (final malformed in <String, Map<String, dynamic>>{
    'wrong task identity': _ack()..['task_id'] = _orderId,
    'wrong request identity': _ack()..['request_id'] = _orderId,
    'wrong operation': _ack()..['operation'] = 'start',
    'wrong task status': _ack()..['task_status'] = 'in_transit',
    'wrong order status': _ack()..['order_status'] = 'delivering',
    'invalid event UUID': _ack()..['event_id'] = 'not-a-uuid',
    'invalid attempt count': _ack()..['delivery_attempt_count'] = 1,
    'invalid accepted timestamp': _ack()
      ..['accepted_at'] = '2026-02-30T08:00:00Z',
    'missing timezone': _ack()..['accepted_at'] = '2026-10-25T08:00:00',
    'missing started_at field': _ack()..remove('started_at'),
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
          _repository(access).execute(_command()),
          throwsA(isA<OutboundAcknowledgementFailure>()),
        );
      } finally {
        await _dispose(access);
      }
    });
  }
}

OutboundTaskCommand _command({
  OutboundTaskAction action = OutboundTaskAction.acceptGoods,
}) =>
    OutboundTaskCommand(taskId: _taskId, requestId: _requestId, action: action);

Map<String, dynamic> _ack({
  OutboundTaskAction action = OutboundTaskAction.acceptGoods,
}) {
  final isAccept = action == OutboundTaskAction.acceptGoods;
  return {
    'task_id': _taskId,
    'order_id': _orderId,
    'operation': isAccept ? 'accept' : 'start',
    'task_status': isAccept ? 'accepted' : 'in_transit',
    'order_status': isAccept ? 'awaiting_pickup' : 'delivering',
    'attempt_number': 1,
    'delivery_attempt_count': isAccept ? 0 : 1,
    'accepted_at': '2026-10-25T08:00:00.123456Z',
    'started_at': isAccept ? null : '2026-10-25T08:05:00.123456+00:00',
    'dispatch_event_id': _dispatchEventId,
    'event_id': _eventId,
    'request_id': _requestId,
  };
}

SupabaseOutboundTaskCommandRepository _repository(
  OperationalReadAccess access,
) => SupabaseOutboundTaskCommandRepository(access: access);

Future<OperationalReadAccess> _access({
  required Future<http.Response> Function(http.Request request) handler,
  Duration readTimeout = const Duration(seconds: 2),
}) async {
  final client = await fixtureClient(handler, userId: _shipperId);
  final access = OperationalReadAccess(client, readTimeout: readTimeout);
  await Future<void>.delayed(Duration.zero);
  return access;
}

Future<void> _dispose(OperationalReadAccess access) async {
  final client = access.client;
  await access.dispose();
  await client.dispose();
}
