import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:sports_store/features/cod/data/repositories/supabase_cod_receipt_repository.dart';
import 'package:sports_store/features/cod/domain/models/cod_receipt.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';

import '../support/operational_supabase_fixture.dart';

const _managerId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _otherManagerId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _orderId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const _requestId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const _eventId = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
const _notificationId = '99999999-9999-4999-8999-999999999999';

void main() {
  test(
    'sends the exact command parameters and validates server result',
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
          return jsonResponse(request, _receiptPayload());
        },
      );
      try {
        final command = _command();
        final receipt = await SupabaseCodReceiptRepository(access: access)
            .confirmReceipt(command);

        expect(receipt.status, CodReceiptStatus.received);
        expect(receipt.orderId, _orderId);
        expect(receipt.receivedAmountVnd, 550000);
        expect(receipt.receivedBy, _managerId);
        expect(receipt.handedOverAt, receipt.receivedAt);
        expect(receipt.eventId, _eventId);
        expect(receipt.notificationId, _notificationId);

        final rpcRequest = requests.singleWhere(
          (request) => request.url.path.endsWith('/rpc/confirm_cod_received'),
        );
        expect(jsonDecode(rpcRequest.body), {
          'p_order_id': _orderId,
          'p_received_amount_vnd': 550000,
          'p_request_id': _requestId,
        });
      } finally {
        await access.dispose();
        await access.client.dispose();
      }
    },
  );

  test('rejects malformed command before opening a session or RPC', () async {
    final requests = <http.Request>[];
    final access = await _access(
      handler: (request) async {
        requests.add(request);
        return jsonResponse(request, [
          {'role': 'manager'},
        ]);
      },
    );
    try {
      final command = const CodReceiptCommand(
        orderId: 'not-a-uuid',
        receivedAmountVnd: 550000,
        requestId: _requestId,
      );
      await expectLater(
        SupabaseCodReceiptRepository(access: access).confirmReceipt(command),
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
      await access.dispose();
      await access.client.dispose();
    }
  });

  test('maps amount and state conflicts to safe typed failures', () async {
    for (final error in const [
      'AMOUNT_MISMATCH',
      'STATE_CONFLICT',
      'IDEMPOTENCY_CONFLICT',
    ]) {
      final access = await _access(
        handler: (request) async {
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'role': 'manager'},
            ]);
          }
          return jsonResponse(request, {
            'code': 'PT409',
            'message': error,
          }, status: 409);
        },
      );
      try {
        await expectLater(
          SupabaseCodReceiptRepository(access: access)
              .confirmReceipt(_command()),
          throwsA(
            isA<CodReceiptFailure>().having(
              (failure) => failure.receiptCode,
              'receiptCode',
              switch (error) {
                'AMOUNT_MISMATCH' => CodReceiptFailureCode.amountMismatch,
                'IDEMPOTENCY_CONFLICT' =>
                  CodReceiptFailureCode.idempotencyConflict,
                _ => CodReceiptFailureCode.stateConflict,
              },
            ),
          ),
        );
      } finally {
        await access.dispose();
        await access.client.dispose();
      }
    }
  });

  test(
    'maps an authorization code before inspecting arbitrary message text',
    () async {
      final access = await _access(
        handler: (request) async {
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'role': 'manager'},
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
          SupabaseCodReceiptRepository(access: access)
              .confirmReceipt(_command()),
          throwsA(
            isA<OperationalFailure>().having(
              (failure) => failure.code,
              'code',
              OperationalFailureCode.permissionDenied,
            ),
          ),
        );
      } finally {
        await access.dispose();
        await access.client.dispose();
      }
    },
  );

  test(
    'unknown PT409 text is unexpected and missing RPC stays unavailable',
    () async {
      for (final response in [
        (
          code: 'PT409',
          message: 'STATE_CONFLICT: extra server context',
          status: 409,
          expected: OperationalFailureCode.unexpected,
        ),
        (
          code: 'PGRST202',
          message: 'AMOUNT_MISMATCH function not found',
          status: 404,
          expected: OperationalFailureCode.backendUnavailable,
        ),
      ]) {
        final access = await _access(
          handler: (request) async {
            if (request.url.path.endsWith('/profiles')) {
              return jsonResponse(request, [
                {'role': 'manager'},
              ]);
            }
            return jsonResponse(request, {
              'code': response.code,
              'message': response.message,
            }, status: response.status);
          },
        );
        try {
          await expectLater(
            SupabaseCodReceiptRepository(access: access)
                .confirmReceipt(_command()),
            throwsA(
              isA<OperationalFailure>().having(
                (failure) => failure.code,
                'code',
                response.expected,
              ),
            ),
          );
        } finally {
          await access.dispose();
          await access.client.dispose();
        }
      }
    },
  );

  test('denies a shipper before calling the receipt RPC', () async {
    final requests = <http.Request>[];
    final access = await _access(
      handler: (request) async {
        requests.add(request);
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        return jsonResponse(request, _receiptPayload());
      },
    );
    try {
      await expectLater(
        SupabaseCodReceiptRepository(access: access).confirmReceipt(_command()),
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
          (request) => request.url.path.endsWith('/rpc/confirm_cod_received'),
        ),
        isEmpty,
      );
    } finally {
      await access.dispose();
      await access.client.dispose();
    }
  });

  test('missing RPC is surfaced without a table-read fallback', () async {
    final requests = <http.Request>[];
    final access = await _access(
      handler: (request) async {
        requests.add(request);
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'manager'},
          ]);
        }
        return jsonResponse(request, {
          'code': 'PGRST202',
          'message': 'function not found',
        }, status: 404);
      },
    );
    try {
      await expectLater(
        SupabaseCodReceiptRepository(access: access).confirmReceipt(_command()),
        throwsA(
          isA<OperationalFailure>().having(
            (failure) => failure.code,
            'code',
            OperationalFailureCode.backendUnavailable,
          ),
        ),
      );
      expect(
        requests.where(
          (request) => request.url.path.endsWith('/cod_collections'),
        ),
        isEmpty,
      );
    } finally {
      await access.dispose();
      await access.client.dispose();
    }
  });

  test('rejects an account switch before accepting a late response', () async {
    final started = Completer<void>();
    final response = Completer<http.Response>();
    final access = await _access(
      handler: (request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'manager'},
          ]);
        }
        if (!started.isCompleted) started.complete();
        return response.future;
      },
    );
    try {
      final pending = SupabaseCodReceiptRepository(access: access)
          .confirmReceipt(_command());
      await started.future;
      await recoverFixtureSession(access.client, _otherManagerId);
      response.complete(
        jsonResponse(
          http.Request('POST', Uri.parse('https://test-fixture.invalid/rpc')),
          _receiptPayload(receivedBy: _managerId),
        ),
      );

      await expectLater(
        pending,
        throwsA(
          isA<OperationalFailure>().having(
            (failure) => failure.code,
            'code',
            OperationalFailureCode.sessionExpired,
          ),
        ),
      );
    } finally {
      if (!response.isCompleted) {
        response.completeError(StateError('test cleanup'));
      }
      await access.dispose();
      await access.client.dispose();
    }
  });

  test('same request id can safely replay the server result', () async {
    var rpcCalls = 0;
    final access = await _access(
      handler: (request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'manager'},
          ]);
        }
        rpcCalls++;
        return jsonResponse(request, _receiptPayload());
      },
    );
    try {
      final repository = SupabaseCodReceiptRepository(access: access);
      final first = await repository.confirmReceipt(_command());
      final replay = await repository.confirmReceipt(_command());
      expect(replay, first);
      expect(rpcCalls, 2);
    } finally {
      await access.dispose();
      await access.client.dispose();
    }
  });

  test(
    'a malformed acknowledgement remains retryable with the same request id',
    () async {
      var rpcCalls = 0;
      final bodies = <Map<String, dynamic>>[];
      final access = await _access(
        handler: (request) async {
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'role': 'manager'},
            ]);
          }
          rpcCalls++;
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (rpcCalls == 1) {
            // The transaction may already have committed; the worker must
            // retry with this same command/request ID, never mint a new one.
            return jsonResponse(request, {
              'order_id': _orderId,
              'status': 'received',
            });
          }
          return jsonResponse(request, _receiptPayload());
        },
      );
      try {
        final repository = SupabaseCodReceiptRepository(access: access);
        await expectLater(
          repository.confirmReceipt(_command()),
          throwsA(
            isA<CodReceiptAcknowledgementFailure>().having(
              (failure) => failure.code,
              'code',
              OperationalFailureCode.invalidData,
            ),
          ),
        );

        final replay = await repository.confirmReceipt(_command());
        expect(replay.status, CodReceiptStatus.received);
        expect(bodies, hasLength(2));
        expect(bodies[0]['p_request_id'], _requestId);
        expect(bodies[1]['p_request_id'], _requestId);
      } finally {
        await access.dispose();
        await access.client.dispose();
      }
    },
  );
}

CodReceiptCommand _command() => const CodReceiptCommand(
  orderId: _orderId,
  receivedAmountVnd: 550000,
  requestId: _requestId,
);

Map<String, dynamic> _receiptPayload({String receivedBy = _managerId}) {
  return {
    'order_id': _orderId,
    'status': 'received',
    'received_amount_vnd': 550000,
    'received_by': receivedBy,
    'received_at': '2026-10-25T08:00:00.123456Z',
    'handed_over_at': '2026-10-25T08:00:00.123456Z',
    'event_id': _eventId,
    'notification_id': _notificationId,
  };
}

Future<OperationalReadAccess> _access({
  required Future<http.Response> Function(http.Request) handler,
}) async {
  final client = await fixtureClient(handler, userId: _managerId);
  final access = OperationalReadAccess(client);
  await Future<void>.delayed(Duration.zero);
  return access;
}
