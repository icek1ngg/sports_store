import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/data/repositories/supabase_return_pickup_repository.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_failure_command.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';
import 'package:sports_store/features/deliveries/domain/models/return_pickup_command.dart';
import 'package:sports_store/features/deliveries/domain/repositories/return_pickup_repository.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/return_pickup_providers.dart';

import '../support/operational_supabase_fixture.dart';

const _taskId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _returnRequestId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const _orderId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const _requestId = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
const _eventId = '99999999-9999-4999-8999-999999999999';
const _itemA = '11111111-1111-4111-8111-111111111111';
const _itemB = '22222222-2222-4222-8222-222222222222';

ReturnPickupCommand _collectCommand({
  String taskId = _taskId,
  String requestId = _requestId,
  String returnRequestId = _returnRequestId,
  String orderId = _orderId,
  Iterable<ReturnPickupItem> items = const [
    ReturnPickupItem(returnItemId: _itemA, quantity: 1),
    ReturnPickupItem(returnItemId: _itemB, quantity: 2),
  ],
}) => ReturnPickupCommand.collect(
  taskId: taskId,
  requestId: requestId,
  returnRequestId: returnRequestId,
  orderId: orderId,
  items: items,
);

ReturnPickupCommand _failCommand({
  String taskId = _taskId,
  String requestId = _requestId,
  String returnRequestId = _returnRequestId,
  String orderId = _orderId,
  OutboundFailureReason reason = OutboundFailureReason.unreachable,
  String? description,
}) => ReturnPickupCommand.fail(
  taskId: taskId,
  requestId: requestId,
  returnRequestId: returnRequestId,
  orderId: orderId,
  reason: reason,
  description: description,
);

ReturnPickupCommand _handoverCommand({
  String taskId = _taskId,
  String requestId = _requestId,
  String returnRequestId = _returnRequestId,
  String orderId = _orderId,
  Iterable<ReturnPickupItem> items = const [
    ReturnPickupItem(returnItemId: _itemA, quantity: 1),
    ReturnPickupItem(returnItemId: _itemB, quantity: 2),
  ],
}) => ReturnPickupCommand.handover(
  taskId: taskId,
  requestId: requestId,
  returnRequestId: returnRequestId,
  orderId: orderId,
  items: items,
);

Map<String, dynamic> _collectAck({
  String taskId = _taskId,
  String returnRequestId = _returnRequestId,
  String orderId = _orderId,
  String requestId = _requestId,
  String? timestamp = '2026-10-28T08:00:00.123456Z',
}) => {
  'task_id': taskId,
  'return_request_id': returnRequestId,
  'order_id': orderId,
  'operation': 'collect_return_items',
  'task_status': 'in_transit',
  'return_status': 'returning_to_store',
  'accepted_at': timestamp,
  'started_at': timestamp,
  'occurred_at': timestamp,
  'event_id': _eventId,
  'request_id': requestId,
};

Map<String, dynamic> _failAck({
  String taskId = _taskId,
  String returnRequestId = _returnRequestId,
  String orderId = _orderId,
  String requestId = _requestId,
  String reason = 'unreachable',
  Object? description,
  String timestamp = '2026-10-28T08:00:00.123456Z',
}) => {
  'task_id': taskId,
  'return_request_id': returnRequestId,
  'order_id': orderId,
  'operation': 'fail_return_pickup_task',
  'task_status': 'failed',
  'return_status': 'awaiting_return_pickup',
  'reason_code': reason,
  'description': description,
  'failed_at': timestamp,
  'occurred_at': timestamp,
  'event_id': _eventId,
  'request_id': requestId,
};

Map<String, dynamic> _handoverAck({
  String taskId = _taskId,
  String returnRequestId = _returnRequestId,
  String orderId = _orderId,
  String requestId = _requestId,
  String timestamp = '2026-10-28T08:00:00.123456Z',
}) => {
  'task_id': taskId,
  'return_request_id': returnRequestId,
  'order_id': orderId,
  'operation': 'report_return_pickup_handover',
  'task_status': 'in_transit',
  'return_status': 'returning_to_store',
  'reported_at': timestamp,
  'occurred_at': timestamp,
  'event_id': _eventId,
  'request_id': requestId,
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
  test('collect sends the exact sorted approved-plan payload', () async {
    final bodies = <Map<String, dynamic>>[];
    final access = await _access(
      handler: (request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        expect(request.url.path, endsWith('/rpc/collect_return_items'));
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return jsonResponse(request, _collectAck());
      },
    );
    try {
      final ack = await SupabaseReturnPickupRepository(access: access)
          .execute(_collectCommand());
      expect(ack.taskId, _taskId);
      expect(ack.returnRequestId, _returnRequestId);
      expect(ack.orderId, _orderId);
      expect(ack.operation, ReturnPickupOperation.collect);
      expect(ack.taskStatus, 'in_transit');
      expect(ack.returnStatus, 'returning_to_store');
      expect(bodies, [
        {
          'p_task_id': _taskId,
          'p_request_id': _requestId,
          'p_items': [
            {'return_item_id': _itemA, 'quantity': 1},
            {'return_item_id': _itemB, 'quantity': 2},
          ],
        },
      ]);
    } finally {
      await _dispose(access);
    }
  });

  test('fail trims description and accepts nullable description', () async {
    final bodies = <Map<String, dynamic>>[];
    final command = _failCommand(
      reason: OutboundFailureReason.other,
      description: '  customer unavailable  ',
    );
    final access = await _access(
      handler: (request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return jsonResponse(
          request,
          _failAck(reason: 'other', description: 'customer unavailable'),
        );
      },
    );
    try {
      final ack = await SupabaseReturnPickupRepository(access: access)
          .execute(command);
      expect(ack.operation, ReturnPickupOperation.fail);
      expect(ack.reason, OutboundFailureReason.other);
      expect(ack.description, 'customer unavailable');
      expect(bodies.single, {
        'p_task_id': _taskId,
        'p_request_id': _requestId,
        'p_reason_code': 'other',
        'p_description': 'customer unavailable',
      });
    } finally {
      await _dispose(access);
    }

    final nullableAccess = await _access(
      handler: (request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        return jsonResponse(request, _failAck());
      },
    );
    try {
      final ack = await SupabaseReturnPickupRepository(access: nullableAccess)
          .execute(_failCommand());
      expect(ack.description, isNull);
    } finally {
      await _dispose(nullableAccess);
    }
  });

  test(
    'commands freeze item lists and reject non-canonical collection input',
    () {
      final mutable = <ReturnPickupItem>[
        const ReturnPickupItem(returnItemId: _itemA, quantity: 1),
      ];
      final command = _collectCommand(items: mutable);
      mutable.add(const ReturnPickupItem(returnItemId: _itemB, quantity: 2));
      expect(command.items, hasLength(1));
      expect(
        _collectCommand(
          items: const [
            ReturnPickupItem(returnItemId: _itemB, quantity: 1),
            ReturnPickupItem(returnItemId: _itemA, quantity: 1),
          ],
        ).isValid,
        isFalse,
      );
    },
  );

  test('invalid commands fail before profile or RPC access', () async {
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
        SupabaseReturnPickupRepository(access: access).execute(
          _collectCommand(
            items: const [ReturnPickupItem(returnItemId: _itemA, quantity: 0)],
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

      await expectLater(
        SupabaseReturnPickupRepository(access: access).execute(
          _failCommand(reason: OutboundFailureReason.other, description: '  '),
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

  test('role denial occurs before pickup RPC', () async {
    var rpcCalled = false;
    final access = await _access(
      handler: (request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'manager'},
          ]);
        }
        rpcCalled = true;
        return jsonResponse(request, _collectAck());
      },
    );
    try {
      await expectLater(
        SupabaseReturnPickupRepository(access: access)
            .execute(_collectCommand()),
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
    'documented pickup business markers map to safe typed failures',
    () async {
      const businessMarkers = <String, Type>{
        'STATE_CONFLICT': OutboundBusinessFailure,
        'APPROVAL_UNRESOLVED': OutboundBusinessFailure,
        'STALE_ASSIGNMENT': OutboundCommandFailure,
        'ITEMS_MISMATCH': OutboundBusinessFailure,
        'CUSTODY_UNRESOLVED': OutboundBusinessFailure,
        'IDEMPOTENCY_CONFLICT': OutboundBusinessFailure,
        'INVALID_SHIPPER': OutboundCommandFailure,
        'TASK_CONFLICT': OutboundBusinessFailure,
      };
      for (final entry in businessMarkers.entries) {
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
            SupabaseReturnPickupRepository(access: access)
                .execute(_collectCommand()),
            throwsA(isA<OutboundCommandFailure>()),
          );
        } finally {
          await _dispose(access);
        }
      }
    },
  );

  for (final malformed in <String, Map<String, dynamic>>{
    'foreign task': _collectAck()..['task_id'] = _orderId,
    'foreign return request': _collectAck()..['return_request_id'] = _orderId,
    'foreign order': _collectAck()..['order_id'] = _taskId,
    'foreign request key': _collectAck()..['request_id'] = _orderId,
    'wrong operation': _collectAck()..['operation'] = 'fail_return_pickup_task',
    'wrong task status': _collectAck()..['task_status'] = 'assigned',
    'wrong return status': _collectAck()
      ..['return_status'] = 'awaiting_return_pickup',
    'missing nullable collection field': _collectAck()..remove('started_at'),
    'extra private field': _collectAck()..['customer_phone'] = 'secret',
    'invalid event UUID': _collectAck()..['event_id'] = 'not-a-uuid',
    'invalid timestamp': _collectAck()
      ..['occurred_at'] = '2026-02-30T08:00:00Z',
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
          SupabaseReturnPickupRepository(access: access)
              .execute(_collectCommand()),
          throwsA(isA<OutboundAcknowledgementFailure>()),
        );
      } finally {
        await _dispose(access);
      }
    });
  }

  test(
    'failure ACK requires a description key and matches nullable null',
    () async {
      final malformed = _failAck()..remove('description');
      final access = await _access(
        handler: (request) async {
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'role': 'shipper'},
            ]);
          }
          return jsonResponse(request, malformed);
        },
      );
      try {
        await expectLater(
          SupabaseReturnPickupRepository(access: access)
              .execute(_failCommand()),
          throwsA(isA<OutboundAcknowledgementFailure>()),
        );
      } finally {
        await _dispose(access);
      }
    },
  );

  test(
    'same-user refresh after dispatch keeps the uncertain request key',
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
          return jsonResponse(request, _collectAck());
        },
      );
      try {
        final pending = SupabaseReturnPickupRepository(access: access)
            .execute(_collectCommand());
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
        return jsonResponse(request, _collectAck());
      },
    );
    try {
      await expectLater(
        SupabaseReturnPickupRepository(access: access)
            .execute(_collectCommand()),
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
    'missing RPC maps to backend unavailable without table fallback',
    () async {
      final paths = <String>[];
      final access = await _access(
        handler: (request) async {
          paths.add(request.url.path);
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
          SupabaseReturnPickupRepository(access: access)
              .execute(_collectCommand()),
          throwsA(
            isA<OperationalFailure>().having(
              (failure) => failure.code,
              'code',
              OperationalFailureCode.backendUnavailable,
            ),
          ),
        );
        expect(
          paths.where((path) => path.contains('/delivery_tasks')),
          isEmpty,
        );
        expect(paths.where((path) => path.contains('/return_items')), isEmpty);
      } finally {
        await _dispose(access);
      }
    },
  );

  test('handover uses its own RPC and exact full-plan payload', () async {
    final bodies = <Map<String, dynamic>>[];
    final access = await _access(
      handler: (request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        expect(
          request.url.path,
          endsWith('/rpc/report_return_pickup_handover'),
        );
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return jsonResponse(request, _handoverAck());
      },
    );
    try {
      final command = _handoverCommand();
      final ack = await SupabaseReturnPickupRepository(access: access)
          .execute(command);
      expect(ack.operation, ReturnPickupOperation.handover);
      expect(ack.taskStatus, 'in_transit');
      expect(ack.returnStatus, 'returning_to_store');
      expect(ack.reportedAt, ack.occurredAt);
      expect(bodies, [
        {
          'p_task_id': _taskId,
          'p_request_id': _requestId,
          'p_items': [
            {'return_item_id': _itemA, 'quantity': 1},
            {'return_item_id': _itemB, 'quantity': 2},
          ],
        },
      ]);
    } finally {
      await _dispose(access);
    }
  });

  test('handover marker read is narrow and strict', () async {
    final paths = <String>[];
    final access = await _access(
      handler: (request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        expect(
          request.url.path,
          endsWith('/rpc/get_my_return_pickup_handover'),
        );
        expect(jsonDecode(request.body), {'p_task_id': _taskId});
        return jsonResponse(request, {
          'task_id': _taskId,
          'reported': true,
          'reported_at': '2026-10-28T08:00:00.123456Z',
        });
      },
    );
    try {
      final ReturnPickupRepository repository = SupabaseReturnPickupRepository(
        access: access,
      );
      final container = ProviderContainer(
        overrides: [
          returnPickupRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final marker = await container.read(returnPickupHandoverStatusProvider)(
        _taskId,
      );
      expect(await repository.getHandoverStatus(_taskId), marker);
      expect(marker.taskId, _taskId);
      expect(marker.reported, isTrue);
      expect(marker.reportedAt, isNotNull);
      expect(paths.where((path) => path.contains('/delivery_tasks')), isEmpty);
      expect(paths.where((path) => path.contains('/return_requests')), isEmpty);
    } finally {
      await _dispose(access);
    }
  });
}
