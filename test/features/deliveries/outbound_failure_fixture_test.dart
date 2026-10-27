import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_dto.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_failure_command.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';

import 'fixtures/delivery_dtos.dart';
import 'fixtures/outbound_failure_fixture.dart';

const _taskId = '11111111-1111-4111-8111-111111111111';
const _requestId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

DeliveryTaskDetails _details({
  String status = 'in_transit',
  String kind = 'outbound',
  String scope = 'current',
  int attempt = 1,
  String task = _taskId,
  bool lifecycleTimestamps = true,
}) {
  final raw =
      scope == 'current'
            ? currentTaskDto(
                task: task,
                kind: kind,
                status: status,
                acceptedAt: lifecycleTimestamps ? '2026-10-25T09:00:00Z' : null,
                startedAt: lifecycleTimestamps ? '2026-10-25T09:10:00Z' : null,
              )
            : maskedTaskDto(kind: kind, status: status, scope: scope)
        ..['task_id'] = task;
  raw['attempt_number'] = attempt;
  final dto = DeliveryTaskDto.fromJson(raw);
  return DeliveryTaskDetails(task: dto.toDomain(), items: const []);
}

DeliveryTaskDetails _current({int attempt = 1, String task = _taskId}) =>
    _details(attempt: attempt, task: task);

DeliveryTaskDetails _failed({int attempt = 1, String task = _taskId}) =>
    _details(
      status: 'failed',
      scope: 'restricted',
      attempt: attempt,
      task: task,
    );

({
  ProviderContainer container,
  ScriptedOutboundFailureRepository repository,
  List<String> reads,
  List<String> reloads,
})
_harness({
  required ScriptedOutboundFailureRepository repository,
  required Future<DeliveryTaskDetails> Function(String taskId) read,
  FixtureOutboundSession? session,
  String? assignedActorId,
  Future<void> Function()? refreshTaskList,
  String Function()? requestIds,
}) {
  final reads = <String>[];
  final reloads = <String>[];
  final dependencies = FixtureOutboundFailureDependencies(
    initialSession:
        session ??
        const FixtureOutboundSession(
          userId: 'shipper-a',
          epoch: 1,
          isShipper: true,
        ),
    assignedActorId: assignedActorId,
    readTask: (taskId) {
      reads.add(taskId);
      return read(taskId);
    },
    failureRepository: repository,
    createRequestId: requestIds ?? (() => _requestId),
    refreshTaskList: () async {
      reloads.add('mh10');
      await refreshTaskList?.call();
    },
  );
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      fixtureOutboundFailureDependenciesProvider.overrideWithValue(
        dependencies,
      ),
    ],
  );
  container.listen(
    fixtureOutboundFailureViewModelProvider(_taskId),
    (_, _) {},
    fireImmediately: true,
  );
  return (
    container: container,
    repository: repository,
    reads: reads,
    reloads: reloads,
  );
}

Future<void> _settle(ProviderContainer container, bool Function() done) async {
  for (var index = 0; index < 250; index++) {
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    if (done()) return;
  }
  fail('failure fixture did not settle');
}

Future<FixtureOutboundFailureViewModel> _ready(
  ProviderContainer container,
) async {
  await _settle(
    container,
    () => container
        .read(fixtureOutboundFailureViewModelProvider(_taskId))
        .details
        .hasValue,
  );
  return container.read(
    fixtureOutboundFailureViewModelProvider(_taskId).notifier,
  );
}

FixtureOutboundFailureState _state(ProviderContainer container) =>
    container.read(fixtureOutboundFailureViewModelProvider(_taskId));

void main() {
  test('reason, description and UUID draft validation have no amount/shipper input', () {
    const command = OutboundFailureCommand(
      taskId: _taskId,
      requestId: _requestId,
      attemptNumber: 1,
      reason: OutboundFailureReason.other,
      description: '  recipient was unavailable  ',
    );
    expect(command.isValid, isTrue);
    expect(command.trimmedDescription, 'recipient was unavailable');
    expect(command.toString(), contains('hasDescription: true'));
    expect(command.toString(), isNot(contains('recipient was unavailable')));
    expect(command.toString(), isNot(contains('amount')));
    expect(command.toString(), isNot(contains('shipper')));
    expect(
      const OutboundFailureCommand(
        taskId: _taskId,
        requestId: _requestId,
        attemptNumber: 1,
        reason: OutboundFailureReason.other,
        description: '  ',
      ).isValid,
      isFalse,
    );
    expect(
      const OutboundFailureCommand(
        taskId: 'not-a-uuid',
        requestId: _requestId,
        attemptNumber: 1,
        reason: OutboundFailureReason.unreachable,
      ).isValid,
      isFalse,
    );
    expect(
      const OutboundFailureCommand(
        taskId: _taskId,
        requestId: _requestId,
        attemptNumber: 3,
        reason: OutboundFailureReason.unreachable,
      ).isValid,
      isFalse,
    );
  });

  test('ack carries exact command identity and first/second dispositions', () {
    const first = OutboundFailureCommand(
      taskId: _taskId,
      requestId: _requestId,
      attemptNumber: 1,
      reason: OutboundFailureReason.unreachable,
    );
    const second = OutboundFailureCommand(
      taskId: _taskId,
      requestId: _requestId,
      attemptNumber: 2,
      reason: OutboundFailureReason.refusal,
    );
    const firstAck = OutboundFailureAck(
      taskId: _taskId,
      requestId: _requestId,
      attemptNumber: 1,
      disposition: OutboundFailureDisposition.managerDecision,
    );
    const secondAck = OutboundFailureAck(
      taskId: _taskId,
      requestId: _requestId,
      attemptNumber: 2,
      disposition: OutboundFailureDisposition.storeReturnPending,
    );
    expect(firstAck.isValid, isTrue);
    expect(firstAck.matches(first), isTrue);
    expect(firstAck.matches(second), isFalse);
    expect(secondAck.isValid, isTrue);
    expect(secondAck.matches(second), isTrue);
    expect(
      const OutboundFailureAck(
        taskId: _taskId,
        requestId: _requestId,
        attemptNumber: 2,
        disposition: OutboundFailureDisposition.managerDecision,
      ).isValid,
      isFalse,
    );
  });

  test('eligibility requires current outbound in-transit owner and all lifecycle timestamps', () async {
    final repository = ScriptedOutboundFailureRepository();
    var remote = _current();
    final h = _harness(
      repository: repository,
      assignedActorId: 'shipper-a',
      read: (_) async => remote,
    );
    addTearDown(h.container.dispose);
    final vm = await _ready(h.container);
    expect(_state(h.container).canReport, isTrue);

    remote = _details(lifecycleTimestamps: false);
    await vm.refresh();
    expect(_state(h.container).canReport, isFalse);

    remote = _details(status: 'assigned');
    await vm.refresh();
    expect(_state(h.container).canReport, isFalse);
  });

  test(
    'attempt one reports, reads restricted failed task, then reloads MH10',
    () async {
      var remote = _current();
      final repository = ScriptedOutboundFailureRepository()
        ..handler = (_) async {
          remote = _failed();
          return const OutboundFailureAck(
            taskId: _taskId,
            requestId: _requestId,
            attemptNumber: 1,
            disposition: OutboundFailureDisposition.managerDecision,
          );
        };
      final h = _harness(
        repository: repository,
        assignedActorId: 'shipper-a',
        read: (_) async => remote,
      );
      addTearDown(h.container.dispose);
      final vm = await _ready(h.container);
      await vm.submit(
        reason: OutboundFailureReason.badAddress,
        description: '  address did not resolve  ',
      );
      final state = _state(h.container);
      expect(repository.commands, hasLength(1));
      expect(repository.commands.single.attemptNumber, 1);
      expect(repository.commands.single.description, 'address did not resolve');
      expect(
        state.acknowledgement?.disposition,
        OutboundFailureDisposition.managerDecision,
      );
      expect(state.reported, isTrue);
      expect(state.details.requireValue.task.status, DeliveryTaskStatus.failed);
      expect(
        state.details.requireValue.task.scope,
        DeliverySnapshotScope.restricted,
      );
      expect(h.reloads, ['mh10']);
    },
  );

  test(
    'attempt two reports with storeReturnPending and no third-attempt path',
    () async {
      var remote = _current(attempt: 2);
      final repository = ScriptedOutboundFailureRepository()
        ..handler = (_) async {
          remote = _failed(attempt: 2);
          return const OutboundFailureAck(
            taskId: _taskId,
            requestId: _requestId,
            attemptNumber: 2,
            disposition: OutboundFailureDisposition.storeReturnPending,
          );
        };
      final h = _harness(
        repository: repository,
        assignedActorId: 'shipper-a',
        read: (_) async => remote,
      );
      addTearDown(h.container.dispose);
      final vm = await _ready(h.container);
      await vm.submit(reason: OutboundFailureReason.refusal);
      expect(repository.commands.single.attemptNumber, 2);
      expect(
        _state(h.container).disposition,
        OutboundFailureDisposition.storeReturnPending,
      );
      expect(_state(h.container).reported, isTrue);
      expect(_state(h.container).canReport, isFalse);
    },
  );

  test(
    'duplicate confirm while write is busy starts one command/key',
    () async {
      var remote = _current();
      final gate = Completer<OutboundFailureAck>();
      final repository = ScriptedOutboundFailureRepository()
        ..handler = (_) => gate.future;
      final h = _harness(
        repository: repository,
        assignedActorId: 'shipper-a',
        read: (_) async => remote,
      );
      addTearDown(h.container.dispose);
      final vm = await _ready(h.container);
      final first = vm.submit(reason: OutboundFailureReason.unreachable);
      await Future<void>.delayed(Duration.zero);
      final duplicate = vm.submit(
        reason: OutboundFailureReason.other,
        description: 'changed draft',
      );
      expect(repository.commands, hasLength(1));
      remote = _failed();
      gate.complete(
        const OutboundFailureAck(
          taskId: _taskId,
          requestId: _requestId,
          attemptNumber: 1,
          disposition: OutboundFailureDisposition.managerDecision,
        ),
      );
      await Future.wait([first, duplicate]);
      expect(repository.commands, hasLength(1));
      expect(
        repository.commands.single.reason,
        OutboundFailureReason.unreachable,
      );
    },
  );

  test('timeout freezes pending payload and retry reuses exact command after changed draft', () async {
    var calls = 0;
    final repository = ScriptedOutboundFailureRepository()
      ..handler = (_) async {
        if (calls++ == 0) throw TimeoutException('lost response');
        return const OutboundFailureAck(
          taskId: _taskId,
          requestId: _requestId,
          attemptNumber: 1,
          disposition: OutboundFailureDisposition.managerDecision,
        );
      };
    var remote = _current();
    final h = _harness(
      repository: repository,
      assignedActorId: 'shipper-a',
      read: (_) async => remote,
    );
    addTearDown(h.container.dispose);
    final vm = await _ready(h.container);
    await vm.submit(reason: OutboundFailureReason.reschedule);
    final pending = _state(h.container).pendingCommand;
    expect(pending, isNotNull);
    expect(_state(h.container).error?.code, OutboundCommandFailureCode.timeout);
    await vm.submit(
      reason: OutboundFailureReason.other,
      description: 'new draft must not replace pending',
    );
    expect(repository.commands, hasLength(1));
    remote = _failed();
    await vm.retry();
    expect(repository.commands, hasLength(2));
    expect(repository.commands[1], same(repository.commands[0]));
    expect(_state(h.container).reported, isTrue);
    expect(_state(h.container).acknowledgement?.requestId, _requestId);
  });

  test(
    'network failure uses same retry semantics and does not reload MH10 early',
    () async {
      var calls = 0;
      final repository = ScriptedOutboundFailureRepository()
        ..handler = (_) async {
          if (calls++ == 0) {
            throw const OutboundCommandFailure(
              OutboundCommandFailureCode.network,
            );
          }
          return const OutboundFailureAck(
            taskId: _taskId,
            requestId: _requestId,
            attemptNumber: 1,
            disposition: OutboundFailureDisposition.managerDecision,
          );
        };
      var remote = _current();
      final h = _harness(
        repository: repository,
        assignedActorId: 'shipper-a',
        read: (_) async => remote,
      );
      addTearDown(h.container.dispose);
      final vm = await _ready(h.container);
      await vm.submit(reason: OutboundFailureReason.unreachable);
      expect(_state(h.container).pendingCommand, isNotNull);
      expect(h.reloads, isEmpty);
      remote = _failed();
      await vm.retry();
      expect(repository.commands, hasLength(2));
      expect(h.reloads, ['mh10']);
    },
  );

  test('ACK followed by read failure retries read only', () async {
    var reads = 0;
    var remote = _current();
    final repository = ScriptedOutboundFailureRepository()
      ..handler = (_) async {
        remote = _failed();
        return const OutboundFailureAck(
          taskId: _taskId,
          requestId: _requestId,
          attemptNumber: 1,
          disposition: OutboundFailureDisposition.managerDecision,
        );
      };
    final h = _harness(
      repository: repository,
      assignedActorId: 'shipper-a',
      read: (_) async {
        if (++reads == 2) {
          throw const OutboundCommandFailure(
            OutboundCommandFailureCode.network,
          );
        }
        return remote;
      },
    );
    addTearDown(h.container.dispose);
    final vm = await _ready(h.container);
    await vm.submit(reason: OutboundFailureReason.unreachable);
    expect(repository.commands, hasLength(1));
    expect(_state(h.container).pendingCommand, isNull);
    expect(_state(h.container).awaitingAuthoritativeRead, isTrue);
    expect(_state(h.container).error?.code, OutboundCommandFailureCode.network);
    await vm.retry();
    expect(repository.commands, hasLength(1));
    expect(_state(h.container).reported, isTrue);
    expect(h.reloads, ['mh10']);
  });

  test('old in-transit read after ACK is stale; retry reads failed task without writing again', () async {
    var remote = _current();
    final repository = ScriptedOutboundFailureRepository()
      ..handler = (_) async => const OutboundFailureAck(
        taskId: _taskId,
        requestId: _requestId,
        attemptNumber: 1,
        disposition: OutboundFailureDisposition.managerDecision,
      );
    final h = _harness(
      repository: repository,
      assignedActorId: 'shipper-a',
      read: (_) async => remote,
    );
    addTearDown(h.container.dispose);
    final vm = await _ready(h.container);
    await vm.submit(reason: OutboundFailureReason.refusal);
    expect(_state(h.container).reported, isFalse);
    expect(
      _state(h.container).error?.code,
      OutboundCommandFailureCode.staleState,
    );
    expect(repository.commands, hasLength(1));
    remote = _failed();
    await vm.retry();
    expect(repository.commands, hasLength(1));
    expect(_state(h.container).reported, isTrue);
  });

  test(
    'mismatched ACK is typed invalid data and never becomes local success',
    () async {
      final repository = ScriptedOutboundFailureRepository()
        ..handler = (_) async => const OutboundFailureAck(
          taskId: _taskId,
          requestId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          attemptNumber: 1,
          disposition: OutboundFailureDisposition.managerDecision,
        );
      final h = _harness(
        repository: repository,
        assignedActorId: 'shipper-a',
        read: (_) async => _current(),
      );
      addTearDown(h.container.dispose);
      final vm = await _ready(h.container);
      await vm.submit(reason: OutboundFailureReason.unreachable);
      expect(
        _state(h.container).error?.code,
        OutboundCommandFailureCode.invalidData,
      );
      expect(_state(h.container).reported, isFalse);
      expect(_state(h.container).acknowledgement, isNull);
      expect(_state(h.container).pendingCommand, isNotNull);
      expect(_state(h.container).canReport, isFalse);
    },
  );

  test(
    'permission or stale assignment clears/redacts detail and blocks retries',
    () async {
      for (final failure in [
        OutboundCommandFailureCode.permissionDenied,
        OutboundCommandFailureCode.staleAssignment,
      ]) {
        final repository = ScriptedOutboundFailureRepository()
          ..handler = (_) async => throw OutboundCommandFailure(failure);
        final h = _harness(
          repository: repository,
          assignedActorId: 'shipper-a',
          read: (_) async => _current(),
        );
        final vm = await _ready(h.container);
        await vm.submit(reason: OutboundFailureReason.unreachable);
        final state = _state(h.container);
        expect(state.error?.code, failure);
        expect(state.details.hasValue, isFalse);
        expect(state.actionsDenied, isTrue);
        await vm.retry();
        expect(repository.commands, hasLength(1));
        h.container.dispose();
      }
    },
  );

  test(
    'ACK decode failure retains the dispatched command for same-key retry',
    () async {
      var calls = 0;
      var remote = _current();
      final repository = ScriptedOutboundFailureRepository()
        ..handler = (_) async {
          if (calls++ == 0) throw const FormatException('malformed ACK');
          remote = _failed();
          return const OutboundFailureAck(
            taskId: _taskId,
            requestId: _requestId,
            attemptNumber: 1,
            disposition: OutboundFailureDisposition.managerDecision,
          );
        };
      final h = _harness(
        repository: repository,
        assignedActorId: 'shipper-a',
        read: (_) async => remote,
      );
      addTearDown(h.container.dispose);
      final vm = await _ready(h.container);
      await vm.submit(reason: OutboundFailureReason.unreachable);
      expect(
        _state(h.container).error?.code,
        OutboundCommandFailureCode.invalidData,
      );
      expect(_state(h.container).pendingCommand, isNotNull);
      await vm.retry();
      expect(repository.commands, hasLength(2));
      expect(repository.commands.first, same(repository.commands.last));
      expect(_state(h.container).reported, isTrue);
    },
  );

  test(
    'unclassified post-dispatch failure also keeps the idempotency key',
    () async {
      final repository = ScriptedOutboundFailureRepository()
        ..handler = (_) async => throw StateError('response decoder failed');
      final h = _harness(
        repository: repository,
        assignedActorId: 'shipper-a',
        read: (_) async => _current(),
      );
      addTearDown(h.container.dispose);
      final vm = await _ready(h.container);
      await vm.submit(reason: OutboundFailureReason.unreachable);
      expect(
        _state(h.container).error?.code,
        OutboundCommandFailureCode.unexpected,
      );
      expect(_state(h.container).pendingCommand, isNotNull);
      expect(_state(h.container).canReport, isFalse);
    },
  );

  test('session change drops old in-flight ACK/read and does not reload old MH10 state', () async {
    final ack = Completer<OutboundFailureAck>();
    var remote = _current();
    final repository = ScriptedOutboundFailureRepository()
      ..handler = (_) => ack.future;
    final h = _harness(
      repository: repository,
      assignedActorId: 'shipper-a',
      read: (_) async => remote,
    );
    addTearDown(h.container.dispose);
    final vm = await _ready(h.container);
    final submit = vm.submit(reason: OutboundFailureReason.unreachable);
    await Future<void>.delayed(Duration.zero);
    final revision = vm.sessionRevisionForFixture;
    vm.updateSession(
      const FixtureOutboundSession(
        userId: 'shipper-b',
        epoch: 2,
        isShipper: true,
      ),
    );
    expect(vm.sessionRevisionForFixture, greaterThan(revision));
    expect(_state(h.container).details.hasValue, isFalse);
    remote = _failed();
    ack.complete(
      const OutboundFailureAck(
        taskId: _taskId,
        requestId: _requestId,
        attemptNumber: 1,
        disposition: OutboundFailureDisposition.managerDecision,
      ),
    );
    await submit;
    await Future<void>.delayed(Duration.zero);
    expect(h.reloads, isEmpty);
    expect(_state(h.container).session.userId, 'shipper-b');
    expect(_state(h.container).reported, isFalse);
  });

  test(
    'late initial read cannot overwrite newer session and owner epoch',
    () async {
      final oldRead = Completer<DeliveryTaskDetails>();
      var reads = 0;
      final h = _harness(
        repository: ScriptedOutboundFailureRepository(),
        assignedActorId: 'shipper-a',
        read: (_) => ++reads == 1 ? oldRead.future : Future.value(_current()),
      );
      addTearDown(h.container.dispose);
      final vm = h.container.read(
        fixtureOutboundFailureViewModelProvider(_taskId).notifier,
      );
      await Future<void>.delayed(Duration.zero);
      vm.updateSession(
        const FixtureOutboundSession(
          userId: 'shipper-b',
          epoch: 4,
          isShipper: true,
        ),
      );
      oldRead.complete(_current());
      await _settle(h.container, () => _state(h.container).actionsDenied);
      expect(_state(h.container).session.userId, 'shipper-b');
      expect(_state(h.container).details.hasValue, isFalse);
      expect(_state(h.container).canReport, isFalse);
    },
  );

  test('failed MH10 reload remains a callback-only retry after authoritative result', () async {
    var remote = _current();
    var reloads = 0;
    final repository = ScriptedOutboundFailureRepository()
      ..handler = (_) async {
        remote = _failed();
        return const OutboundFailureAck(
          taskId: _taskId,
          requestId: _requestId,
          attemptNumber: 1,
          disposition: OutboundFailureDisposition.managerDecision,
        );
      };
    final h = _harness(
      repository: repository,
      assignedActorId: 'shipper-a',
      read: (_) async => remote,
      refreshTaskList: () async {
        if (++reloads == 1) {
          throw const OutboundCommandFailure(
            OutboundCommandFailureCode.network,
          );
        }
      },
    );
    addTearDown(h.container.dispose);
    final vm = await _ready(h.container);
    await vm.submit(reason: OutboundFailureReason.unreachable);
    final readsAfterAck = h.reads.length;
    expect(_state(h.container).reported, isTrue);
    expect(_state(h.container).requiresReadRetry, isTrue);
    await vm.retry();
    expect(repository.commands, hasLength(1));
    expect(h.reads.length, readsAfterAck);
    expect(_state(h.container).requiresReadRetry, isFalse);
    expect(_state(h.container).busy, isFalse);
  });

  test('inactive session starts redacted and never submits', () async {
    final repository = ScriptedOutboundFailureRepository();
    final h = _harness(
      repository: repository,
      session: const FixtureOutboundSession(
        userId: null,
        epoch: 9,
        isShipper: true,
      ),
      read: (_) async => _current(),
    );
    addTearDown(h.container.dispose);
    final vm = h.container.read(
      fixtureOutboundFailureViewModelProvider(_taskId).notifier,
    );
    await vm.submit(reason: OutboundFailureReason.unreachable);
    expect(repository.commands, isEmpty);
    expect(_state(h.container).details.hasValue, isFalse);
    expect(_state(h.container).actionsDenied, isTrue);
  });
}
