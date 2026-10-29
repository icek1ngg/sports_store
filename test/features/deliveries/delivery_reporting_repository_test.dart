import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/data/repositories/supabase_delivery_reporting_repository.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_reporting.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';

import '../support/operational_supabase_fixture.dart';

const _taskId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _orderId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const _requestId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const _eventId = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
const _firstItemId = '11111111-1111-4111-8111-111111111111';
const _secondItemId = '22222222-2222-4222-8222-222222222222';

final _handoverCommand = ReportingCommand.handover(
  taskId: _taskId,
  requestId: _requestId,
  items: const [
    ReportItem(
      orderItemId: _firstItemId,
      productName: 'Bóng đá',
      variantLabel: 'Số 5',
      quantity: 2,
    ),
    ReportItem(
      orderItemId: _secondItemId,
      productName: 'Áo thể thao',
      quantity: 1,
    ),
  ],
);

const _incidentCommand = ReportingCommand.incident(
  taskId: _taskId,
  requestId: _requestId,
  incidentKind: ReportingIncidentKind.damaged,
  reason: '  rách bao bì  ',
);

Map<String, dynamic> _context({Map<String, dynamic>? change}) => {
  'task_id': _taskId,
  'task_status': 'failed',
  'order_status': 'awaiting_store_return',
  'can_handover': true,
  'can_incident': true,
  'handover_reported': false,
  'handover_block_reason': null,
  'incident_block_reason': null,
  'items': [
    {
      'order_item_id': _firstItemId,
      'product_name': 'Bóng đá',
      'variant_label': 'Số 5',
      'quantity': 2,
    },
    {
      'order_item_id': _secondItemId,
      'product_name': 'Áo thể thao',
      'variant_label': null,
      'quantity': 1,
    },
  ],
}..addAll(change ?? const {});

Map<String, dynamic> _ack({
  required ReportingCommand command,
  String? taskStatus,
  String? orderStatus,
}) => {
  'task_id': _taskId,
  'order_id': _orderId,
  'operation': command.operation.rpcName,
  'request_id': _requestId,
  'event_id': _eventId,
  'reported_at': '2026-10-27T08:00:00.123456Z',
  'task_status': taskStatus ?? (command.isHandover ? 'failed' : 'in_transit'),
  'order_status':
      orderStatus ??
      (command.isHandover ? 'awaiting_store_return' : 'delivering'),
};

Future<OperationalReadAccess> _access({
  required Future<dynamic> Function(dynamic request) handler,
  Duration readTimeout = const Duration(seconds: 2),
  String userId = shipperA,
}) async {
  final client = await fixtureClient((request) async {
    final response = await handler(request);
    return response;
  }, userId: userId);
  final access = OperationalReadAccess(client, readTimeout: readTimeout);
  await Future<void>.delayed(Duration.zero);
  return access;
}

Future<void> _dispose(OperationalReadAccess access) async {
  final client = access.client;
  await access.dispose();
  await client.dispose();
}

SupabaseDeliveryReportingRepository _repository(OperationalReadAccess access) =>
    SupabaseDeliveryReportingRepository(access: access);

void main() {
  test(
    'context uses only the secure RPC and maps the exact projection',
    () async {
      final requests = <dynamic>[];
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
            endsWith('/rpc/get_my_delivery_reporting_context'),
          );
          expect(jsonDecode(request.body), {'p_task_id': _taskId});
          return jsonResponse(request, _context());
        },
      );
      try {
        final context = await _repository(access).getContext(_taskId);
        expect(context.taskId, _taskId);
        expect(context.kind, DeliveryTaskKind.outbound);
        expect(context.status, DeliveryTaskStatus.failed);
        expect(context.orderStatus, 'awaiting_store_return');
        expect(context.canHandover, isTrue);
        expect(context.items, hasLength(2));
        expect(context.items.first.variantLabel, 'Số 5');
        expect(
          requests.where(
            (request) => request.url.path.contains('/delivery_tasks'),
          ),
          isEmpty,
        );
      } finally {
        await _dispose(access);
      }
    },
  );

  test('context accepts a null order status without faking one', () async {
    final access = await _access(
      handler: (request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        return jsonResponse(
          request,
          _context(
            change: {
              'task_status': 'assigned',
              'order_status': null,
              'can_handover': false,
              'can_incident': false,
              'items': [],
              'incident_block_reason': 'CUSTODY_UNRESOLVED',
            },
          ),
        );
      },
    );
    try {
      final context = await _repository(access).getContext(_taskId);
      expect(context.orderStatus, isNull);
      expect(context.canHandover, isFalse);
      expect(context.items, isEmpty);
      expect(context.incidentBlockReason, 'CUSTODY_UNRESOLVED');
    } finally {
      await _dispose(access);
    }
  });

  test('context rejects extra fields and unknown block reasons', () async {
    for (final change in [
      {'private_price': 100000},
      {'handover_block_reason': 'private backend detail'},
    ]) {
      final access = await _access(
        handler: (request) async {
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'role': 'shipper'},
            ]);
          }
          return jsonResponse(request, _context(change: change));
        },
      );
      try {
        await expectLater(
          _repository(access).getContext(_taskId),
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
    }
  });

  test(
    'handover sends immutable item IDs/quantities only and validates ACK',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final access = await _access(
        handler: (request) async {
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'role': 'shipper'},
            ]);
          }
          expect(request.url.path, endsWith('/rpc/report_store_handover'));
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return jsonResponse(request, _ack(command: _handoverCommand));
        },
      );
      try {
        final ack = await _repository(access).execute(_handoverCommand);
        expect(ack.taskId, _taskId);
        expect(ack.operation, 'report_store_handover');
        expect(ack.operationKind, ReportingOperation.handover);
        expect(bodies, [
          {
            'p_task_id': _taskId,
            'p_request_id': _requestId,
            'p_items': [
              {'order_item_id': _firstItemId, 'quantity': 2},
              {'order_item_id': _secondItemId, 'quantity': 1},
            ],
          },
        ]);
      } finally {
        await _dispose(access);
      }
    },
  );

  test('incident trims reason and sends kind/reason only', () async {
    final bodies = <Map<String, dynamic>>[];
    final access = await _access(
      handler: (request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        expect(request.url.path, endsWith('/rpc/report_delivery_incident'));
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return jsonResponse(request, _ack(command: _incidentCommand));
      },
    );
    try {
      await _repository(access).execute(_incidentCommand);
      expect(bodies.single, {
        'p_task_id': _taskId,
        'p_request_id': _requestId,
        'p_incident_kind': 'damaged',
        'p_reason': 'rách bao bì',
      });
    } finally {
      await _dispose(access);
    }
  });

  test('invalid command is rejected before profile or RPC access', () async {
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
        _repository(access).execute(
          const ReportingCommand.incident(
            taskId: 'not-a-uuid',
            requestId: _requestId,
            incidentKind: ReportingIncidentKind.other,
            reason: 'reason',
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

  test(
    'handover quantity above the server integer bound is rejected locally',
    () async {
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
        final command = ReportingCommand.handover(
          taskId: _taskId,
          requestId: _requestId,
          items: const [
            ReportItem(
              orderItemId: _firstItemId,
              productName: 'Bóng đá',
              quantity: maxReportingItemQuantity + 1,
            ),
          ],
        );
        await expectLater(
          _repository(access).execute(command),
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
    },
  );

  test('role denial occurs before a report RPC', () async {
    var rpcCalled = false;
    final access = await _access(
      handler: (request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'manager'},
          ]);
        }
        rpcCalled = true;
        return jsonResponse(request, _ack(command: _incidentCommand));
      },
    );
    try {
      await expectLater(
        _repository(access).execute(_incidentCommand),
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

  for (final entry in <String, OutboundBusinessFailureCode>{
    'STATE_CONFLICT': OutboundBusinessFailureCode.stateConflict,
    'IDEMPOTENCY_CONFLICT': OutboundBusinessFailureCode.idempotencyConflict,
    'CUSTODY_UNRESOLVED': OutboundBusinessFailureCode.custodyUnresolved,
    'ITEMS_MISMATCH': OutboundBusinessFailureCode.itemsMismatch,
  }.entries) {
    test('maps ${entry.key} to a safe business failure', () async {
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
          _repository(access).execute(_incidentCommand),
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
    });
  }

  test(
    'unsupported kind is invalid data and unknown marker is unexpected',
    () async {
      for (final marker in ['UNSUPPORTED_TASK_KIND', 'private detail']) {
        final access = await _access(
          handler: (request) async {
            if (request.url.path.endsWith('/profiles')) {
              return jsonResponse(request, [
                {'role': 'shipper'},
              ]);
            }
            return jsonResponse(request, {
              'code': 'PT409',
              'message': marker,
            }, status: 409);
          },
        );
        try {
          await expectLater(
            _repository(access).execute(_incidentCommand),
            throwsA(
              isA<OperationalFailure>().having(
                (failure) => failure.code,
                'code',
                marker == 'UNSUPPORTED_TASK_KIND'
                    ? OperationalFailureCode.invalidData
                    : OperationalFailureCode.unexpected,
              ),
            ),
          );
        } finally {
          await _dispose(access);
        }
      }
    },
  );

  test('missing RPC has no table-read fallback', () async {
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
        _repository(access).getContext(_taskId),
        throwsA(
          isA<OperationalFailure>().having(
            (failure) => failure.code,
            'code',
            OperationalFailureCode.backendUnavailable,
          ),
        ),
      );
      expect(paths.where((path) => path.contains('/delivery_tasks')), isEmpty);
    } finally {
      await _dispose(access);
    }
  });

  test(
    'malformed ACK preserves the same request key for explicit retry',
    () async {
      var calls = 0;
      final bodies = <Map<String, dynamic>>[];
      final access = await _access(
        handler: (request) async {
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'role': 'shipper'},
            ]);
          }
          calls++;
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return jsonResponse(
            request,
            calls == 1
                ? {'task_id': _taskId, 'request_id': _requestId}
                : _ack(command: _incidentCommand),
          );
        },
      );
      try {
        await expectLater(
          _repository(access).execute(_incidentCommand),
          throwsA(isA<OutboundAcknowledgementFailure>()),
        );
        await _repository(access).execute(_incidentCommand);
        expect(bodies, hasLength(2));
        expect(bodies[0]['p_request_id'], _requestId);
        expect(bodies[1]['p_request_id'], _requestId);
      } finally {
        await _dispose(access);
      }
    },
  );

  test(
    'same-user refresh after dispatch preserves uncertain command semantics',
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
          return jsonResponse(request, _ack(command: _incidentCommand));
        },
      );
      try {
        final pending = _repository(access).execute(_incidentCommand);
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
}
