import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_store/features/deliveries/data/models/outbound_completion_ack_dto.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_completion_command.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_completion_failure.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';
import 'package:sports_store/features/deliveries/domain/repositories/outbound_completion_repository.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/outbound_completion_providers.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/outbound_completion_view_model.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_dto.dart';

import 'fixtures/delivery_dtos.dart';

const _taskId = taskId;
const _requestId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

class _Repository implements OutboundCompletionRepository {
  final commands = <OutboundCompletionCommand>[];
  Future<void> Function(OutboundCompletionCommand)? handler;

  @override
  Future<void> execute(OutboundCompletionCommand command) {
    commands.add(command);
    return handler?.call(command) ?? Future<void>.value();
  }
}

DeliveryTaskDetails _current({String status = 'in_transit'}) {
  return DeliveryTaskDetails(
    task: DeliveryTaskDto.fromJson(
      currentTaskDto(
        status: status,
        acceptedAt: '2026-10-25T09:00:00Z',
        startedAt: '2026-10-25T09:10:00Z',
      ),
    ).toDomain(),
    items: const [],
  );
}

DeliveryTaskDetails _delivered() {
  return DeliveryTaskDetails(
    task: DeliveryTaskDto.fromJson(
      maskedTaskDto(status: 'delivered', scope: 'history'),
    ).toDomain(),
    items: const [],
  );
}

Future<void> _settle(ProviderContainer container, bool Function() done) async {
  for (var i = 0; i < 200; i++) {
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    if (done()) return;
  }
  fail('completion provider did not settle');
}

({
  ProviderContainer container,
  StreamController<OperationalSession> sessions,
  _Repository repository,
  List<bool> taskRefreshes,
  List<bool> codRefreshes,
})
_harness({
  required Future<DeliveryTaskDetails> Function() read,
  Future<void> Function(OutboundCompletionCommand)? execute,
}) {
  final sessions = StreamController<OperationalSession>.broadcast();
  final repository = _Repository()..handler = execute;
  final taskRefreshes = <bool>[];
  final codRefreshes = <bool>[];
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      operationalSessionProvider.overrideWith((ref) => sessions.stream),
      outboundCompletionRepositoryProvider.overrideWithValue(repository),
      outboundCompletionRequestIdProvider.overrideWithValue(() => _requestId),
      outboundCompletionDetailsReloadProvider.overrideWithValue((_) => read()),
      outboundCompletionTaskListReloadProvider.overrideWithValue(() async {
        taskRefreshes.add(true);
      }),
      outboundCompletionCodReloadProvider.overrideWithValue(() async {
        codRefreshes.add(true);
      }),
    ],
  );
  return (
    container: container,
    sessions: sessions,
    repository: repository,
    taskRefreshes: taskRefreshes,
    codRefreshes: codRefreshes,
  );
}

Future<OutboundCompletionViewModel> _ready(ProviderContainer container) async {
  await _settle(container, () {
    final state = container.read(outboundCompletionViewModelProvider(_taskId));
    return state.details.hasValue;
  });
  return container.read(outboundCompletionViewModelProvider(_taskId).notifier);
}

ProviderSubscription<OutboundCompletionState> _listen(
  ProviderContainer container,
) => container.listen(
  outboundCompletionViewModelProvider(_taskId),
  (_, _) {},
  fireImmediately: true,
);

void main() {
  test(
    'definitive conflict reads authoritative state and refreshes both caches',
    () async {
      var remote = _current();
      final h = _harness(
        read: () async => remote,
        execute: (_) async {
          remote = _delivered();
          throw const OutboundCompletionBusinessFailure(
            OutboundCompletionBusinessFailureCode.stateConflict,
          );
        },
      );
      final sub = _listen(h.container);
      addTearDown(() async {
        sub.close();
        h.container.dispose();
        await h.sessions.close();
      });
      h.sessions.add(
        const OperationalSession(userId: 'shipper-a', generation: 1),
      );
      final vm = await _ready(h.container);
      await vm.submit(
        receivedAllItems: true,
        receivedFullCod: true,
        displayedAmountVnd: 550000,
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      final state = h.container.read(
        outboundCompletionViewModelProvider(_taskId),
      );
      expect(state.error, isA<OutboundCompletionBusinessFailure>());
      expect(state.confirmed, isFalse);
      expect(h.taskRefreshes, hasLength(1));
      expect(h.codRefreshes, hasLength(1));
    },
  );

  test(
    'pending then hidden account switch releases the old controller',
    () async {
      final gate = Completer<void>();
      final h = _harness(
        read: () async => _current(),
        execute: (_) => gate.future,
      );
      final sub = _listen(h.container);
      addTearDown(() async {
        h.container.dispose();
        await h.sessions.close();
      });
      h.sessions.add(
        const OperationalSession(userId: 'shipper-a', generation: 1),
      );
      final old = await _ready(h.container);
      final submit = old.submit(
        receivedAllItems: true,
        receivedFullCod: true,
        displayedAmountVnd: 550000,
        sessionRevision: old.sessionRevisionForConfirmation,
      );
      await Future<void>.delayed(Duration.zero);
      sub.close();
      await h.container.pump();
      h.sessions.add(
        const OperationalSession(userId: 'shipper-b', generation: 2),
      );
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
        await h.container.pump();
      }
      gate.complete();
      await submit;
      final resumed = _listen(h.container);
      addTearDown(resumed.close);
      expect(
        h.container.read(outboundCompletionViewModelProvider(_taskId).notifier),
        isNot(same(old)),
      );
    },
  );

  test('completion ACK validates authoritative delivered receipt', () {
    final json = <String, dynamic>{
      'request_id': _requestId,
      'task_id': _taskId,
      'order_id': orderId,
      'event_id': '33333333-3333-4333-8333-333333333333',
      'attempt_number': 1,
      'operation': 'complete',
      'task_status': 'delivered',
      'order_status': 'delivered',
      'collected_amount_vnd': 550000,
      'delivery_attempt_count': 1,
      'completed_at': '2026-10-26T08:00:00Z',
    };
    final command = const OutboundCompletionCommand(
      taskId: _taskId,
      requestId: _requestId,
      receivedAllItems: true,
      reportedCollectedAmountVnd: 550000,
    );
    final dto = OutboundCompletionAckDto.fromJson(json, command: command);
    expect(
      () => OutboundCompletionAckDto.fromJson({
        ...json,
        'collected_amount_vnd': 549999,
      }, command: command),
      throwsA(isA<FormatException>()),
    );
    expect(dto.collectedAmountVnd, 550000);
    expect(dto.committedAt.isUtc, isTrue);
  });

  test(
    'production VM requires both confirmations and exact backend amount',
    () async {
      final sessions = StreamController<OperationalSession>.broadcast();
      var remote = _current();
      final repository = _Repository();
      final listRefreshes = <bool>[];
      final codRefreshes = <bool>[];
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          operationalSessionProvider.overrideWith((ref) => sessions.stream),
          outboundCompletionRepositoryProvider.overrideWithValue(repository),
          outboundCompletionRequestIdProvider.overrideWithValue(
            () => _requestId,
          ),
          outboundCompletionDetailsReloadProvider.overrideWithValue(
            (_) async => remote,
          ),
          outboundCompletionTaskListReloadProvider.overrideWithValue(() async {
            listRefreshes.add(true);
          }),
          outboundCompletionCodReloadProvider.overrideWithValue(() async {
            codRefreshes.add(true);
          }),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await sessions.close();
      });
      final subscription = container.listen(
        outboundCompletionViewModelProvider(_taskId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      sessions.add(
        const OperationalSession(userId: 'shipper-a', generation: 1),
      );
      await _settle(
        container,
        () => container
            .read(outboundCompletionViewModelProvider(_taskId))
            .details
            .hasValue,
      );
      final vm = container.read(
        outboundCompletionViewModelProvider(_taskId).notifier,
      );
      final revision = vm.sessionRevisionForConfirmation;
      await vm.submit(
        receivedAllItems: false,
        receivedFullCod: true,
        displayedAmountVnd: 550000,
        sessionRevision: revision,
      );
      expect(repository.commands, isEmpty);
      await vm.submit(
        receivedAllItems: true,
        receivedFullCod: true,
        displayedAmountVnd: 520000,
        sessionRevision: revision,
      );
      expect(repository.commands, isEmpty);
      repository.handler = (_) async {
        remote = _delivered();
      };
      await vm.submit(
        receivedAllItems: true,
        receivedFullCod: true,
        displayedAmountVnd: 550000,
        sessionRevision: revision,
      );
      final state = container.read(
        outboundCompletionViewModelProvider(_taskId),
      );
      expect(state.confirmed, isTrue);
      expect(repository.commands, hasLength(1));
      expect(listRefreshes, hasLength(1));
      expect(codRefreshes, hasLength(1));
    },
  );

  test(
    'timeout retry reuses one command key and confirms after delivered read',
    () async {
      var remote = _current();
      var calls = 0;
      final h = _harness(
        read: () async => remote,
        execute: (_) async {
          if (calls++ == 0) throw TimeoutException('lost response');
          remote = _delivered();
        },
      );
      final subscription = _listen(h.container);
      addTearDown(() async {
        subscription.close();
        h.container.dispose();
        await h.sessions.close();
      });
      h.sessions.add(
        const OperationalSession(userId: 'shipper-a', generation: 1),
      );
      final vm = await _ready(h.container);
      final revision = vm.sessionRevisionForConfirmation;
      await vm.submit(
        receivedAllItems: true,
        receivedFullCod: true,
        displayedAmountVnd: 550000,
        sessionRevision: revision,
      );
      expect(h.repository.commands, hasLength(1));
      expect(
        h.container
            .read(outboundCompletionViewModelProvider(_taskId))
            .pendingCommand,
        isNotNull,
      );
      await vm.retry();
      final state = h.container.read(
        outboundCompletionViewModelProvider(_taskId),
      );
      expect(h.repository.commands, hasLength(2));
      expect(h.repository.commands.first, same(h.repository.commands.last));
      expect(state.confirmed, isTrue);
    },
  );

  test(
    'ACK read failure retries reads and caches without sending a second write',
    () async {
      var remote = _current();
      var failNextRead = false;
      final h = _harness(
        read: () async {
          if (failNextRead) {
            failNextRead = false;
            throw TimeoutException('read failed');
          }
          return remote;
        },
        execute: (_) async {
          remote = _delivered();
          failNextRead = true;
        },
      );
      final subscription = _listen(h.container);
      addTearDown(() async {
        subscription.close();
        h.container.dispose();
        await h.sessions.close();
      });
      h.sessions.add(
        const OperationalSession(userId: 'shipper-a', generation: 1),
      );
      final vm = await _ready(h.container);
      final revision = vm.sessionRevisionForConfirmation;
      await vm.submit(
        receivedAllItems: true,
        receivedFullCod: true,
        displayedAmountVnd: 550000,
        sessionRevision: revision,
      );
      expect(h.repository.commands, hasLength(1));
      expect(
        h.container
            .read(outboundCompletionViewModelProvider(_taskId))
            .confirmed,
        isFalse,
      );
      await vm.retry();
      expect(h.repository.commands, hasLength(1));
      expect(
        h.container
            .read(outboundCompletionViewModelProvider(_taskId))
            .confirmed,
        isTrue,
      );
    },
  );

  test(
    'hidden ACK keeps the envelope and reconciles when route resumes',
    () async {
      var remote = _current();
      final readGate = Completer<void>();
      var reads = 0;
      final h = _harness(
        read: () async {
          reads++;
          if (reads == 2) await readGate.future;
          return remote;
        },
        execute: (_) async {
          remote = _delivered();
        },
      );
      final subscription = _listen(h.container);
      addTearDown(() async {
        subscription.close();
        h.container.dispose();
        await h.sessions.close();
      });
      h.sessions.add(
        const OperationalSession(userId: 'shipper-a', generation: 1),
      );
      final vm = await _ready(h.container);
      final submit = vm.submit(
        receivedAllItems: true,
        receivedFullCod: true,
        displayedAmountVnd: 550000,
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      await Future<void>.delayed(Duration.zero);
      await _settle(h.container, () => reads >= 2);
      subscription.close();
      await h.container.pump();
      readGate.complete();
      await submit;
      final hidden = h.container.read(
        outboundCompletionViewModelProvider(_taskId),
      );
      expect(hidden.awaitingAuthoritativeRead, isTrue);
      final resumed = _listen(h.container);
      addTearDown(resumed.close);
      await _settle(
        h.container,
        () => h.container
            .read(outboundCompletionViewModelProvider(_taskId))
            .confirmed,
      );
      expect(h.repository.commands, hasLength(1));
    },
  );

  test(
    'account switch clears pending completion and ignores late response',
    () async {
      final gate = Completer<void>();
      final h = _harness(
        read: () async => _current(),
        execute: (_) => gate.future,
      );
      final subscription = _listen(h.container);
      addTearDown(() async {
        subscription.close();
        h.container.dispose();
        await h.sessions.close();
      });
      h.sessions.add(
        const OperationalSession(userId: 'shipper-a', generation: 1),
      );
      final vm = await _ready(h.container);
      final oldRevision = vm.sessionRevisionForConfirmation;
      final submit = vm.submit(
        receivedAllItems: true,
        receivedFullCod: true,
        displayedAmountVnd: 550000,
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      await Future<void>.delayed(Duration.zero);
      h.sessions.add(
        const OperationalSession(userId: 'shipper-b', generation: 2),
      );
      await _settle(
        h.container,
        () =>
            vm.sessionRevisionForConfirmation > oldRevision &&
            h.container
                    .read(outboundCompletionViewModelProvider(_taskId))
                    .pendingCommand ==
                null,
      );
      gate.complete();
      await submit;
      expect(
        h.container
            .read(outboundCompletionViewModelProvider(_taskId))
            .pendingCommand,
        isNull,
      );
    },
  );

  test(
    'idle completion provider releases keepalive and does not retain details',
    () async {
      final h = _harness(read: () async => _current());
      final first = _listen(h.container);
      addTearDown(() async {
        first.close();
        h.container.dispose();
        await h.sessions.close();
      });
      h.sessions.add(
        const OperationalSession(userId: 'shipper-a', generation: 1),
      );
      await _ready(h.container);
      first.close();
      await h.container.pump();
      await h.container.pump();
      final second = _listen(h.container);
      addTearDown(second.close);
      h.sessions.add(
        const OperationalSession(userId: 'shipper-a', generation: 2),
      );
      await _settle(
        h.container,
        () => h.container
            .read(outboundCompletionViewModelProvider(_taskId))
            .details
            .hasValue,
      );
      final state = h.container.read(
        outboundCompletionViewModelProvider(_taskId),
      );
      expect(state.pendingCommand, isNull);
      expect(state.confirmed, isFalse);
    },
  );

  test(
    'business failure is typed and does not manufacture a delivered state',
    () {
      const failure = OutboundCompletionBusinessFailure(
        OutboundCompletionBusinessFailureCode.amountMismatch,
      );
      expect(failure.code, OutboundCommandFailureCode.staleState);
      expect(failure.message, contains('COD'));
    },
  );
}
