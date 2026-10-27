import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_dto.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_query.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';
import 'package:sports_store/features/deliveries/domain/repositories/delivery_repository.dart';
import 'package:sports_store/features/deliveries/domain/repositories/outbound_task_command_repository.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_providers.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_task_detail_view_model.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/outbound_action_providers.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/outbound_task_actions_view_model.dart';

import 'fixtures/delivery_dtos.dart';

const _taskId = taskId;
const _requestId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

class _CommandRepository implements OutboundTaskCommandRepository {
  final commands = <OutboundTaskCommand>[];
  Future<void> Function(OutboundTaskCommand command)? handler;

  @override
  Future<void> execute(OutboundTaskCommand command) {
    commands.add(command);
    return handler?.call(command) ?? Future<void>.value();
  }
}

class _DeliveryRepository implements DeliveryRepository {
  _DeliveryRepository(this.read);

  Future<DeliveryTaskDetails> Function(String taskId) read;
  final calls = <String>[];

  @override
  Future<DeliveryTaskDetails> getTaskDetails(String taskId) {
    calls.add(taskId);
    return read(taskId);
  }

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

DeliveryTaskDetails _details({
  String status = 'assigned',
  String? acceptedAt,
  String? startedAt,
  String task = _taskId,
}) {
  final dto = DeliveryTaskDto.fromJson(
    currentTaskDto(
      task: task,
      status: status,
      acceptedAt: acceptedAt,
      startedAt: startedAt,
    ),
  );
  return DeliveryTaskDetails(task: dto.toDomain(), items: const []);
}

OperationalSession _session(String? userId, int generation) =>
    OperationalSession(userId: userId, generation: generation);

Future<void> _settle(ProviderContainer container, bool Function() done) async {
  for (var index = 0; index < 200; index++) {
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    if (done()) return;
  }
  fail('provider did not settle');
}

typedef _Harness = ({
  ProviderContainer container,
  ProviderSubscription<OutboundTaskActionsState> actions,
  StreamController<OperationalSession> sessions,
  _CommandRepository repository,
  _DeliveryRepository delivery,
  List<DeliveryTaskDetails> reads,
  List<void> listRefreshes,
});

_Harness _harness({
  required _CommandRepository repository,
  required Future<DeliveryTaskDetails> Function(String taskId) read,
  Future<void> Function()? refreshList,
  Future<DeliveryTaskDetails> Function(String taskId)? reloadDetails,
}) {
  final sessions = StreamController<OperationalSession>.broadcast();
  final observedReads = <DeliveryTaskDetails>[];
  final listRefreshes = <void>[];
  final delivery = _DeliveryRepository((id) async {
    final value = await read(id);
    observedReads.add(value);
    return value;
  });
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      operationalSessionProvider.overrideWith((ref) => sessions.stream),
      deliveryRepositoryProvider.overrideWithValue(delivery),
      outboundTaskCommandRepositoryProvider.overrideWithValue(repository),
      outboundTaskRequestIdProvider.overrideWithValue(() => _requestId),
      outboundTaskDetailsReloadProvider.overrideWithValue(
        (taskId) => reloadDetails?.call(taskId) ?? read(taskId),
      ),
      outboundTaskListReloadProvider.overrideWithValue(() async {
        listRefreshes.add(null);
        await refreshList?.call();
      }),
    ],
  );
  final actions = container.listen<OutboundTaskActionsState>(
    outboundTaskActionsViewModelProvider(_taskId),
    (_, _) {},
    fireImmediately: true,
  );
  sessions.add(_session('shipper-a', 1));
  return (
    container: container,
    actions: actions,
    sessions: sessions,
    repository: repository,
    delivery: delivery,
    reads: observedReads,
    listRefreshes: listRefreshes,
  );
}

Future<OutboundTaskActionsViewModel> _ready(_Harness h) async {
  await _settle(h.container, () {
    final detail = h.container.read(
      deliveryTaskDetailViewModelProvider(_taskId),
    );
    final actions = h.container.read(
      outboundTaskActionsViewModelProvider(_taskId).notifier,
    );
    return detail.hasValue && actions.sessionRevisionForConfirmation > 0;
  });
  return h.container.read(
    outboundTaskActionsViewModelProvider(_taskId).notifier,
  );
}

void main() {
  test(
    'same-account refresh preserves acknowledged attempt for read retry',
    () async {
      var failRead = true;
      final accepted = _details(
        status: 'accepted',
        acceptedAt: '2026-10-26T08:00:00Z',
      );
      final h = _harness(
        repository: _CommandRepository(),
        read: (_) async => _details(),
        reloadDetails: (_) async {
          if (failRead) throw TimeoutException('read');
          return accepted;
        },
      );
      addTearDown(() async {
        h.container.dispose();
        await h.sessions.close();
      });
      final vm = await _ready(h);
      await vm.submit(
        OutboundTaskAction.acceptGoods,
        expectedTask: _details().task,
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      expect(
        h.container
            .read(outboundTaskActionsViewModelProvider(_taskId))
            .acknowledged,
        isTrue,
      );
      final revision = vm.sessionRevisionForConfirmation;
      h.sessions.add(_session('shipper-a', 2));
      await _settle(
        h.container,
        () => vm.sessionRevisionForConfirmation > revision,
      );
      failRead = false;
      await vm.retry();
      final state = h.container.read(
        outboundTaskActionsViewModelProvider(_taskId),
      );
      expect(state.confirmed, isTrue);
      expect(state.requiresReadRetry, isFalse);
      expect(h.repository.commands, hasLength(1));
      expect(h.listRefreshes, hasLength(1));
    },
  );

  test('success performs command, detail reload, then list reload', () async {
    var remote = _details();
    final h = _harness(
      repository: _CommandRepository()
        ..handler = (_) async {
          remote = _details(
            status: 'accepted',
            acceptedAt: '2026-10-25T09:00:00Z',
          );
        },
      read: (_) async => remote,
      reloadDetails: (_) async => remote,
    );
    addTearDown(() async {
      h.container.dispose();
      await h.sessions.close();
    });
    final vm = await _ready(h);
    final expected = remote.task;
    await vm.submit(
      OutboundTaskAction.acceptGoods,
      expectedTask: expected,
      sessionRevision: vm.sessionRevisionForConfirmation,
    );

    expect(h.repository.commands, hasLength(1));
    expect(h.repository.commands.single.action, OutboundTaskAction.acceptGoods);
    expect(h.listRefreshes, hasLength(1));
    final state = h.container.read(
      outboundTaskActionsViewModelProvider(_taskId),
    );
    expect(state.busy, isFalse);
    expect(state.pendingCommand, isNull);
    expect(state.acknowledged, isTrue);
    expect(state.confirmedAction, OutboundTaskAction.acceptGoods);
  });

  test('busy gate ignores duplicate confirmation', () async {
    final gate = Completer<void>();
    final h = _harness(
      repository: _CommandRepository()..handler = (_) => gate.future,
      read: (_) async => _details(),
    );
    addTearDown(() async {
      h.container.dispose();
      await h.sessions.close();
    });
    final vm = await _ready(h);
    final expected = _details().task;
    final first = vm.submit(
      OutboundTaskAction.acceptGoods,
      expectedTask: expected,
      sessionRevision: vm.sessionRevisionForConfirmation,
    );
    await Future<void>.delayed(Duration.zero);
    final second = vm.submit(
      OutboundTaskAction.acceptGoods,
      expectedTask: expected,
      sessionRevision: vm.sessionRevisionForConfirmation,
    );
    expect(h.repository.commands, hasLength(1));
    gate.complete();
    await Future.wait([first, second]);
  });

  test(
    'timeout retains exact command and retry does not generate a key',
    () async {
      var calls = 0;
      final h = _harness(
        repository: _CommandRepository()
          ..handler = (_) async {
            if (calls++ == 0) throw TimeoutException('lost response');
          },
        read: (_) async => _details(),
      );
      addTearDown(() async {
        h.container.dispose();
        await h.sessions.close();
      });
      final vm = await _ready(h);
      final expected = _details().task;
      await vm.submit(
        OutboundTaskAction.acceptGoods,
        expectedTask: expected,
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      final first = h.repository.commands.single;
      expect(
        h.container
            .read(outboundTaskActionsViewModelProvider(_taskId))
            .pendingCommand,
        same(first),
      );
      await vm.retry();
      expect(h.repository.commands, hasLength(2));
      expect(h.repository.commands.last, same(first));
    },
  );

  test('malformed acknowledgement retains the same request key', () async {
    final h = _harness(
      repository: _CommandRepository()
        ..handler = (_) async => throw const OutboundAcknowledgementFailure(),
      read: (_) async => _details(),
    );
    addTearDown(() async {
      h.container.dispose();
      await h.sessions.close();
    });
    final vm = await _ready(h);
    await vm.submit(
      OutboundTaskAction.acceptGoods,
      expectedTask: _details().task,
      sessionRevision: vm.sessionRevisionForConfirmation,
    );
    final state = h.container.read(
      outboundTaskActionsViewModelProvider(_taskId),
    );
    expect(state.error, isA<OutboundAcknowledgementFailure>());
    expect(state.pendingCommand?.requestId, _requestId);
    await vm.retry();
    expect(h.repository.commands, hasLength(2));
    expect(h.repository.commands.first, h.repository.commands.last);
  });

  test('ACK read failure retries detail/list only', () async {
    var reloads = 0;
    var remote = _details();
    final h = _harness(
      repository: _CommandRepository()
        ..handler = (_) async {
          remote = _details(
            status: 'accepted',
            acceptedAt: '2026-10-25T09:00:00Z',
          );
        },
      read: (_) async => remote,
      reloadDetails: (_) async {
        reloads++;
        if (reloads == 1) {
          throw const OperationalFailure(OperationalFailureCode.network);
        }
        return remote;
      },
    );
    addTearDown(() async {
      h.container.dispose();
      await h.sessions.close();
    });
    final vm = await _ready(h);
    await vm.submit(
      OutboundTaskAction.acceptGoods,
      expectedTask: remote.task,
      sessionRevision: vm.sessionRevisionForConfirmation,
    );
    expect(h.repository.commands, hasLength(1));
    expect(
      h.container
          .read(outboundTaskActionsViewModelProvider(_taskId))
          .requiresReadRetry,
      isTrue,
    );
    await vm.retry();
    expect(h.repository.commands, hasLength(1));
    expect(reloads, 2);
    expect(h.listRefreshes, hasLength(1));
  });

  test(
    'business rejection reloads current detail and clears command',
    () async {
      var reloads = 0;
      final h = _harness(
        repository: _CommandRepository()
          ..handler = (_) async => throw const OutboundBusinessFailure(
            OutboundBusinessFailureCode.stateConflict,
          ),
        read: (_) async => _details(),
        reloadDetails: (_) async {
          reloads++;
          return _details();
        },
      );
      addTearDown(() async {
        h.container.dispose();
        await h.sessions.close();
      });
      final vm = await _ready(h);
      await vm.submit(
        OutboundTaskAction.acceptGoods,
        expectedTask: _details().task,
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      final state = h.container.read(
        outboundTaskActionsViewModelProvider(_taskId),
      );
      expect(state.error, isA<OutboundBusinessFailure>());
      expect(state.pendingCommand, isNull);
      expect(state.requiresReadRetry, isFalse);
      expect(reloads, 1);
      expect(h.listRefreshes, hasLength(1));
    },
  );

  test(
    'account switch clears pending and ignores late acknowledgement',
    () async {
      final gate = Completer<void>();
      final h = _harness(
        repository: _CommandRepository()..handler = (_) => gate.future,
        read: (_) async => _details(),
      );
      addTearDown(() async {
        h.container.dispose();
        await h.sessions.close();
      });
      final vm = await _ready(h);
      final submit = vm.submit(
        OutboundTaskAction.acceptGoods,
        expectedTask: _details().task,
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      await Future<void>.delayed(Duration.zero);
      h.sessions.add(_session('shipper-b', 2));
      await _settle(
        h.container,
        () =>
            h.container
                .read(outboundTaskActionsViewModelProvider(_taskId))
                .pendingCommand ==
            null,
      );
      expect(
        h.container
            .read(outboundTaskActionsViewModelProvider(_taskId))
            .pendingCommand,
        isNull,
      );
      gate.complete();
      await submit;
      expect(h.listRefreshes, isEmpty);
    },
  );

  test(
    'same-account refresh freezes the command for exact-key retry',
    () async {
      final gate = Completer<void>();
      final h = _harness(
        repository: _CommandRepository()..handler = (_) => gate.future,
        read: (_) async => _details(),
      );
      addTearDown(() async {
        h.container.dispose();
        await h.sessions.close();
      });
      final vm = await _ready(h);
      final submit = vm.submit(
        OutboundTaskAction.acceptGoods,
        expectedTask: _details().task,
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      await Future<void>.delayed(Duration.zero);
      h.sessions.add(_session('shipper-a', 2));
      await _settle(
        h.container,
        () => !h.container
            .read(outboundTaskActionsViewModelProvider(_taskId))
            .busy,
      );
      final frozen = h.container.read(
        outboundTaskActionsViewModelProvider(_taskId),
      );
      expect(frozen.pendingCommand?.requestId, _requestId);
      gate.complete();
      await submit;
    },
  );

  test(
    'hidden ACK defers detail/list reads until the action route resumes',
    () async {
      final gate = Completer<void>();
      var remote = _details();
      var reloads = 0;
      final h = _harness(
        repository: _CommandRepository()
          ..handler = (_) async {
            await gate.future;
            remote = _details(
              status: 'accepted',
              acceptedAt: '2026-10-25T09:00:00Z',
            );
          },
        read: (_) async => remote,
        reloadDetails: (_) async {
          reloads++;
          return remote;
        },
      );
      addTearDown(() async {
        h.container.dispose();
        await h.sessions.close();
      });
      final vm = await _ready(h);
      final submit = vm.submit(
        OutboundTaskAction.acceptGoods,
        expectedTask: remote.task,
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      await Future<void>.delayed(Duration.zero);
      h.actions.close();
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await submit;
      final hidden = h.container.read(
        outboundTaskActionsViewModelProvider(_taskId),
      );
      expect(hidden.acknowledged, isTrue);
      expect(hidden.requiresReadRetry, isTrue);
      expect(reloads, 0);
      expect(h.listRefreshes, isEmpty);

      final resumed = h.container.listen<OutboundTaskActionsState>(
        outboundTaskActionsViewModelProvider(_taskId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(resumed.close);
      await _settle(
        h.container,
        () => h.container
            .read(outboundTaskActionsViewModelProvider(_taskId))
            .confirmed,
      );
      expect(reloads, 1);
      expect(h.listRefreshes, hasLength(1));
    },
  );

  test(
    'hidden account switch clears the frozen key without a hidden detail read',
    () async {
      final gate = Completer<void>();
      final h = _harness(
        repository: _CommandRepository()..handler = (_) => gate.future,
        read: (_) async => _details(),
      );
      addTearDown(() async {
        h.container.dispose();
        await h.sessions.close();
      });
      final vm = await _ready(h);
      final initialReads = h.delivery.calls.length;
      final submit = vm.submit(
        OutboundTaskAction.acceptGoods,
        expectedTask: _details().task,
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      await Future<void>.delayed(Duration.zero);
      h.actions.close();
      await Future<void>.delayed(Duration.zero);
      h.sessions.add(_session('shipper-b', 2));
      await Future<void>.delayed(Duration.zero);
      expect(h.delivery.calls.length, initialReads);
      gate.complete();
      await submit;
      expect(h.listRefreshes, isEmpty);
    },
  );

  test(
    'hidden business failure resumes its deferred authoritative read',
    () async {
      final gate = Completer<void>();
      var reloads = 0;
      final h = _harness(
        repository: _CommandRepository()
          ..handler = (_) async {
            await gate.future;
            throw const OutboundBusinessFailure(
              OutboundBusinessFailureCode.stateConflict,
            );
          },
        read: (_) async => _details(),
        reloadDetails: (_) async {
          reloads++;
          return _details();
        },
      );
      addTearDown(() async {
        h.container.dispose();
        await h.sessions.close();
      });
      final vm = await _ready(h);
      final submit = vm.submit(
        OutboundTaskAction.acceptGoods,
        expectedTask: _details().task,
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      await Future<void>.delayed(Duration.zero);
      h.actions.close();
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await submit;
      expect(reloads, 0);
      expect(
        h.container
            .read(outboundTaskActionsViewModelProvider(_taskId))
            .requiresReadRetry,
        isTrue,
      );

      final resumed = h.container.listen<OutboundTaskActionsState>(
        outboundTaskActionsViewModelProvider(_taskId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(resumed.close);
      await _settle(
        h.container,
        () =>
            reloads == 1 &&
            !h.container
                .read(outboundTaskActionsViewModelProvider(_taskId))
                .requiresReadRetry,
      );
      expect(
        h.container.read(outboundTaskActionsViewModelProvider(_taskId)).error,
        isA<OutboundBusinessFailure>(),
      );
    },
  );
}
