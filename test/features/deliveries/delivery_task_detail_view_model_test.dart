import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_dto.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_query.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';
import 'package:sports_store/features/deliveries/domain/repositories/delivery_repository.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_providers.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_task_detail_view_model.dart';

import 'fixtures/delivery_dtos.dart';

final class _FixtureRepository implements DeliveryRepository {
  _FixtureRepository(this.read);

  final Future<DeliveryTaskDetails> Function(String taskId) read;
  final calls = <String>[];

  @override
  Future<DeliveryTaskDetails> getTaskDetails(String taskId) {
    calls.add(taskId);
    return read(taskId);
  }

  @override
  Future<List<DeliveryTaskSnapshot>> listTasks() =>
      Future.error(UnimplementedError());

  @override
  Future<DeliveryTaskPage> queryTasks(DeliveryTaskQuery query) =>
      Future.error(UnimplementedError());

  @override
  Future<DeliveryTaskSnapshot> getTask(String taskId) =>
      Future.error(UnimplementedError());
}

OperationalSession _session(String? userId, int generation) =>
    OperationalSession(userId: userId, generation: generation);

DeliveryTaskDetails _details({required String taskId, int? amount = 30000}) {
  final task = DeliveryTaskDto.fromJson(
    currentTaskDto(task: taskId, amount: amount ?? 30000),
  ).toDomain();
  return DeliveryTaskDetails(task: task, items: const []);
}

Future<void> _settle(ProviderContainer container, bool Function() done) async {
  for (var index = 0; index < 200; index++) {
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    if (done()) return;
  }
  fail('Provider did not reach the expected state');
}

({
  ProviderContainer container,
  StreamController<OperationalSession> sessions,
  ProviderSubscription<AsyncValue<DeliveryTaskDetails>> subscription,
})
_harness(_FixtureRepository repository, String taskId) {
  final sessions = StreamController<OperationalSession>.broadcast();
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      deliveryRepositoryProvider.overrideWithValue(repository),
      operationalSessionProvider.overrideWith((ref) => sessions.stream),
    ],
  );
  final subscription = container.listen(
    deliveryTaskDetailViewModelProvider(taskId),
    (_, _) {},
    fireImmediately: true,
  );
  return (container: container, sessions: sessions, subscription: subscription);
}

void main() {
  test('publishes loading then authorized detail data', () async {
    final repository = _FixtureRepository(
      (taskId) async => _details(taskId: taskId),
    );
    final h = _harness(repository, taskId);
    addTearDown(() async {
      h.subscription.close();
      h.container.dispose();
      await h.sessions.close();
    });

    expect(
      h.container.read(deliveryTaskDetailViewModelProvider(taskId)),
      isA<AsyncLoading<DeliveryTaskDetails>>(),
    );
    h.sessions.add(_session('shipper-a', 1));
    await _settle(
      h.container,
      () => h.container
          .read(deliveryTaskDetailViewModelProvider(taskId))
          .hasValue,
    );

    final value = h.container
        .read(deliveryTaskDetailViewModelProvider(taskId))
        .requireValue;
    expect(value.task.taskId, taskId);
    expect(value.task.amountToCollectVnd, 30000);
    expect(repository.calls, [taskId]);
  });

  test(
    'maps repository failures and retry never reports fake success',
    () async {
      var attempt = 0;
      final retryResult = Completer<DeliveryTaskDetails>();
      final repository = _FixtureRepository((taskId) async {
        attempt++;
        if (attempt == 1) {
          throw const OperationalFailure(OperationalFailureCode.network);
        }
        return retryResult.future;
      });
      final h = _harness(repository, taskId);
      addTearDown(() async {
        h.subscription.close();
        h.container.dispose();
        await h.sessions.close();
      });
      h.sessions.add(_session('shipper-a', 1));
      await _settle(
        h.container,
        () => h.container
            .read(deliveryTaskDetailViewModelProvider(taskId))
            .hasError,
      );
      final failed = h.container.read(
        deliveryTaskDetailViewModelProvider(taskId),
      );
      expect(failed.asData, isNull);
      expect(
        (failed.error! as OperationalFailure).code,
        OperationalFailureCode.network,
      );

      final retry = h.container
          .read(deliveryTaskDetailViewModelProvider(taskId).notifier)
          .refresh();
      await Future<void>.delayed(Duration.zero);
      await h.container.pump();
      expect(
        h.container.read(deliveryTaskDetailViewModelProvider(taskId)).isLoading,
        isTrue,
      );
      retryResult.complete(_details(taskId: taskId));
      await retry;
      await _settle(
        h.container,
        () => h.container
            .read(deliveryTaskDetailViewModelProvider(taskId))
            .hasValue,
      );
      expect(attempt, 2);
    },
  );

  test(
    'refresh clears the previous projection until the new read completes',
    () async {
      final first = _details(taskId: taskId);
      final second = _details(taskId: taskId, amount: 45000);
      final pending = Completer<DeliveryTaskDetails>();
      var call = 0;
      final repository = _FixtureRepository((_) async {
        call++;
        if (call == 1) return first;
        return pending.future;
      });
      final h = _harness(repository, taskId);
      addTearDown(() async {
        h.subscription.close();
        h.container.dispose();
        await h.sessions.close();
      });
      h.sessions.add(_session('shipper-a', 1));
      await _settle(
        h.container,
        () => h.container
            .read(deliveryTaskDetailViewModelProvider(taskId))
            .hasValue,
      );
      expect(
        h.container
            .read(deliveryTaskDetailViewModelProvider(taskId))
            .requireValue
            .task
            .amountToCollectVnd,
        30000,
      );

      final refresh = h.container
          .read(deliveryTaskDetailViewModelProvider(taskId).notifier)
          .refresh();
      await Future<void>.delayed(Duration.zero);
      await h.container.pump();
      expect(
        h.container.read(deliveryTaskDetailViewModelProvider(taskId)).asData,
        isNull,
      );
      pending.complete(second);
      await refresh;
      await _settle(
        h.container,
        () => h.container
            .read(deliveryTaskDetailViewModelProvider(taskId))
            .hasValue,
      );
      expect(
        h.container
            .read(deliveryTaskDetailViewModelProvider(taskId))
            .requireValue
            .task
            .amountToCollectVnd,
        45000,
      );
    },
  );

  test('refresh Future returns with settled success', () async {
    final pending = Completer<DeliveryTaskDetails>();
    var calls = 0;
    final repository = _FixtureRepository((id) async {
      calls++;
      if (calls == 1) return _details(taskId: id);
      return pending.future;
    });
    final h = _harness(repository, taskId);
    addTearDown(() async {
      h.subscription.close();
      h.container.dispose();
      await h.sessions.close();
    });
    h.sessions.add(_session('shipper-a', 1));
    await _settle(
      h.container,
      () => h.container
          .read(deliveryTaskDetailViewModelProvider(taskId))
          .hasValue,
    );
    final refresh = h.container
        .read(deliveryTaskDetailViewModelProvider(taskId).notifier)
        .refresh();
    var refreshCompleted = false;
    refresh.whenComplete(() => refreshCompleted = true);
    await Future<void>.delayed(Duration.zero);
    await h.container.pump();
    expect(refreshCompleted, isFalse);
    pending.complete(_details(taskId: taskId, amount: 45000));
    await refresh;
    expect(
      h.container.read(deliveryTaskDetailViewModelProvider(taskId)).hasValue,
      isTrue,
    );
    expect(
      h.container
          .read(deliveryTaskDetailViewModelProvider(taskId))
          .requireValue
          .task
          .amountToCollectVnd,
      45000,
    );
  });

  test('refresh waits for and exposes a denied reassignment result', () async {
    final first = _details(taskId: taskId);
    var calls = 0;
    final repository = _FixtureRepository((id) async {
      calls++;
      if (calls == 1) return first;
      throw const OperationalFailure(OperationalFailureCode.staleAssignment);
    });
    final h = _harness(repository, taskId);
    addTearDown(() async {
      h.subscription.close();
      h.container.dispose();
      await h.sessions.close();
    });
    h.sessions.add(_session('shipper-a', 1));
    await _settle(
      h.container,
      () => h.container
          .read(deliveryTaskDetailViewModelProvider(taskId))
          .hasValue,
    );

    await h.container
        .read(deliveryTaskDetailViewModelProvider(taskId).notifier)
        .refresh();
    expect(
      h.container.read(deliveryTaskDetailViewModelProvider(taskId)).hasError,
      isTrue,
    );
    await _settle(
      h.container,
      () => h.container
          .read(deliveryTaskDetailViewModelProvider(taskId))
          .hasError,
    );
    final state = h.container.read(deliveryTaskDetailViewModelProvider(taskId));
    expect(state.asData, isNull);
    expect(
      (state.error! as OperationalFailure).code,
      OperationalFailureCode.staleAssignment,
    );
    expect(calls, 2);
  });

  test('detail providers stay scoped to their task IDs', () async {
    const taskA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    const taskB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    final repository = _FixtureRepository((id) async {
      return _details(taskId: id, amount: id == taskA ? 41000 : 52000);
    });
    final sessions = StreamController<OperationalSession>.broadcast();
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        deliveryRepositoryProvider.overrideWithValue(repository),
        operationalSessionProvider.overrideWith((ref) => sessions.stream),
      ],
    );
    final subA = container.listen(
      deliveryTaskDetailViewModelProvider(taskA),
      (_, _) {},
      fireImmediately: true,
    );
    final subB = container.listen(
      deliveryTaskDetailViewModelProvider(taskB),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() async {
      subA.close();
      subB.close();
      container.dispose();
      await sessions.close();
    });
    sessions.add(_session('shipper-a', 1));
    await _settle(
      container,
      () =>
          container.read(deliveryTaskDetailViewModelProvider(taskA)).hasValue &&
          container.read(deliveryTaskDetailViewModelProvider(taskB)).hasValue,
    );
    expect(repository.calls, containsAllInOrder([taskA, taskB]));

    await container
        .read(deliveryTaskDetailViewModelProvider(taskA).notifier)
        .refresh();
    await _settle(
      container,
      () => repository.calls.where((id) => id == taskA).length == 2,
    );
    expect(repository.calls.where((id) => id == taskB).length, 1);
  });

  test('late detail completion after disposal is ignored', () async {
    final pending = Completer<DeliveryTaskDetails>();
    final repository = _FixtureRepository((_) => pending.future);
    final h = _harness(repository, taskId);
    h.sessions.add(_session('shipper-a', 1));
    await _settle(h.container, () => repository.calls.length == 1);
    h.subscription.close();
    h.container.dispose();
    pending.complete(_details(taskId: taskId, amount: 99000));
    await Future<void>.delayed(Duration.zero);
    await h.sessions.close();
    expect(repository.calls, [taskId]);
  });

  test(
    'refresh after session expiry never starts an unauthorized read',
    () async {
      final repository = _FixtureRepository((id) async {
        return _details(taskId: id);
      });
      final h = _harness(repository, taskId);
      addTearDown(() async {
        h.subscription.close();
        h.container.dispose();
        await h.sessions.close();
      });
      h.sessions.add(
        const OperationalSession(
          userId: null,
          generation: 1,
          failure: OperationalFailure(OperationalFailureCode.sessionExpired),
        ),
      );
      await _settle(
        h.container,
        () => h.container
            .read(deliveryTaskDetailViewModelProvider(taskId))
            .hasError,
      );

      await h.container
          .read(deliveryTaskDetailViewModelProvider(taskId).notifier)
          .refresh();
      expect(repository.calls, isEmpty);
      final state = h.container.read(
        deliveryTaskDetailViewModelProvider(taskId),
      );
      expect(state.asData, isNull);
      expect(
        (state.error! as OperationalFailure).code,
        OperationalFailureCode.sessionExpired,
      );
    },
  );

  test('in-flight refresh completes when the account epoch changes', () async {
    final pendingRefresh = Completer<DeliveryTaskDetails>();
    var calls = 0;
    final repository = _FixtureRepository((id) async {
      calls++;
      if (calls == 1) return _details(taskId: id, amount: 30000);
      if (calls == 2) return pendingRefresh.future;
      return _details(taskId: id, amount: 64000);
    });
    final h = _harness(repository, taskId);
    addTearDown(() async {
      h.subscription.close();
      h.container.dispose();
      await h.sessions.close();
    });
    h.sessions.add(_session('shipper-a', 1));
    await _settle(
      h.container,
      () => h.container
          .read(deliveryTaskDetailViewModelProvider(taskId))
          .hasValue,
    );

    final refresh = h.container
        .read(deliveryTaskDetailViewModelProvider(taskId).notifier)
        .refresh();
    await _settle(h.container, () => calls == 2);
    h.sessions.add(_session('shipper-b', 2));

    await refresh;
    await _settle(
      h.container,
      () =>
          calls == 3 &&
          h.container
              .read(deliveryTaskDetailViewModelProvider(taskId))
              .hasValue,
    );
    expect(
      h.container
          .read(deliveryTaskDetailViewModelProvider(taskId))
          .requireValue
          .task
          .amountToCollectVnd,
      64000,
    );

    // The superseded account-A result cannot overwrite account B.
    pendingRefresh.complete(_details(taskId: taskId, amount: 99000));
    await h.container.pump();
    expect(
      h.container
          .read(deliveryTaskDetailViewModelProvider(taskId))
          .requireValue
          .task
          .amountToCollectVnd,
      64000,
    );
  });

  test(
    'a new session object supersedes refresh even with matching fields',
    () async {
      final pendingRefresh = Completer<DeliveryTaskDetails>();
      var calls = 0;
      final repository = _FixtureRepository((id) async {
        calls++;
        if (calls == 1) return _details(taskId: id, amount: 30000);
        if (calls == 2) return pendingRefresh.future;
        return _details(taskId: id, amount: 71000);
      });
      final h = _harness(repository, taskId);
      addTearDown(() async {
        h.subscription.close();
        h.container.dispose();
        await h.sessions.close();
      });
      h.sessions.add(_session('shipper-a', 1));
      await _settle(
        h.container,
        () => h.container
            .read(deliveryTaskDetailViewModelProvider(taskId))
            .hasValue,
      );

      final refresh = h.container
          .read(deliveryTaskDetailViewModelProvider(taskId).notifier)
          .refresh();
      await _settle(h.container, () => calls == 2);
      // Same user/generation, but a new session object means a new family key.
      h.sessions.add(_session('shipper-a', 1));

      await refresh;
      await _settle(
        h.container,
        () =>
            calls == 3 &&
            h.container
                .read(deliveryTaskDetailViewModelProvider(taskId))
                .hasValue,
      );
      expect(
        h.container
            .read(deliveryTaskDetailViewModelProvider(taskId))
            .requireValue
            .task
            .amountToCollectVnd,
        71000,
      );
      pendingRefresh.complete(_details(taskId: taskId, amount: 99000));
      await h.container.pump();
      expect(
        h.container
            .read(deliveryTaskDetailViewModelProvider(taskId))
            .requireValue
            .task
            .amountToCollectVnd,
        71000,
      );
    },
  );

  test(
    'in-flight refresh completes on logout and keeps old data hidden',
    () async {
      final pendingRefresh = Completer<DeliveryTaskDetails>();
      var calls = 0;
      final repository = _FixtureRepository((id) async {
        calls++;
        if (calls == 1) return _details(taskId: id, amount: 30000);
        return pendingRefresh.future;
      });
      final h = _harness(repository, taskId);
      addTearDown(() async {
        h.subscription.close();
        h.container.dispose();
        await h.sessions.close();
      });
      h.sessions.add(_session('shipper-a', 1));
      await _settle(
        h.container,
        () => h.container
            .read(deliveryTaskDetailViewModelProvider(taskId))
            .hasValue,
      );
      final refresh = h.container
          .read(deliveryTaskDetailViewModelProvider(taskId).notifier)
          .refresh();
      await _settle(h.container, () => calls == 2);
      h.sessions.add(
        const OperationalSession(
          userId: null,
          generation: 2,
          failure: OperationalFailure(OperationalFailureCode.sessionExpired),
        ),
      );

      await refresh;
      await _settle(
        h.container,
        () => h.container
            .read(deliveryTaskDetailViewModelProvider(taskId))
            .hasError,
      );
      final state = h.container.read(
        deliveryTaskDetailViewModelProvider(taskId),
      );
      expect(state.asData, isNull);
      expect(
        (state.error! as OperationalFailure).code,
        OperationalFailureCode.sessionExpired,
      );
      pendingRefresh.complete(_details(taskId: taskId, amount: 99000));
      await h.container.pump();
      expect(
        h.container.read(deliveryTaskDetailViewModelProvider(taskId)).asData,
        isNull,
      );
    },
  );

  test('in-flight refresh completes when its provider is disposed', () async {
    final pendingRefresh = Completer<DeliveryTaskDetails>();
    var calls = 0;
    final repository = _FixtureRepository((id) async {
      calls++;
      if (calls == 1) return _details(taskId: id);
      return pendingRefresh.future;
    });
    final h = _harness(repository, taskId);
    h.sessions.add(_session('shipper-a', 1));
    await _settle(
      h.container,
      () => h.container
          .read(deliveryTaskDetailViewModelProvider(taskId))
          .hasValue,
    );
    final refresh = h.container
        .read(deliveryTaskDetailViewModelProvider(taskId).notifier)
        .refresh();
    await _settle(h.container, () => calls == 2);
    h.subscription.close();
    h.container.dispose();

    await refresh.timeout(const Duration(seconds: 1));
    pendingRefresh.complete(_details(taskId: taskId, amount: 99000));
    await h.sessions.close();
  });

  test('account/session changes discard old detail and late result', () async {
    final lateA = Completer<DeliveryTaskDetails>();
    final detailsB = _details(taskId: taskId, amount: 60000);
    var call = 0;
    final repository = _FixtureRepository((_) async {
      call++;
      if (call == 1) return lateA.future;
      return detailsB;
    });
    final h = _harness(repository, taskId);
    addTearDown(() async {
      h.subscription.close();
      h.container.dispose();
      await h.sessions.close();
    });
    h.sessions.add(_session('shipper-a', 1));
    await _settle(h.container, () => call == 1);
    h.sessions.add(_session('shipper-b', 2));
    await _settle(
      h.container,
      () =>
          call == 2 &&
          h.container
              .read(deliveryTaskDetailViewModelProvider(taskId))
              .hasValue,
    );
    expect(
      h.container
          .read(deliveryTaskDetailViewModelProvider(taskId))
          .requireValue
          .task
          .amountToCollectVnd,
      60000,
    );
    lateA.complete(_details(taskId: taskId, amount: 30000));
    await h.container.pump();
    expect(
      h.container
          .read(deliveryTaskDetailViewModelProvider(taskId))
          .requireValue
          .task
          .amountToCollectVnd,
      60000,
    );

    h.sessions.add(
      const OperationalSession(
        userId: null,
        generation: 3,
        failure: OperationalFailure(OperationalFailureCode.sessionExpired),
      ),
    );
    await _settle(
      h.container,
      () => h.container
          .read(deliveryTaskDetailViewModelProvider(taskId))
          .hasError,
    );
    expect(
      h.container.read(deliveryTaskDetailViewModelProvider(taskId)).asData,
      isNull,
    );
  });
}
