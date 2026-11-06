import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_dto.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_item_dto.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_query.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_failure_command.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/outbound_result_gate.dart';
import 'package:sports_store/features/deliveries/domain/models/return_pickup_command.dart';
import 'package:sports_store/features/deliveries/domain/repositories/delivery_repository.dart';
import 'package:sports_store/features/deliveries/domain/repositories/return_pickup_repository.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_task_detail_view_model.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_providers.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/return_pickup_providers.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/return_pickup_view_model.dart';
import 'package:sports_store/features/deliveries/presentation/widgets/return_pickup_action.dart';

const _taskId = '11111111-1111-4111-8111-111111111111';
const _orderId = '22222222-2222-4222-8222-222222222222';
const _returnId = '33333333-3333-4333-8333-333333333333';
const _itemA = '44444444-4444-4444-8444-444444444444';
const _itemB = '55555555-5555-4555-8555-555555555555';
const _requestId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

class _FixtureDetailViewModel extends DeliveryTaskDetailViewModel {
  _FixtureDetailViewModel(super.taskId, this.value);
  final DeliveryTaskDetails value;
  @override
  AsyncValue<DeliveryTaskDetails> build() => AsyncData(value);
}

class _Repo implements ReturnPickupRepository {
  final commands = <ReturnPickupCommand>[];
  Future<ReturnPickupAck> Function(ReturnPickupCommand command)? handler;
  @override
  Future<ReturnPickupAck> execute(ReturnPickupCommand command) async {
    commands.add(command);
    return handler?.call(command) ?? _ack(command);
  }
}

class _DeliveryRepository implements DeliveryRepository {
  @override
  Future<DeliveryTaskDetails> getTaskDetails(String taskId) =>
      Future<DeliveryTaskDetails>.error(UnimplementedError());
  @override
  Future<List<DeliveryTaskSnapshot>> listTasks() =>
      Future<List<DeliveryTaskSnapshot>>.value(const []);
  @override
  Future<DeliveryTaskPage> queryTasks(DeliveryTaskQuery query) =>
      Future<DeliveryTaskPage>.error(UnimplementedError());
  @override
  Future<DeliveryTaskSnapshot> getTask(String taskId) =>
      Future<DeliveryTaskSnapshot>.error(UnimplementedError());
}

DeliveryTaskDetails _pickupDetails({
  String status = 'assigned',
  String scope = 'current',
  String? acceptedAt,
  String? startedAt,
  String? completedAt,
  int collectedA = 0,
  int collectedB = 0,
  bool second = true,
}) {
  final task = DeliveryTaskDto.fromJson({
    'task_id': _taskId,
    'kind': 'return_pickup',
    'status': status,
    'attempt_number': 1,
    'snapshot_scope': scope,
    'order_id': scope == 'restricted' ? null : _orderId,
    'return_request_id': scope == 'restricted' ? null : _returnId,
    'amount_to_collect_vnd': scope == 'restricted' ? null : 0,
    'destination_name': scope == 'restricted' ? null : 'Khách trả hàng',
    'destination_phone': scope == 'restricted' ? null : '0900000000',
    'destination_address': scope == 'restricted' ? null : 'Hà Nội',
    'destination_latitude': scope == 'restricted' ? null : '21.028511',
    'destination_longitude': scope == 'restricted' ? null : '105.804817',
    'assigned_at': scope == 'restricted' ? null : '2026-10-28T01:00:00Z',
    'accepted_at': acceptedAt,
    'started_at': startedAt,
    'completed_at': completedAt,
    'item_source': scope == 'restricted' ? 'unavailable' : 'return_plan',
  }).toDomain();
  final rows = <DeliveryTaskItem>[];
  if (scope != 'restricted') {
    rows.add(
      DeliveryTaskItemDto.fromJson({
        'item_id': _itemA,
        'item_source': 'return_plan',
        'product_name': 'Bóng đá lỗi',
        'variant_label': null,
        'attributes': null,
        'quantity': 2,
        'quantity_collected': collectedA,
        'unit_price_vnd': null,
        'line_total_vnd': null,
      }).toDomain(),
    );
  }
  if (second && scope != 'restricted') {
    rows.add(
      DeliveryTaskItemDto.fromJson({
        'item_id': _itemB,
        'item_source': 'return_plan',
        'product_name': 'Áo thể thao lỗi',
        'variant_label': null,
        'attributes': null,
        'quantity': 1,
        'quantity_collected': collectedB,
        'unit_price_vnd': null,
        'line_total_vnd': null,
      }).toDomain(),
    );
  }
  return DeliveryTaskDetails(task: task, items: rows);
}

DeliveryTaskDetails _restrictedFailed() => _pickupDetails(
  status: 'failed',
  scope: 'restricted',
  completedAt: '2026-10-28T02:00:00Z',
  second: false,
);

ReturnPickupAck _ack(ReturnPickupCommand command) {
  final now = DateTime.utc(2026, 10, 28, 2);
  return ReturnPickupAck(
    taskId: command.taskId,
    returnRequestId: command.returnRequestId,
    orderId: command.orderId,
    operation: command.operation,
    taskStatus: command.isCollect ? 'in_transit' : 'failed',
    returnStatus: command.isCollect
        ? 'returning_to_store'
        : 'awaiting_return_pickup',
    eventId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    requestId: command.requestId,
    occurredAt: now,
    acceptedAt: command.isCollect ? now : null,
    startedAt: command.isCollect ? now : null,
    failedAt: command.isFailure ? now : null,
    reason: command.reason,
    description: command.trimmedDescription,
  );
}

ReturnPickupAck _handoverAck(ReturnPickupCommand command) {
  final now = DateTime.utc(2026, 10, 28, 2);
  return ReturnPickupAck(
    taskId: command.taskId,
    returnRequestId: command.returnRequestId,
    orderId: command.orderId,
    operation: command.operation,
    taskStatus: 'in_transit',
    returnStatus: 'returning_to_store',
    eventId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    requestId: command.requestId,
    occurredAt: now,
    reportedAt: now,
  );
}

OperationalSession _session(String user) =>
    OperationalSession(userId: user, generation: 1);

Future<void> _settle(ProviderContainer container, bool Function() done) async {
  for (var i = 0; i < 200; i++) {
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    if (done()) return;
  }
  fail('provider did not settle');
}

typedef _Harness = ({
  ProviderContainer container,
  StreamController<OperationalSession> sessions,
  _Repo repo,
  List<DeliveryTaskDetails> reads,
  List<void> listRefreshes,
});

_Harness _harness({
  required DeliveryTaskDetails initial,
  required Future<DeliveryTaskDetails> Function() reload,
  Future<ReturnPickupHandoverStatus> Function(String)? handoverStatus,
}) {
  final sessions = StreamController<OperationalSession>.broadcast();
  final repo = _Repo();
  var current = initial;
  final reads = <DeliveryTaskDetails>[];
  final listRefreshes = <void>[];
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      operationalSessionProvider.overrideWith((ref) => sessions.stream),
      deliveryRepositoryProvider.overrideWithValue(_DeliveryRepository()),
      deliveryTaskDetailViewModelProvider(_taskId)
          .overrideWith(() => _FixtureDetailViewModel(_taskId, current)),
      returnPickupRepositoryProvider.overrideWithValue(repo),
      returnPickupRequestIdProvider.overrideWithValue(() => _requestId),
      returnPickupDetailsReloadProvider.overrideWithValue((_) async {
        final value = await reload();
        current = value;
        reads.add(value);
        return value;
      }),
      returnPickupHandoverStatusProvider.overrideWithValue(
        handoverStatus ??
            (_) => Future<ReturnPickupHandoverStatus>.error(
              UnsupportedError('marker unavailable in this fixture'),
            ),
      ),
      returnPickupTaskListReloadProvider.overrideWithValue(() async {
        listRefreshes.add(null);
      }),
    ],
  );
  return (
    container: container,
    sessions: sessions,
    repo: repo,
    reads: reads,
    listRefreshes: listRefreshes,
  );
}

Future<ReturnPickupViewModel> _ready(_Harness h) async {
  h.container.listen<ReturnPickupState>(
    returnPickupViewModelProvider(_taskId),
    (_, _) {},
    fireImmediately: true,
  );
  h.sessions.add(_session('shipper-a'));
  await _settle(h.container, () {
    return h.container.read(returnPickupViewModelProvider(_taskId)).canCollect;
  });
  return h.container.read(returnPickupViewModelProvider(_taskId).notifier);
}

Future<ReturnPickupViewModel> _readyForHandover(_Harness h) async {
  h.container.listen<ReturnPickupState>(
    returnPickupViewModelProvider(_taskId),
    (_, _) {},
    fireImmediately: true,
  );
  h.sessions.add(_session('shipper-a'));
  await _settle(h.container, () {
    final state = h.container.read(returnPickupViewModelProvider(_taskId));
    return state.handoverStatus.hasValue || state.handoverStatus.hasError;
  });
  return h.container.read(returnPickupViewModelProvider(_taskId).notifier);
}

void main() {
  test('only a complete assigned return plan permits mutations', () {
    final assigned = _pickupDetails();
    for (final status in ['accepted', 'in_transit']) {
      expect(
        ReturnPickupViewModel.canMutateDetails(_pickupDetails(status: status)),
        isFalse,
      );
    }
    expect(
      ReturnPickupViewModel.canMutateDetails(_restrictedFailed()),
      isFalse,
    );
    expect(
      ReturnPickupViewModel.canMutateDetails(
        DeliveryTaskDetails(
          task: assigned.task,
          items: [
            DeliveryTaskItem(
              itemId: _itemA,
              itemSource: DeliveryItemSource.orderSnapshot,
              productName: 'Wrong source',
              quantity: 2,
              quantityCollected: 0,
            ),
          ],
        ),
      ),
      isFalse,
    );
  });
  for (final refresh in [false, true]) {
    test(
      'uncertain ACK retains exact envelope, token refresh=$refresh',
      () async {
        final h = _harness(
          initial: _pickupDetails(),
          reload: () async => _pickupDetails(
            status: 'in_transit',
            acceptedAt: '2026-10-28T02:00:00Z',
            startedAt: '2026-10-28T02:00:00Z',
            collectedA: 2,
            collectedB: 1,
          ),
        );
        addTearDown(() async {
          h.container.dispose();
          await h.sessions.close();
        });
        final vm = await _ready(h);
        h.repo.handler = (_) async =>
            throw const OutboundAcknowledgementFailure();
        await vm.submitCollect(
          expectedTask: vm.state.details.requireValue.task,
          expectedItems: vm.state.details.requireValue.items,
          sessionRevision: vm.sessionRevisionForConfirmation,
        );
        final pending = vm.state.pendingCommand;
        expect(pending, isNotNull);
        if (refresh) {
          h.sessions.add(
            const OperationalSession(userId: 'shipper-a', generation: 2),
          );
          await _settle(h.container, () => vm.state.details.isLoading);
        }
        h.repo.handler = (command) async => _ack(command);
        await vm.retry();
        expect(h.repo.commands, hasLength(2));
        expect(identical(h.repo.commands[0], h.repo.commands[1]), isTrue);
        expect(vm.state.confirmed, isTrue);
        expect(h.container.read(outboundResultGateProvider(_taskId)), isNull);
      },
    );
  }
  test('a partial authoritative item plan never confirms collection', () async {
    final h = _harness(
      initial: _pickupDetails(),
      reload: () async => _pickupDetails(
        status: 'in_transit',
        acceptedAt: '2026-10-28T02:00:00Z',
        startedAt: '2026-10-28T02:00:00Z',
        collectedA: 1,
        collectedB: 1,
      ),
    );
    addTearDown(() async {
      h.container.dispose();
      await h.sessions.close();
    });
    final vm = await _ready(h);
    await vm.submitCollect(
      expectedTask: vm.state.details.requireValue.task,
      expectedItems: vm.state.details.requireValue.items,
      sessionRevision: vm.sessionRevisionForConfirmation,
    );
    expect(vm.state.confirmed, isFalse);
    expect(vm.state.requiresReadRetry, isTrue);
    expect(h.listRefreshes, isEmpty);
    expect(
      vm.state.details.requireValue.task.status,
      DeliveryTaskStatus.assigned,
    );
    expect(h.repo.commands, hasLength(1));
  });
  test('assigned pickup is exact-plan only and refreshes detail/list after collect', () async {
    final h = _harness(
      initial: _pickupDetails(),
      reload: () async => _pickupDetails(
        status: 'in_transit',
        acceptedAt: '2026-10-28T02:00:00Z',
        startedAt: '2026-10-28T02:00:00Z',
        collectedA: 2,
        collectedB: 1,
      ),
    );
    addTearDown(() async {
      h.container.dispose();
      await h.sessions.close();
    });
    final vm = await _ready(h);
    expect(vm.state.canCollect, isTrue);
    expect(vm.state.canFail, isTrue);
    await vm.submitCollect(
      expectedTask: vm.state.details.requireValue.task,
      expectedItems: vm.state.details.requireValue.items,
      sessionRevision: vm.sessionRevisionForConfirmation,
    );
    expect(h.repo.commands.single.items.map((e) => e.quantity), [2, 1]);
    expect(h.reads, hasLength(1));
    expect(h.listRefreshes, hasLength(1));
    expect(
      h.container.read(returnPickupViewModelProvider(_taskId)).confirmed,
      isTrue,
    );
  });

  test(
    'collect confirmation releases the flow into one full-plan handover',
    () async {
      var reported = false;
      final h = _harness(
        initial: _pickupDetails(),
        reload: () async => _pickupDetails(
          status: 'in_transit',
          acceptedAt: '2026-10-28T02:00:00Z',
          startedAt: '2026-10-28T02:00:00Z',
          collectedA: 2,
          collectedB: 1,
        ),
        handoverStatus: (_) async => ReturnPickupHandoverStatus(
          taskId: _taskId,
          reported: reported,
          reportedAt: reported ? DateTime.utc(2026, 10, 28, 3) : null,
        ),
      );
      h.repo.handler = (command) async {
        if (command.isHandover) {
          reported = true;
          return _handoverAck(command);
        }
        return _ack(command);
      };
      addTearDown(() async {
        h.container.dispose();
        await h.sessions.close();
      });
      final vm = await _ready(h);
      await vm.submitCollect(
        expectedTask: vm.state.details.requireValue.task,
        expectedItems: vm.state.details.requireValue.items,
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      expect(vm.state.confirmedOperation, ReturnPickupOperation.collect);
      await _settle(h.container, () => vm.state.canReportStoreHandover);
      expect(vm.state.handoverReported, isFalse);

      await vm.submitHandover(
        expectedTask: vm.state.details.requireValue.task,
        expectedItems: vm.state.details.requireValue.items,
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      expect(h.repo.commands.map((command) => command.operation), [
        ReturnPickupOperation.collect,
        ReturnPickupOperation.handover,
      ]);
      expect(vm.state.confirmedOperation, ReturnPickupOperation.handover);
      expect(vm.state.handoverReported, isTrue);
      expect(
        vm.state.details.requireValue.task.status,
        DeliveryTaskStatus.inTransit,
      );
      expect(vm.state.canReportStoreHandover, isFalse);
    },
  );

  test(
    'late handover marker response cannot restore a previous account',
    () async {
      final firstReadStarted = Completer<void>();
      final firstRead = Completer<ReturnPickupHandoverStatus>();
      var markerCalls = 0;
      final inTransit = _pickupDetails(
        status: 'in_transit',
        acceptedAt: '2026-10-28T02:00:00Z',
        startedAt: '2026-10-28T02:00:00Z',
        collectedA: 2,
        collectedB: 1,
      );
      final h = _harness(
        initial: inTransit,
        reload: () async => inTransit,
        handoverStatus: (_) {
          markerCalls++;
          if (markerCalls == 1) {
            firstReadStarted.complete();
            return firstRead.future;
          }
          return Future<ReturnPickupHandoverStatus>.value(
            const ReturnPickupHandoverStatus(taskId: _taskId, reported: false),
          );
        },
      );
      addTearDown(() async {
        h.container.dispose();
        await h.sessions.close();
      });
      final sub = h.container.listen<ReturnPickupState>(
        returnPickupViewModelProvider(_taskId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      h.sessions.add(_session('shipper-a'));
      await firstReadStarted.future;
      h.sessions.add(_session('shipper-b'));
      await _settle(h.container, () => markerCalls >= 2);
      firstRead.complete(
        const ReturnPickupHandoverStatus(
          taskId: _taskId,
          reported: true,
          reportedAt: null,
        ),
      );
      await _settle(
        h.container,
        () => h.container
            .read(returnPickupViewModelProvider(_taskId))
            .handoverStatus
            .hasValue,
      );
      final state = h.container.read(returnPickupViewModelProvider(_taskId));
      expect(state.handoverReported, isFalse);
      expect(state.canReportStoreHandover, isTrue);
      expect(h.repo.commands, isEmpty);
    },
  );

  test(
    'marker read retry never writes a handover while marker is unresolved',
    () async {
      var markerCalls = 0;
      final inTransit = _pickupDetails(
        status: 'in_transit',
        acceptedAt: '2026-10-28T02:00:00Z',
        startedAt: '2026-10-28T02:00:00Z',
        collectedA: 2,
        collectedB: 1,
      );
      final h = _harness(
        initial: inTransit,
        reload: () async => inTransit,
        handoverStatus: (_) {
          markerCalls++;
          if (markerCalls == 1) {
            return Future<ReturnPickupHandoverStatus>.error(
              const OperationalFailure(OperationalFailureCode.network),
            );
          }
          return Future<ReturnPickupHandoverStatus>.value(
            const ReturnPickupHandoverStatus(taskId: _taskId, reported: false),
          );
        },
      );
      addTearDown(() async {
        h.container.dispose();
        await h.sessions.close();
      });
      final vm = await _readyForHandover(h);
      expect(vm.state.handoverStatus.hasError, isTrue);
      expect(h.repo.commands, isEmpty);
      await vm.retryHandoverStatus();
      await _settle(h.container, () => vm.state.handoverStatus.hasValue);
      expect(vm.state.canReportStoreHandover, isTrue);
      expect(h.repo.commands, isEmpty);
    },
  );

  test(
    'already collected assigned projection cannot expose collect/fail',
    () async {
      final h = _harness(
        initial: _pickupDetails(collectedA: 1),
        reload: () async => _pickupDetails(collectedA: 1),
      );
      addTearDown(() async {
        h.container.dispose();
        await h.sessions.close();
      });
      final sub = h.container.listen<ReturnPickupState>(
        returnPickupViewModelProvider(_taskId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      h.sessions.add(_session('shipper-a'));
      await _settle(
        h.container,
        () => h.container
            .read(returnPickupViewModelProvider(_taskId))
            .details
            .hasValue,
      );
      final state = h.container.read(returnPickupViewModelProvider(_taskId));
      expect(state.canCollect, isFalse);
      expect(state.canFail, isFalse);
      expect(h.repo.commands, isEmpty);
    },
  );

  test(
    'failure accepts restricted authoritative projection without PII',
    () async {
      var remote = _pickupDetails();
      final h = _harness(initial: remote, reload: () async => remote);
      h.repo.handler = (command) async {
        remote = _restrictedFailed();
        return _ack(command);
      };
      addTearDown(() async {
        h.container.dispose();
        await h.sessions.close();
      });
      final vm = await _ready(h);
      await vm.submitFailure(
        reason: OutboundFailureReason.other,
        description: 'Khách hẹn lại',
        expectedTask: vm.state.details.requireValue.task,
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      final state = h.container.read(returnPickupViewModelProvider(_taskId));
      expect(state.confirmed, isTrue);
      expect(state.confirmedOperation, ReturnPickupOperation.fail);
      expect(state.details.requireValue.items, isEmpty);
      expect(state.details.requireValue.task.orderId, isNull);
      expect(
        state.details.requireValue.task.scope,
        DeliverySnapshotScope.restricted,
      );
      expect(h.listRefreshes, hasLength(1));
    },
  );

  test(
    'timeout keeps the exact request key and retry does not generate another',
    () async {
      var calls = 0;
      var remote = _pickupDetails();
      final h = _harness(initial: remote, reload: () async => remote);
      h.repo.handler = (command) async {
        if (calls++ == 0) {
          throw TimeoutException('lost acknowledgement');
        }
        remote = _pickupDetails(
          status: 'in_transit',
          acceptedAt: '2026-10-28T02:00:00Z',
          startedAt: '2026-10-28T02:00:00Z',
          collectedA: 2,
          collectedB: 1,
        );
        return _ack(command);
      };
      addTearDown(() async {
        h.container.dispose();
        await h.sessions.close();
      });
      final vm = await _ready(h);
      await vm.submitCollect(
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      final pending = h.container
          .read(returnPickupViewModelProvider(_taskId))
          .pendingCommand;
      expect(pending, isNotNull);
      expect(pending!.requestId, _requestId);
      await vm.retry();
      expect(h.repo.commands, hasLength(2));
      expect(h.repo.commands.first, same(h.repo.commands.last));
      expect(
        h.container.read(returnPickupViewModelProvider(_taskId)).confirmed,
        isTrue,
      );
    },
  );

  test('ACK read failure retries reads only', () async {
    var read = 0;
    var remote = _pickupDetails();
    final h = _harness(
      initial: remote,
      reload: () async {
        if (read++ == 0) {
          throw const OperationalFailure(OperationalFailureCode.network);
        }
        return remote;
      },
    );
    h.repo.handler = (command) async {
      remote = _pickupDetails(
        status: 'in_transit',
        acceptedAt: '2026-10-28T02:00:00Z',
        startedAt: '2026-10-28T02:00:00Z',
        collectedA: 2,
        collectedB: 1,
      );
      return _ack(command);
    };
    addTearDown(() async {
      h.container.dispose();
      await h.sessions.close();
    });
    final vm = await _ready(h);
    await vm.submitCollect(sessionRevision: vm.sessionRevisionForConfirmation);
    expect(h.repo.commands, hasLength(1));
    expect(
      h.container
          .read(returnPickupViewModelProvider(_taskId))
          .requiresReadRetry,
      isTrue,
    );
    await vm.retry();
    expect(h.repo.commands, hasLength(1));
    expect(
      h.container.read(returnPickupViewModelProvider(_taskId)).confirmed,
      isTrue,
    );
  });

  test(
    'account switch clears a pending command and ignores its late ACK',
    () async {
      final gate = Completer<ReturnPickupAck>();
      final h = _harness(
        initial: _pickupDetails(),
        reload: () async => _pickupDetails(),
      );
      h.repo.handler = (_) => gate.future;
      addTearDown(() async {
        h.container.dispose();
        await h.sessions.close();
      });
      final vm = await _ready(h);
      final write = vm.submitCollect(
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      await Future<void>.delayed(Duration.zero);
      h.sessions.add(_session('shipper-b'));
      await _settle(
        h.container,
        () =>
            h.container
                .read(returnPickupViewModelProvider(_taskId))
                .pendingCommand ==
            null,
      );
      gate.complete(
        _ack(
          ReturnPickupCommand.collect(
            taskId: _taskId,
            requestId: _requestId,
            returnRequestId: _returnId,
            orderId: _orderId,
            items: const [
              ReturnPickupItem(returnItemId: _itemA, quantity: 2),
              ReturnPickupItem(returnItemId: _itemB, quantity: 1),
            ],
          ),
        ),
      );
      await write;
      expect(h.listRefreshes, isEmpty);
      expect(
        h.container.read(returnPickupViewModelProvider(_taskId)).confirmed,
        isFalse,
      );
    },
  );

  testWidgets('in-transit pickup exposes only the honest handover blocker', (
    tester,
  ) async {
    final details = _pickupDetails(
      status: 'in_transit',
      acceptedAt: '2026-10-28T02:00:00Z',
      startedAt: '2026-10-28T02:00:00Z',
      collectedA: 2,
      collectedB: 1,
    );
    final sessions = StreamController<OperationalSession>.broadcast();
    final container = ProviderContainer(
      overrides: [
        operationalSessionProvider.overrideWith((ref) => sessions.stream),
        deliveryTaskDetailViewModelProvider(_taskId)
            .overrideWith(() => _FixtureDetailViewModel(_taskId, details)),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await sessions.close();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: ReturnPickupAction(taskId: _taskId)),
        ),
      ),
    );
    sessions.add(_session('shipper-a'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('pickup-handover-disabled')),
      findsOneWidget,
    );
    expect(find.textContaining('Báo bàn giao chưa khả dụng'), findsOneWidget);
    expect(find.byKey(const ValueKey('pickup-collect-open')), findsNothing);
    expect(find.textContaining('/ 2'), findsNothing);
    expect(find.textContaining('COD'), findsNothing);
  });
}
