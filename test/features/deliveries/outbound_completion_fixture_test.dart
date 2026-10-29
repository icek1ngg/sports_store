import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_dto.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_completion_command.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';
import 'package:sports_store/features/deliveries/domain/repositories/outbound_completion_repository.dart';

import 'fixtures/delivery_dtos.dart';
import 'fixtures/outbound_completion_fixture.dart';

const _taskId = '11111111-1111-4111-8111-111111111111';
const _requestId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

class _CompletionRepository implements OutboundCompletionRepository {
  final commands = <OutboundCompletionCommand>[];
  Future<void> Function(OutboundCompletionCommand command)? handler;

  @override
  Future<void> execute(OutboundCompletionCommand command) {
    commands.add(command);
    return handler?.call(command) ?? Future<void>.value();
  }
}

DeliveryTaskDetails _current({
  String kind = 'outbound',
  String status = 'in_transit',
  Object amount = 550000,
  String task = _taskId,
}) {
  final dto = DeliveryTaskDto.fromJson(
    currentTaskDto(
      task: task,
      kind: kind,
      status: status,
      amount: amount,
      acceptedAt: '2026-10-25T09:00:00Z',
      startedAt: '2026-10-25T09:10:00Z',
    ),
  );
  return DeliveryTaskDetails(task: dto.toDomain(), items: const []);
}

DeliveryTaskDetails _deliveredHistory() {
  final dto = DeliveryTaskDto.fromJson(
    maskedTaskDto(status: 'delivered', scope: 'history'),
  );
  return DeliveryTaskDetails(task: dto.toDomain(), items: const []);
}

({
  ProviderContainer container,
  _CompletionRepository repository,
  List<String> reads,
  List<String> refreshes,
})
_harness({
  required _CompletionRepository repository,
  required Future<DeliveryTaskDetails> Function(String taskId) read,
  FixtureOutboundSession? session,
  Future<void> Function()? refreshTaskList,
  Future<void> Function()? refreshCod,
  String Function()? requestIds,
}) {
  final reads = <String>[];
  final refreshes = <String>[];
  final dependencies = FixtureOutboundCompletionDependencies(
    initialSession:
        session ??
        const FixtureOutboundSession(
          userId: 'shipper-a',
          epoch: 1,
          isShipper: true,
        ),
    readTask: (taskId) {
      reads.add(taskId);
      return read(taskId);
    },
    commandRepository: repository,
    createRequestId: requestIds ?? (() => _requestId),
    refreshTaskList: () async {
      refreshes.add('tasks');
      await refreshTaskList?.call();
    },
    refreshCod: () async {
      refreshes.add('cod');
      await refreshCod?.call();
    },
  );
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      fixtureOutboundCompletionDependenciesProvider.overrideWithValue(
        dependencies,
      ),
    ],
  );
  container.listen(
    fixtureOutboundCompletionViewModelProvider(_taskId),
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
  fail('completion fixture did not settle');
}

Future<FixtureOutboundCompletionViewModel> _ready(
  ProviderContainer container,
) async {
  await _settle(
    container,
    () => container
        .read(fixtureOutboundCompletionViewModelProvider(_taskId))
        .details
        .hasValue,
  );
  return container.read(
    fixtureOutboundCompletionViewModelProvider(_taskId).notifier,
  );
}

FixtureOutboundCompletionState _state(ProviderContainer container) =>
    container.read(fixtureOutboundCompletionViewModelProvider(_taskId));

void main() {
  test('command is exact and contains no shipper or order total', () {
    const command = OutboundCompletionCommand(
      taskId: _taskId,
      requestId: _requestId,
      receivedAllItems: true,
      reportedCollectedAmountVnd: 550000,
    );
    expect(command.isValid, isTrue);
    expect(command.hasUuidShape, isTrue);
    expect(command.hasSafePositiveAmount, isTrue);
    expect(command.toString(), isNot(contains('shipper')));
    expect(command.toString(), isNot(contains('orderTotal')));
  });

  test(
    'authoritative amount is 550000 including fee, with no UI addition',
    () async {
      final h = _harness(
        repository: _CompletionRepository(),
        read: (_) async => _current(),
      );
      addTearDown(h.container.dispose);
      final vm = await _ready(h.container);
      final state = _state(h.container);
      expect(state.authoritativeAmountVnd, 550000);
      expect(state.canComplete, isTrue);
      expect(vm.sessionRevisionForFixture, 1);
    },
  );

  test('both confirmations and an exact amount are required', () async {
    final repository = _CompletionRepository();
    final h = _harness(repository: repository, read: (_) async => _current());
    addTearDown(h.container.dispose);
    final vm = await _ready(h.container);

    await vm.submit(
      receivedAllItems: false,
      receivedFullCod: true,
      displayedAmountVnd: 550000,
    );
    expect(
      _state(h.container).error?.code,
      OutboundCommandFailureCode.invalidData,
    );
    expect(repository.commands, isEmpty);

    await vm.submit(
      receivedAllItems: true,
      receivedFullCod: false,
      displayedAmountVnd: 550000,
    );
    expect(repository.commands, isEmpty);

    await vm.submit(
      receivedAllItems: true,
      receivedFullCod: true,
      displayedAmountVnd: 520000,
    );
    expect(
      _state(h.container).error?.code,
      OutboundCommandFailureCode.invalidData,
    );
    expect(repository.commands, isEmpty);
  });

  test(
    'wrong kind/status and missing or non-positive amounts cannot complete',
    () async {
      var remote = _current(status: 'assigned');
      final h = _harness(
        repository: _CompletionRepository(),
        read: (_) async => remote,
      );
      addTearDown(h.container.dispose);
      final vm = await _ready(h.container);
      await vm.submit(
        receivedAllItems: true,
        receivedFullCod: true,
        displayedAmountVnd: 550000,
      );
      expect(
        _state(h.container).error?.code,
        OutboundCommandFailureCode.staleState,
      );

      remote = _current(amount: 0);
      await vm.refresh();
      await vm.submit(
        receivedAllItems: true,
        receivedFullCod: true,
        displayedAmountVnd: 0,
      );
      expect(
        _state(h.container).error?.code,
        OutboundCommandFailureCode.invalidData,
      );
    },
  );

  test('timeout retry reuses one request ID and confirms only after delivered read', () async {
    var calls = 0;
    var remote = _current();
    final repository = _CompletionRepository()
      ..handler = (_) async {
        if (calls++ == 0) throw TimeoutException('lost response');
        remote = _deliveredHistory();
      };
    var idCalls = 0;
    final h = _harness(
      repository: repository,
      read: (_) async => remote,
      requestIds: () {
        idCalls++;
        return _requestId;
      },
    );
    addTearDown(h.container.dispose);
    final vm = await _ready(h.container);
    await vm.submit(
      receivedAllItems: true,
      receivedFullCod: true,
      displayedAmountVnd: 550000,
    );
    expect(repository.commands, hasLength(1));
    expect(_state(h.container).pendingCommand, isNotNull);
    expect(_state(h.container).confirmed, isFalse);
    await vm.retry();
    expect(repository.commands, hasLength(2));
    expect(repository.commands.first, same(repository.commands.last));
    expect(idCalls, 1);
    expect(_state(h.container).confirmed, isTrue);
    expect(
      _state(h.container).details.requireValue.task.scope,
      DeliverySnapshotScope.history,
    );
  });

  test(
    'ACK with an old read blocks another command and does not fake success',
    () async {
      var remote = _current();
      final repository = _CompletionRepository()
        ..handler = (_) async {
          remote = _current();
        };
      final h = _harness(repository: repository, read: (_) async => remote);
      addTearDown(h.container.dispose);
      final vm = await _ready(h.container);
      await vm.submit(
        receivedAllItems: true,
        receivedFullCod: true,
        displayedAmountVnd: 550000,
      );
      expect(_state(h.container).confirmed, isFalse);
      expect(_state(h.container).awaitingAuthoritativeRead, isTrue);
      expect(
        _state(h.container).error?.code,
        OutboundCommandFailureCode.staleState,
      );
      expect(repository.commands, hasLength(1));

      await vm.submit(
        receivedAllItems: true,
        receivedFullCod: true,
        displayedAmountVnd: 550000,
      );
      expect(repository.commands, hasLength(1));

      remote = _deliveredHistory();
      await vm.retry();
      expect(_state(h.container).confirmed, isTrue);
      expect(repository.commands, hasLength(1));
    },
  );

  test(
    'busy state rejects duplicate taps while the write is in flight',
    () async {
      final gate = Completer<void>();
      final repository = _CompletionRepository()..handler = (_) => gate.future;
      final h = _harness(repository: repository, read: (_) async => _current());
      addTearDown(h.container.dispose);
      final vm = await _ready(h.container);
      final first = vm.submit(
        receivedAllItems: true,
        receivedFullCod: true,
        displayedAmountVnd: 550000,
      );
      await Future<void>.delayed(Duration.zero);
      await vm.submit(
        receivedAllItems: true,
        receivedFullCod: true,
        displayedAmountVnd: 550000,
      );
      expect(repository.commands, hasLength(1));
      gate.complete();
      await first;
    },
  );

  test(
    'successful ACK refreshes task list and COD after masked delivered read',
    () async {
      var remote = _current();
      final repository = _CompletionRepository()
        ..handler = (_) async {
          remote = _deliveredHistory();
        };
      final h = _harness(repository: repository, read: (_) async => remote);
      addTearDown(h.container.dispose);
      final vm = await _ready(h.container);
      await vm.submit(
        receivedAllItems: true,
        receivedFullCod: true,
        displayedAmountVnd: 550000,
      );
      expect(_state(h.container).confirmed, isTrue);
      expect(h.refreshes, ['tasks', 'cod']);
      expect(_state(h.container).authoritativeAmountVnd, isNull);
    },
  );

  test(
    'failed task refresh does not suppress COD refresh and retries cache only',
    () async {
      var remote = _current();
      var taskRefreshes = 0;
      var codRefreshes = 0;
      final repository = _CompletionRepository()
        ..handler = (_) async {
          remote = _deliveredHistory();
        };
      final h = _harness(
        repository: repository,
        read: (_) async => remote,
        refreshTaskList: () async {
          if (++taskRefreshes == 1) {
            throw const OutboundCommandFailure(
              OutboundCommandFailureCode.network,
            );
          }
        },
        refreshCod: () async {
          codRefreshes++;
        },
      );
      addTearDown(h.container.dispose);
      final vm = await _ready(h.container);
      await vm.submit(
        receivedAllItems: true,
        receivedFullCod: true,
        displayedAmountVnd: 550000,
      );
      expect(_state(h.container).confirmed, isTrue);
      expect(_state(h.container).requiresReadRetry, isTrue);
      expect(taskRefreshes, 1);
      expect(codRefreshes, 1);
      expect(repository.commands, hasLength(1));

      await vm.retry();
      expect(taskRefreshes, 2);
      expect(codRefreshes, 1);
      expect(repository.commands, hasLength(1));
      expect(_state(h.container).requiresReadRetry, isFalse);
    },
  );

  test('terminal COD cache failure overrides an earlier network failure and stops later work', () async {
    var remote = _current();
    final repository = _CompletionRepository()
      ..handler = (_) async {
        remote = _deliveredHistory();
      };
    var taskRefreshes = 0;
    var codRefreshes = 0;
    final h = _harness(
      repository: repository,
      read: (_) async => remote,
      refreshTaskList: () async {
        taskRefreshes++;
        throw const OutboundCommandFailure(OutboundCommandFailureCode.network);
      },
      refreshCod: () async {
        codRefreshes++;
        throw const OutboundCommandFailure(
          OutboundCommandFailureCode.sessionExpired,
        );
      },
    );
    addTearDown(h.container.dispose);
    final vm = await _ready(h.container);
    await vm.submit(
      receivedAllItems: true,
      receivedFullCod: true,
      displayedAmountVnd: 550000,
    );
    expect(taskRefreshes, 1);
    expect(codRefreshes, 1);
    expect(
      _state(h.container).error?.code,
      OutboundCommandFailureCode.sessionExpired,
    );
    expect(_state(h.container).actionsDenied, isTrue);
    expect(_state(h.container).confirmed, isFalse);
    await vm.retry();
    expect(taskRefreshes, 1);
    expect(codRefreshes, 1);
    expect(repository.commands, hasLength(1));
  });

  test('confirmed refresh rejects a regressed current snapshot and hides old details', () async {
    var remote = _current();
    var taskRefreshes = 0;
    var codRefreshes = 0;
    final repository = _CompletionRepository()
      ..handler = (_) async {
        remote = _deliveredHistory();
      };
    final h = _harness(
      repository: repository,
      read: (_) async => remote,
      refreshTaskList: () async => taskRefreshes++,
      refreshCod: () async => codRefreshes++,
    );
    addTearDown(h.container.dispose);
    final vm = await _ready(h.container);
    await vm.submit(
      receivedAllItems: true,
      receivedFullCod: true,
      displayedAmountVnd: 550000,
    );
    expect(_state(h.container).confirmed, isTrue);
    expect(taskRefreshes, 1);
    expect(codRefreshes, 1);

    remote = _current();
    await vm.refresh();
    expect(_state(h.container).confirmed, isFalse);
    expect(_state(h.container).details.hasValue, isFalse);
    expect(
      _state(h.container).error?.code,
      OutboundCommandFailureCode.staleState,
    );
    expect(taskRefreshes, 1);
    expect(codRefreshes, 1);
    expect(repository.commands, hasLength(1));
  });

  test('task cache dependency failure still invokes COD and retries invalidations only', () async {
    var remote = _current();
    var taskRefreshes = 0;
    var codRefreshes = 0;
    final repository = _CompletionRepository()
      ..handler = (_) async {
        remote = _deliveredHistory();
      };
    final h = _harness(
      repository: repository,
      read: (_) async => remote,
      refreshTaskList: () async {
        taskRefreshes++;
        throw const OutboundCommandFailure(
          OutboundCommandFailureCode.dependencyUnavailable,
        );
      },
      refreshCod: () async {
        codRefreshes++;
      },
    );
    addTearDown(h.container.dispose);
    final vm = await _ready(h.container);
    await vm.submit(
      receivedAllItems: true,
      receivedFullCod: true,
      displayedAmountVnd: 550000,
    );
    expect(_state(h.container).confirmed, isTrue);
    expect(_state(h.container).actionsDenied, isFalse);
    expect(_state(h.container).requiresReadRetry, isTrue);
    expect(taskRefreshes, 1);
    expect(codRefreshes, 1);
    expect(repository.commands, hasLength(1));

    await vm.retry();
    expect(taskRefreshes, 2);
    expect(codRefreshes, 1);
    expect(repository.commands, hasLength(1));
  });

  test(
    'permission, stale assignment and dependency failures deny unsafe retry',
    () async {
      for (final code in [
        OutboundCommandFailureCode.permissionDenied,
        OutboundCommandFailureCode.staleAssignment,
        OutboundCommandFailureCode.dependencyUnavailable,
      ]) {
        final repository = _CompletionRepository()
          ..handler = (_) async => throw OutboundCommandFailure(code);
        final h = _harness(
          repository: repository,
          read: (_) async => _current(),
        );
        final vm = await _ready(h.container);
        await vm.submit(
          receivedAllItems: true,
          receivedFullCod: true,
          displayedAmountVnd: 550000,
        );
        final reads = h.reads.length;
        expect(_state(h.container).actionsDenied, isTrue);
        await vm.retry();
        expect(repository.commands, hasLength(1));
        expect(h.reads.length, greaterThanOrEqualTo(reads));
        h.container.dispose();
      }
    },
  );

  test(
    'late read from an old account cannot retain details or invoke callbacks',
    () async {
      final oldRead = Completer<DeliveryTaskDetails>();
      final newRead = Completer<DeliveryTaskDetails>();
      var readCalls = 0;
      final repository = _CompletionRepository();
      final h = _harness(
        repository: repository,
        read: (_) => ++readCalls == 1 ? oldRead.future : newRead.future,
      );
      addTearDown(h.container.dispose);
      final vm = h.container.read(
        fixtureOutboundCompletionViewModelProvider(_taskId).notifier,
      );
      await Future<void>.delayed(Duration.zero);
      final oldSession = _state(h.container).session;
      final newSession = const FixtureOutboundSession(
        userId: 'shipper-b',
        epoch: 2,
        isShipper: true,
      );
      vm.updateSession(newSession);
      expect(
        _state(h.container).details,
        isA<AsyncLoading<DeliveryTaskDetails>>(),
      );
      expect(_state(h.container).session, same(newSession));
      oldRead.complete(_current());
      await Future<void>.delayed(Duration.zero);
      expect(_state(h.container).session, same(newSession));
      expect(_state(h.container).details.hasValue, isFalse);
      expect(oldSession.userId, 'shipper-a');
    },
  );

  test('inactive session starts denied and never submits', () async {
    final repository = _CompletionRepository();
    final h = _harness(
      repository: repository,
      session: const FixtureOutboundSession(
        userId: null,
        epoch: 3,
        isShipper: true,
      ),
      read: (_) async => _current(),
    );
    addTearDown(h.container.dispose);
    final vm = h.container.read(
      fixtureOutboundCompletionViewModelProvider(_taskId).notifier,
    );
    await vm.submit(
      receivedAllItems: true,
      receivedFullCod: true,
      displayedAmountVnd: 550000,
    );
    expect(repository.commands, isEmpty);
    expect(_state(h.container).actionsDenied, isTrue);
    expect(
      _state(h.container).error?.code,
      OutboundCommandFailureCode.sessionExpired,
    );
  });

  test(
    'A to B to A rejects the first A response by revision, not identity alone',
    () async {
      final firstA = Completer<DeliveryTaskDetails>();
      final secondA = Completer<DeliveryTaskDetails>();
      final bRead = Completer<DeliveryTaskDetails>();
      var reads = 0;
      final h = _harness(
        repository: _CompletionRepository(),
        read: (_) {
          reads++;
          return switch (reads) {
            1 => firstA.future,
            2 => bRead.future,
            _ => secondA.future,
          };
        },
      );
      addTearDown(h.container.dispose);
      final vm = h.container.read(
        fixtureOutboundCompletionViewModelProvider(_taskId).notifier,
      );
      await Future<void>.delayed(Duration.zero);
      const sessionA = FixtureOutboundSession(
        userId: 'shipper-a',
        epoch: 1,
        isShipper: true,
      );
      const sessionB = FixtureOutboundSession(
        userId: 'shipper-b',
        epoch: 2,
        isShipper: true,
      );
      vm.updateSession(sessionB);
      vm.updateSession(sessionA);
      firstA.complete(_current());
      await Future<void>.delayed(Duration.zero);
      expect(_state(h.container).details.hasValue, isFalse);
      expect(vm.sessionRevisionForFixture, 3);
      secondA.complete(_current());
      await _settle(h.container, () => _state(h.container).details.hasValue);
      expect(_state(h.container).session, same(sessionA));
      bRead.complete(_current());
    },
  );

  test('late write ACK after provider disposal is ignored', () async {
    final write = Completer<void>();
    final repository = _CompletionRepository()..handler = (_) => write.future;
    final h = _harness(repository: repository, read: (_) async => _current());
    final vm = await _ready(h.container);
    final submit = vm.submit(
      receivedAllItems: true,
      receivedFullCod: true,
      displayedAmountVnd: 550000,
    );
    await Future<void>.delayed(Duration.zero);
    h.container.dispose();
    write.complete();
    await submit;
    expect(repository.commands, hasLength(1));
  });
}
