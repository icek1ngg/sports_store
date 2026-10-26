import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_dto.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';
import 'package:sports_store/features/deliveries/domain/repositories/outbound_task_command_repository.dart';

import 'fixtures/delivery_dtos.dart';
import 'fixtures/outbound_action_fixture.dart';

const _taskId = '11111111-1111-4111-8111-111111111111';
const _requestA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

class _CommandFixtureRepository implements OutboundTaskCommandRepository {
  final commands = <OutboundTaskCommand>[];
  Future<void> Function(OutboundTaskCommand command)? handler;

  @override
  Future<void> execute(OutboundTaskCommand command) {
    commands.add(command);
    return handler?.call(command) ?? Future<void>.value();
  }
}

DeliveryTaskDetails _details({
  String status = 'assigned',
  String task = _taskId,
}) {
  final dto = DeliveryTaskDto.fromJson(
    currentTaskDto(
      task: task,
      status: status,
      acceptedAt: status == 'accepted' || status == 'in_transit'
          ? '2026-10-25T09:00:00Z'
          : null,
      startedAt: status == 'in_transit' ? '2026-10-25T09:10:00Z' : null,
    ),
  );
  return DeliveryTaskDetails(task: dto.toDomain(), items: const []);
}

({
  ProviderContainer container,
  _CommandFixtureRepository repository,
  List<String> reads,
  List<void> refreshes,
})
_harness({
  required _CommandFixtureRepository repository,
  required Future<DeliveryTaskDetails> Function(String taskId) read,
  Future<void> Function()? refreshTaskList,
  String Function()? requestIds,
}) {
  final reads = <String>[];
  final refreshes = <void>[];
  final dependencies = FixtureOutboundActionDependencies(
    initialSession: const FixtureOutboundSession(
      userId: 'shipper-a',
      epoch: 1,
      isShipper: true,
    ),
    readTask: (taskId) {
      reads.add(taskId);
      return read(taskId);
    },
    commandRepository: repository,
    createRequestId: requestIds ?? (() => _requestA),
    refreshTaskList: () async {
      refreshes.add(null);
      await refreshTaskList?.call();
    },
  );
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      fixtureOutboundActionDependenciesProvider.overrideWithValue(dependencies),
    ],
  );
  container.listen(
    fixtureOutboundActionViewModelProvider(_taskId),
    (_, _) {},
    fireImmediately: true,
  );
  return (
    container: container,
    repository: repository,
    reads: reads,
    refreshes: refreshes,
  );
}

Future<void> _settle(ProviderContainer container, bool Function() done) async {
  for (var i = 0; i < 200; i++) {
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    if (done()) return;
  }
  fail('fixture provider did not settle');
}

Future<FixtureOutboundActionViewModel> _ready(
  ProviderContainer container,
) async {
  await _settle(
    container,
    () => container
        .read(fixtureOutboundActionViewModelProvider(_taskId))
        .details
        .hasValue,
  );
  return container.read(
    fixtureOutboundActionViewModelProvider(_taskId).notifier,
  );
}

void main() {
  test(
    'session expiry from list refresh clears details and disables all retries',
    () async {
      var remote = 'assigned';
      final repository = _CommandFixtureRepository()
        ..handler = (_) async {
          remote = 'accepted';
        };
      final h = _harness(
        repository: repository,
        read: (_) async => _details(status: remote),
        refreshTaskList: () async => throw const OutboundCommandFailure(
          OutboundCommandFailureCode.sessionExpired,
        ),
      );
      addTearDown(h.container.dispose);
      final vm = await _ready(h.container);
      await vm.submit(OutboundTaskAction.acceptGoods);
      final state = h.container.read(
        fixtureOutboundActionViewModelProvider(_taskId),
      );
      expect(state.error?.code, OutboundCommandFailureCode.sessionExpired);
      expect(state.details.asData, null);
      expect(state.actionsDenied, true);
      final reads = h.reads.length;
      await vm.retry();
      await vm.submit(OutboundTaskAction.startDelivery);
      expect(h.reads.length, reads);
      expect(repository.commands.length, 1);
    },
  );

  test(
    'terminal detail error overrides timeout and discards uncertain command',
    () async {
      var reads = 0;
      final repository = _CommandFixtureRepository()
        ..handler = (_) async =>
            throw TimeoutException('Fixture lost response');
      final h = _harness(
        repository: repository,
        read: (_) async {
          if (++reads > 1) {
            throw const OutboundCommandFailure(
              OutboundCommandFailureCode.sessionExpired,
            );
          }
          return _details();
        },
      );
      addTearDown(h.container.dispose);
      final vm = await _ready(h.container);
      await vm.submit(OutboundTaskAction.acceptGoods);
      final state = h.container.read(
        fixtureOutboundActionViewModelProvider(_taskId),
      );
      expect(state.error?.code, OutboundCommandFailureCode.sessionExpired);
      expect(state.pendingCommand, null);
      expect(state.details.asData, null);
      await vm.retry();
      expect(repository.commands.length, 1);
      expect(reads, 2);
    },
  );
  test('manual refresh preserves uncertain request; retry does not generate another key', () async {
    final repository = _CommandFixtureRepository();
    var attempts = 0;
    var ids = 0;
    var remote = 'assigned';
    repository.handler = (_) async {
      if (attempts++ == 0) throw TimeoutException('Fixture response lost');
      remote = 'accepted';
    };
    final h = _harness(
      repository: repository,
      read: (_) async => _details(status: remote),
      requestIds: () {
        ids++;
        return _requestA;
      },
    );
    addTearDown(h.container.dispose);
    final vm = await _ready(h.container);
    await vm.submit(OutboundTaskAction.acceptGoods);
    final uncertain = h.container
        .read(fixtureOutboundActionViewModelProvider(_taskId))
        .pendingCommand;
    await vm.refresh();
    expect(
      h.container
          .read(fixtureOutboundActionViewModelProvider(_taskId))
          .pendingCommand,
      same(uncertain),
    );
    await vm.submit(OutboundTaskAction.startDelivery);
    expect(repository.commands.length, 1);
    await vm.retry();
    expect(repository.commands.length, 2);
    expect(repository.commands.first, same(repository.commands.last));
    expect(ids, 1);
  });

  test(
    'ACK with old snapshot stays blocked until authoritative state advances',
    () async {
      var remote = 'assigned';
      final repository = _CommandFixtureRepository();
      final h = _harness(
        repository: repository,
        read: (_) async => _details(status: remote),
      );
      addTearDown(h.container.dispose);
      final vm = await _ready(h.container);
      await vm.submit(OutboundTaskAction.acceptGoods);
      final old = h.container.read(
        fixtureOutboundActionViewModelProvider(_taskId),
      );
      expect(old.error?.code, OutboundCommandFailureCode.staleState);
      expect(old.canAccept, false);
      await vm.submit(OutboundTaskAction.acceptGoods);
      expect(repository.commands.length, 1);
      remote = 'accepted';
      await vm.retry();
      expect(repository.commands.length, 1);
      expect(
        h.container
            .read(fixtureOutboundActionViewModelProvider(_taskId))
            .canStart,
        true,
      );
    },
  );

  test(
    'start ACK cannot regress to assigned and enable another accept',
    () async {
      var remote = 'accepted';
      final repository = _CommandFixtureRepository();
      repository.handler = (_) async {
        remote = 'assigned';
      };
      final h = _harness(
        repository: repository,
        read: (_) async => _details(status: remote),
      );
      addTearDown(h.container.dispose);
      final vm = await _ready(h.container);
      await vm.submit(OutboundTaskAction.startDelivery);
      final state = h.container.read(
        fixtureOutboundActionViewModelProvider(_taskId),
      );
      expect(state.error?.code, OutboundCommandFailureCode.staleState);
      expect(state.canAccept || state.canStart, false);
    },
  );

  for (final code in [
    OutboundCommandFailureCode.permissionDenied,
    OutboundCommandFailureCode.staleAssignment,
    OutboundCommandFailureCode.sessionExpired,
    OutboundCommandFailureCode.dependencyUnavailable,
  ]) {
    test(
      '$code disables writes through read retry until a new session',
      () async {
        final repository = _CommandFixtureRepository();
        repository.handler = (_) async => throw OutboundCommandFailure(code);
        final h = _harness(
          repository: repository,
          read: (_) async => _details(),
        );
        addTearDown(h.container.dispose);
        final vm = await _ready(h.container);
        await vm.submit(OutboundTaskAction.acceptGoods);
        final reads = h.reads.length;
        await vm.retry();
        await vm.submit(OutboundTaskAction.acceptGoods);
        expect(repository.commands.length, 1);
        expect(
          h.container
              .read(fixtureOutboundActionViewModelProvider(_taskId))
              .canAccept,
          false,
        );
        if (code == OutboundCommandFailureCode.sessionExpired) {
          expect(h.reads.length, reads);
        }
      },
    );
  }

  test(
    'ACK read and list errors retry reads only, including failed list',
    () async {
      var lists = 0;
      final listGate = Completer<void>();
      final repository = _CommandFixtureRepository();
      var remote = 'assigned';
      repository.handler = (_) async {
        remote = 'accepted';
      };
      final h = _harness(
        repository: repository,
        read: (_) async => _details(status: remote),
        refreshTaskList: () async {
          if (++lists == 1) {
            throw const OutboundCommandFailure(
              OutboundCommandFailureCode.network,
            );
          }
          await listGate.future;
        },
      );
      addTearDown(h.container.dispose);
      final vm = await _ready(h.container);
      await vm.submit(OutboundTaskAction.acceptGoods);
      expect(
        h.container
            .read(fixtureOutboundActionViewModelProvider(_taskId))
            .canStart,
        false,
      );
      final retry = vm.retry();
      await _settle(h.container, () => lists == 2);
      await vm.retry(); // Conflicting read retry is ignored while busy.
      await vm.submit(OutboundTaskAction.startDelivery);
      expect(repository.commands.length, 1);
      expect(lists, 2);
      listGate.complete();
      await retry;
      expect(
        h.container
            .read(fixtureOutboundActionViewModelProvider(_taskId))
            .canStart,
        true,
      );
    },
  );

  test('wrong task read never renders details or enables actions', () async {
    final h = _harness(
      repository: _CommandFixtureRepository(),
      read: (_) async => _details(task: '22222222-2222-4222-8222-222222222222'),
    );
    addTearDown(h.container.dispose);
    await _settle(
      h.container,
      () => h.container
          .read(fixtureOutboundActionViewModelProvider(_taskId))
          .details
          .hasError,
    );
    final state = h.container.read(
      fixtureOutboundActionViewModelProvider(_taskId),
    );
    expect(state.error?.code, OutboundCommandFailureCode.invalidData);
    expect(state.details.asData, null);
    expect(state.canAccept, false);
  });

  test('late initial read cannot overwrite a newer manual refresh', () async {
    final old = Completer<DeliveryTaskDetails>();
    var reads = 0;
    final h = _harness(
      repository: _CommandFixtureRepository(),
      read: (_) => ++reads == 1
          ? old.future
          : Future.value(_details(status: 'accepted')),
    );
    addTearDown(h.container.dispose);
    await _settle(h.container, () => reads == 1);
    final vm = h.container.read(
      fixtureOutboundActionViewModelProvider(_taskId).notifier,
    );
    await vm.refresh();
    old.complete(_details());
    await h.container.pump();
    expect(
      h.container
          .read(fixtureOutboundActionViewModelProvider(_taskId))
          .canStart,
      true,
    );
  });

  test(
    'ABA account change drops old ACK and never refreshes old list',
    () async {
      final ack = Completer<void>();
      final repository = _CommandFixtureRepository()
        ..handler = (_) => ack.future;
      final h = _harness(repository: repository, read: (_) async => _details());
      addTearDown(h.container.dispose);
      final vm = await _ready(h.container);
      final submit = vm.submit(OutboundTaskAction.acceptGoods);
      vm.updateSession(
        const FixtureOutboundSession(
          userId: 'shipper-b',
          epoch: 1,
          isShipper: true,
        ),
      );
      vm.updateSession(
        const FixtureOutboundSession(
          userId: 'shipper-a',
          epoch: 1,
          isShipper: true,
        ),
      );
      ack.complete();
      await submit;
      await h.container.pump();
      expect(h.refreshes, isEmpty);
      expect(
        h.container
            .read(fixtureOutboundActionViewModelProvider(_taskId))
            .pendingCommand,
        null,
      );
    },
  );

  test(
    'disposing before initial microtask does not start private read',
    () async {
      final h = _harness(
        repository: _CommandFixtureRepository(),
        read: (_) async => _details(),
      );
      h.container.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(h.reads, isEmpty);
    },
  );

  test(
    'invalid ID factory cannot send a command; UUID v7 shape remains accepted',
    () async {
      const uuid7 = OutboundTaskCommand(
        taskId: '11111111-1111-7111-8111-111111111111',
        requestId: _requestA,
        action: OutboundTaskAction.acceptGoods,
      );
      expect(uuid7.isUuidShaped, true);
      final repository = _CommandFixtureRepository();
      final h = _harness(
        repository: repository,
        read: (_) async => _details(),
        requestIds: () => 'invalid',
      );
      addTearDown(h.container.dispose);
      final vm = await _ready(h.container);
      await vm.submit(OutboundTaskAction.acceptGoods);
      expect(repository.commands, isEmpty);
      expect(
        h.container
            .read(fixtureOutboundActionViewModelProvider(_taskId))
            .error
            ?.code,
        OutboundCommandFailureCode.invalidData,
      );
    },
  );
  test(
    'opens read-only, then accepts in order and refetches authoritative state',
    () async {
      final repository = _CommandFixtureRepository();
      final h = _harness(repository: repository, read: (_) async => _details());
      addTearDown(h.container.dispose);
      final vm = h.container.read(
        fixtureOutboundActionViewModelProvider(_taskId).notifier,
      );
      await _settle(
        h.container,
        () => h.container
            .read(fixtureOutboundActionViewModelProvider(_taskId))
            .details
            .hasValue,
      );

      final initial = h.container.read(
        fixtureOutboundActionViewModelProvider(_taskId),
      );
      expect(repository.commands, isEmpty);
      expect(initial.canAccept, isTrue);
      expect(initial.canStart, isFalse);
      await vm.submit(OutboundTaskAction.acceptGoods);

      expect(repository.commands.single.action, OutboundTaskAction.acceptGoods);
      expect(repository.commands.single.requestId, _requestA);
      expect(h.reads.length, 2);
      expect(h.refreshes.length, 1);
      expect(
        h.container
            .read(fixtureOutboundActionViewModelProvider(_taskId))
            .pendingCommand,
        isNull,
      );
    },
  );

  test('start is unavailable while task is assigned', () async {
    final repository = _CommandFixtureRepository();
    final h = _harness(repository: repository, read: (_) async => _details());
    addTearDown(h.container.dispose);
    final vm = h.container.read(
      fixtureOutboundActionViewModelProvider(_taskId).notifier,
    );
    await _settle(
      h.container,
      () => h.container
          .read(fixtureOutboundActionViewModelProvider(_taskId))
          .details
          .hasValue,
    );
    await vm.submit(OutboundTaskAction.startDelivery);
    expect(repository.commands, isEmpty);
    expect(
      h.container
          .read(fixtureOutboundActionViewModelProvider(_taskId))
          .error
          ?.code,
      OutboundCommandFailureCode.staleState,
    );
  });

  test('timeout retry reuses request id and blocks the other action', () async {
    final repository = _CommandFixtureRepository();
    var calls = 0;
    repository.handler = (_) async {
      calls++;
      if (calls == 1) throw TimeoutException('timeout');
    };
    final h = _harness(repository: repository, read: (_) async => _details());
    addTearDown(h.container.dispose);
    final vm = h.container.read(
      fixtureOutboundActionViewModelProvider(_taskId).notifier,
    );
    await _settle(
      h.container,
      () => h.container
          .read(fixtureOutboundActionViewModelProvider(_taskId))
          .details
          .hasValue,
    );
    await vm.submit(OutboundTaskAction.acceptGoods);
    final failed = h.container.read(
      fixtureOutboundActionViewModelProvider(_taskId),
    );
    expect(failed.pendingCommand?.requestId, _requestA);
    expect(failed.error?.code, OutboundCommandFailureCode.timeout);
    await vm.submit(OutboundTaskAction.startDelivery);
    expect(repository.commands.length, 1);
    await vm.retry();
    expect(repository.commands.length, 2);
    expect(repository.commands[0], repository.commands[1]);
  });

  test('busy state ignores duplicate tap', () async {
    final repository = _CommandFixtureRepository();
    final ack = Completer<void>();
    repository.handler = (_) => ack.future;
    final h = _harness(repository: repository, read: (_) async => _details());
    addTearDown(h.container.dispose);
    final vm = h.container.read(
      fixtureOutboundActionViewModelProvider(_taskId).notifier,
    );
    await _settle(
      h.container,
      () => h.container
          .read(fixtureOutboundActionViewModelProvider(_taskId))
          .details
          .hasValue,
    );
    final first = vm.submit(OutboundTaskAction.acceptGoods);
    await Future<void>.delayed(Duration.zero);
    final second = vm.submit(OutboundTaskAction.acceptGoods);
    expect(repository.commands.length, 1);
    ack.complete();
    await Future.wait([first, second]);
  });

  test(
    'permission error refetches and does not retain a write retry',
    () async {
      final repository = _CommandFixtureRepository();
      repository.handler = (_) async {
        throw const OutboundCommandFailure(
          OutboundCommandFailureCode.permissionDenied,
        );
      };
      final h = _harness(repository: repository, read: (_) async => _details());
      addTearDown(h.container.dispose);
      final vm = h.container.read(
        fixtureOutboundActionViewModelProvider(_taskId).notifier,
      );
      await _settle(
        h.container,
        () => h.container
            .read(fixtureOutboundActionViewModelProvider(_taskId))
            .details
            .hasValue,
      );
      await vm.submit(OutboundTaskAction.acceptGoods);
      final state = h.container.read(
        fixtureOutboundActionViewModelProvider(_taskId),
      );
      expect(state.error?.code, OutboundCommandFailureCode.permissionDenied);
      expect(state.pendingCommand, isNull);
      expect(h.reads.length, 2);
    },
  );

  test(
    'account switch clears pending and ignores late command acknowledgement',
    () async {
      final repository = _CommandFixtureRepository();
      final ack = Completer<void>();
      repository.handler = (_) => ack.future;
      final h = _harness(repository: repository, read: (_) async => _details());
      addTearDown(h.container.dispose);
      final vm = h.container.read(
        fixtureOutboundActionViewModelProvider(_taskId).notifier,
      );
      await _settle(
        h.container,
        () => h.container
            .read(fixtureOutboundActionViewModelProvider(_taskId))
            .details
            .hasValue,
      );
      final submit = vm.submit(OutboundTaskAction.acceptGoods);
      await Future<void>.delayed(Duration.zero);
      vm.updateSession(
        const FixtureOutboundSession(
          userId: 'shipper-b',
          epoch: 2,
          isShipper: true,
        ),
      );
      expect(
        h.container
            .read(fixtureOutboundActionViewModelProvider(_taskId))
            .pendingCommand,
        isNull,
      );
      ack.complete();
      await submit;
      expect(
        h.container
            .read(fixtureOutboundActionViewModelProvider(_taskId))
            .session
            .userId,
        'shipper-b',
      );
    },
  );

  test('ack read failure retries read only, never resubmits command', () async {
    final repository = _CommandFixtureRepository();
    var reads = 0;
    final h = _harness(
      repository: repository,
      read: (_) async {
        reads++;
        if (reads > 1) {
          throw const OutboundCommandFailure(
            OutboundCommandFailureCode.network,
          );
        }
        return _details();
      },
    );
    addTearDown(h.container.dispose);
    final vm = h.container.read(
      fixtureOutboundActionViewModelProvider(_taskId).notifier,
    );
    await _settle(
      h.container,
      () => h.container
          .read(fixtureOutboundActionViewModelProvider(_taskId))
          .details
          .hasValue,
    );
    await vm.submit(OutboundTaskAction.acceptGoods);
    expect(repository.commands.length, 1);
    expect(
      h.container
          .read(fixtureOutboundActionViewModelProvider(_taskId))
          .requiresReadRetry,
      isTrue,
    );
    await vm.retry();
    expect(repository.commands.length, 1);
  });
}
