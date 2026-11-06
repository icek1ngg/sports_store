import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_dto.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_query.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';
import 'package:sports_store/features/deliveries/domain/repositories/delivery_repository.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_providers.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_task_list_view_model.dart';

import 'fixtures/delivery_dtos.dart';

final class _FakeRepository implements DeliveryRepository {
  final calls = <DeliveryTaskQuery>[];
  final responses = <Future<DeliveryTaskPage> Function(DeliveryTaskQuery)>[];

  @override
  Future<DeliveryTaskPage> queryTasks(DeliveryTaskQuery query) {
    calls.add(query);
    if (responses.isEmpty) {
      return Future.error(
        const OperationalFailure(OperationalFailureCode.unexpected),
      );
    }
    return responses.removeAt(0)(query);
  }

  @override
  Future<List<DeliveryTaskSnapshot>> listTasks() => Future.value(const []);

  @override
  Future<DeliveryTaskSnapshot> getTask(String taskId) =>
      Future.error(const OperationalFailure(OperationalFailureCode.unexpected));

  @override
  Future<DeliveryTaskDetails> getTaskDetails(String taskId) =>
      Future.error(const OperationalFailure(OperationalFailureCode.unexpected));
}

DeliveryTaskSnapshot _task({
  required String id,
  String kind = 'outbound',
  String status = 'assigned',
}) {
  return DeliveryTaskDto.fromJson(
    currentTaskDto(task: id, kind: kind, status: status),
  ).toDomain();
}

String _id(int value) =>
    '11111111-1111-4111-8111-${value.toRadixString(16).padLeft(12, '0')}';

DeliveryTaskPage _page({
  List<DeliveryTaskSnapshot> items = const [],
  String? nextCursor,
  int? filteredTotal,
  int? waiting,
  int? inTransit,
  int? completed,
  int? ungrouped,
}) {
  final total = filteredTotal ?? items.length;
  return DeliveryTaskPage(
    items: items,
    nextCursor: nextCursor,
    filteredTotal: total,
    counts: DeliveryTaskCounts(
      waiting: waiting ?? total,
      inTransit: inTransit ?? 0,
      completed: completed ?? 0,
      ungrouped: ungrouped ?? 0,
    ),
    asOf: DateTime.utc(2026, 10, 23, 3),
  );
}

Future<void> _settle(ProviderContainer container, bool Function() done) async {
  for (var i = 0; i < 200; i++) {
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    if (done()) {
      // A call-count predicate only proves that the request was started. Give
      // an immediately completed fixture one more turn to publish its page.
      await Future<void>.delayed(Duration.zero);
      await container.pump();
      return;
    }
  }
  fail('Provider did not reach the expected state');
}

({
  ProviderContainer container,
  StreamController<OperationalSession> sessions,
  ProviderSubscription<DeliveryTaskListState> subscription,
})
_harness(_FakeRepository repository) {
  final sessions = StreamController<OperationalSession>.broadcast();
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      deliveryRepositoryProvider.overrideWithValue(repository),
      operationalSessionProvider.overrideWith((ref) => sessions.stream),
    ],
  );
  final subscription = container.listen(
    deliveryTaskListViewModelProvider,
    (_, _) {},
    fireImmediately: true,
  );
  return (container: container, sessions: sessions, subscription: subscription);
}

OperationalSession session(String user, int generation) =>
    OperationalSession(userId: user, generation: generation);

void main() {
  test(
    'forwards combined search and filters and preserves server counts',
    () async {
      final repository = _FakeRepository();
      repository.responses.add((_) async => _page());
      repository.responses.add((_) async => _page());
      repository.responses.add((_) async => _page());
      repository.responses.add((query) async {
        expect(query.query, 'Nguyen');
        expect(query.kind, DeliveryTaskKind.outbound);
        expect(query.stateGroup, DeliveryTaskStateGroup.waiting);
        return _page(
          items: List.generate(7, (index) => _task(id: _id(index + 1))),
          filteredTotal: 7,
          waiting: 7,
          inTransit: 4,
          completed: 2,
          ungrouped: 1,
        );
      });
      final h = _harness(repository);
      addTearDown(() async {
        h.subscription.close();
        h.container.dispose();
        await h.sessions.close();
      });
      h.sessions.add(session('shipper-a', 1));
      await _settle(h.container, () => repository.calls.length == 1);

      final viewModel = h.container.read(
        deliveryTaskListViewModelProvider.notifier,
      );
      await viewModel.setSearch(' Nguyen ');
      await viewModel.setKind(DeliveryTaskKind.outbound);
      await viewModel.setStateGroup(DeliveryTaskStateGroup.waiting);

      final state = h.container.read(deliveryTaskListViewModelProvider);
      expect(state.query.query, 'Nguyen');
      expect(state.query.kind, DeliveryTaskKind.outbound);
      expect(state.query.stateGroup, DeliveryTaskStateGroup.waiting);
      expect(state.filteredTotal, 7);
      expect(
        state.counts,
        const DeliveryTaskCounts(
          waiting: 7,
          inTransit: 4,
          completed: 2,
          ungrouped: 1,
        ),
      );
    },
  );

  test('appends complete-dataset pages without duplicate task IDs', () async {
    final repository = _FakeRepository();
    final first = _task(id: taskId);
    final second = _task(id: '11111111-1111-4111-8111-111111111112');
    final third = _task(id: '11111111-1111-4111-8111-111111111113');
    final secondPage = List.generate(
      20,
      (index) => index == 0 ? second : _task(id: _id(index + 100)),
    );
    repository.responses
      ..add(
        (_) async => _page(
          items: List.generate(
            20,
            (index) => index == 0 ? first : _task(id: _id(index + 10)),
          ),
          nextCursor: 'cursor-1',
          filteredTotal: 41,
          waiting: 41,
        ),
      )
      ..add((query) async {
        expect(query.cursor, 'cursor-1');
        return _page(
          items: secondPage,
          nextCursor: 'cursor-2',
          filteredTotal: 41,
          waiting: 41,
        );
      })
      ..add((query) async {
        expect(query.cursor, 'cursor-2');
        return _page(items: [third], filteredTotal: 41, waiting: 41);
      });
    final h = _harness(repository);
    addTearDown(() async {
      h.subscription.close();
      h.container.dispose();
      await h.sessions.close();
    });
    h.sessions.add(session('shipper-a', 1));
    await _settle(h.container, () => repository.calls.length == 1);
    await h.container
        .read(deliveryTaskListViewModelProvider.notifier)
        .loadMore();
    await h.container
        .read(deliveryTaskListViewModelProvider.notifier)
        .loadMore();

    final state = h.container.read(deliveryTaskListViewModelProvider);
    expect(state.items, hasLength(41));
    expect(state.items.last.taskId, third.taskId);
    expect(state.nextCursor, isNull);
    expect(state.filteredTotal, 41);
  });

  test(
    'late result from an older search cannot replace the newest query',
    () async {
      final repository = _FakeRepository();
      final oldResult = Completer<DeliveryTaskPage>();
      final newResult = Completer<DeliveryTaskPage>();
      repository.responses
        ..add((_) => oldResult.future)
        ..add((query) {
          expect(query.query, 'new');
          return newResult.future;
        });
      final h = _harness(repository);
      addTearDown(() async {
        h.subscription.close();
        h.container.dispose();
        await h.sessions.close();
      });
      h.sessions.add(session('shipper-a', 1));
      await _settle(h.container, () => repository.calls.length == 1);
      final changing = h.container
          .read(deliveryTaskListViewModelProvider.notifier)
          .setSearch('new');
      await _settle(h.container, () => repository.calls.length == 2);
      newResult.complete(_page(items: [_task(id: taskId)]));
      await changing;
      await h.container.pump();
      oldResult.complete(
        _page(items: [_task(id: '11111111-1111-4111-8111-111111111113')]),
      );
      await h.container.pump();
      expect(
        h.container.read(deliveryTaskListViewModelProvider).items.single.taskId,
        taskId,
      );
    },
  );

  test(
    'refresh invalidates an in-flight load-more after returning from MH11',
    () async {
      final repository = _FakeRepository();
      final lateMore = Completer<DeliveryTaskPage>();
      final freshResult = Completer<DeliveryTaskPage>();
      final refreshed = _task(id: '11111111-1111-4111-8111-111111111114');
      repository.responses
        ..add(
          (_) async => _page(
            items: List.generate(20, (index) => _task(id: _id(index + 1))),
            nextCursor: 'cursor-1',
            filteredTotal: 21,
            waiting: 21,
          ),
        )
        ..add((_) => lateMore.future)
        ..add((_) => freshResult.future);
      final h = _harness(repository);
      addTearDown(() async {
        h.subscription.close();
        h.container.dispose();
        await h.sessions.close();
      });
      h.sessions.add(session('shipper-a', 1));
      await _settle(h.container, () => repository.calls.length == 1);
      final vm = h.container.read(deliveryTaskListViewModelProvider.notifier);
      final loadingMore = vm.loadMore();
      await _settle(h.container, () => repository.calls.length == 2);
      final refreshing = vm.refresh();
      expect(
        h.container.read(deliveryTaskListViewModelProvider).isLoading,
        isTrue,
      );
      lateMore.complete(
        _page(
          items: [_task(id: '11111111-1111-4111-8111-111111111115')],
          filteredTotal: 21,
          waiting: 21,
        ),
      );
      await loadingMore;
      final state = h.container.read(deliveryTaskListViewModelProvider);
      expect(state.items, isEmpty);
      freshResult.complete(
        _page(items: [refreshed], filteredTotal: 1, waiting: 1),
      );
      await refreshing;
      expect(
        h.container.read(deliveryTaskListViewModelProvider).items.single.taskId,
        refreshed.taskId,
      );
    },
  );

  test(
    'account switch clears old rows and logout exposes typed expiry',
    () async {
      final repository = _FakeRepository();
      final a = Completer<DeliveryTaskPage>();
      repository.responses
        ..add((_) => a.future)
        ..add(
          (_) async =>
              _page(items: [_task(id: '11111111-1111-4111-8111-111111111116')]),
        );
      final h = _harness(repository);
      addTearDown(() async {
        h.subscription.close();
        h.container.dispose();
        await h.sessions.close();
      });
      h.sessions.add(session('shipper-a', 1));
      await _settle(h.container, () => repository.calls.length == 1);
      h.sessions.add(session('shipper-b', 2));
      await _settle(
        h.container,
        () =>
            repository.calls.length == 2 &&
            h.container
                .read(deliveryTaskListViewModelProvider)
                .items
                .isNotEmpty,
      );
      expect(
        h.container.read(deliveryTaskListViewModelProvider).items.single.taskId,
        '11111111-1111-4111-8111-111111111116',
      );
      a.complete(_page(items: [_task(id: taskId)]));
      await h.container.pump();
      expect(
        h.container.read(deliveryTaskListViewModelProvider).items.single.taskId,
        '11111111-1111-4111-8111-111111111116',
      );

      h.sessions.add(const OperationalSession(userId: null, generation: 3));
      await _settle(
        h.container,
        () => h.container.read(deliveryTaskListViewModelProvider).error != null,
      );
      final state = h.container.read(deliveryTaskListViewModelProvider);
      expect(state.items, isEmpty);
      expect(state.error?.code, OperationalFailureCode.sessionExpired);
    },
  );

  test('page errors and load-more network errors remain typed', () async {
    final repository = _FakeRepository();
    repository.responses
      ..add(
        (_) => Future.error(
          const OperationalFailure(OperationalFailureCode.network),
        ),
      )
      ..add(
        (_) async => _page(
          items: List.generate(20, (index) => _task(id: _id(index + 1))),
          nextCursor: 'cursor-1',
          filteredTotal: 21,
          waiting: 21,
        ),
      )
      ..add(
        (_) => Future.error(
          const OperationalFailure(OperationalFailureCode.network),
        ),
      );
    final h = _harness(repository);
    addTearDown(() async {
      h.subscription.close();
      h.container.dispose();
      await h.sessions.close();
    });
    h.sessions.add(session('shipper-a', 1));
    await _settle(
      h.container,
      () => h.container.read(deliveryTaskListViewModelProvider).error != null,
    );
    expect(
      h.container.read(deliveryTaskListViewModelProvider).error?.code,
      OperationalFailureCode.network,
    );
    await h.container
        .read(deliveryTaskListViewModelProvider.notifier)
        .refresh();
    await _settle(
      h.container,
      () => h.container.read(deliveryTaskListViewModelProvider).hasMore,
    );
    await h.container
        .read(deliveryTaskListViewModelProvider.notifier)
        .loadMore();
    final state = h.container.read(deliveryTaskListViewModelProvider);
    expect(state.items, hasLength(20));
    expect(state.loadMoreError?.code, OperationalFailureCode.network);
    expect(state.nextCursor, 'cursor-1');
  });

  test('count drift restarts once with the same filters', () async {
    final repository = _FakeRepository();
    repository.responses
      ..add(
        (_) async => _page(
          items: List.generate(20, (index) => _task(id: _id(index + 1))),
          nextCursor: 'cursor-1',
          filteredTotal: 21,
          waiting: 21,
        ),
      )
      ..add(
        (_) async => _page(
          items: [_task(id: '11111111-1111-4111-8111-111111111117')],
          filteredTotal: 22,
          waiting: 22,
        ),
      )
      ..add((query) async {
        expect(query.cursor, isNull);
        return _page(
          items: [_task(id: '11111111-1111-4111-8111-111111111118')],
          filteredTotal: 1,
          waiting: 1,
        );
      });
    final h = _harness(repository);
    addTearDown(() async {
      h.subscription.close();
      h.container.dispose();
      await h.sessions.close();
    });
    h.sessions.add(session('shipper-a', 1));
    await _settle(h.container, () => repository.calls.length == 1);
    await h.container
        .read(deliveryTaskListViewModelProvider.notifier)
        .loadMore();
    await _settle(h.container, () => repository.calls.length == 3);
    final state = h.container.read(deliveryTaskListViewModelProvider);
    expect(state.items.single.taskId, '11111111-1111-4111-8111-111111111118');
    expect(state.error, isNull);
  });

  test(
    'session stream errors clear committed query/counts and ignore a late page',
    () async {
      final repository = _FakeRepository();
      final latePage = Completer<DeliveryTaskPage>();
      repository.responses
        ..add(
          (_) async => _page(
            items: [_task(id: '11111111-1111-4111-8111-111111111119')],
            filteredTotal: 1,
            waiting: 1,
          ),
        )
        ..add((query) {
          expect(query.query, 'secret');
          return latePage.future;
        });
      final h = _harness(repository);
      addTearDown(() async {
        h.subscription.close();
        h.container.dispose();
        await h.sessions.close();
      });

      h.sessions.add(session('shipper-a', 1));
      await _settle(
        h.container,
        () =>
            repository.calls.length == 1 &&
            h.container
                .read(deliveryTaskListViewModelProvider)
                .items
                .isNotEmpty,
      );
      final viewModel = h.container.read(
        deliveryTaskListViewModelProvider.notifier,
      );
      final searching = viewModel.setSearch('secret');
      await _settle(
        h.container,
        () =>
            repository.calls.length == 2 &&
            h.container.read(deliveryTaskListViewModelProvider).isLoading,
      );
      h.sessions.addError(
        const OperationalFailure(OperationalFailureCode.sessionExpired),
      );
      await _settle(
        h.container,
        () =>
            h.container.read(deliveryTaskListViewModelProvider).error?.code ==
            OperationalFailureCode.sessionExpired,
      );
      var state = h.container.read(deliveryTaskListViewModelProvider);
      expect(state.query.query, isNull);
      expect(state.items, isEmpty);
      expect(state.counts, isNull);
      expect(state.filteredTotal, isNull);
      expect(state.nextCursor, isNull);
      expect(state.asOf, isNull);

      latePage.complete(
        _page(
          items: [_task(id: '11111111-1111-4111-8111-111111111120')],
          filteredTotal: 1,
          waiting: 1,
        ),
      );
      await searching;
      await h.container.pump();
      state = h.container.read(deliveryTaskListViewModelProvider);
      expect(state.items, isEmpty);
      expect(state.query.query, isNull);
      expect(state.error?.code, OperationalFailureCode.sessionExpired);
    },
  );

  test('session-expired repository result resets a submitted search and private rows', () async {
    final repository = _FakeRepository();
    repository.responses
      ..add(
        (_) async => _page(
          items: [_task(id: '11111111-1111-4111-8111-111111111122')],
          filteredTotal: 1,
          waiting: 1,
        ),
      )
      ..add((query) {
        expect(query.query, 'secret');
        return Future.error(
          const OperationalFailure(OperationalFailureCode.sessionExpired),
        );
      });
    final h = _harness(repository);
    addTearDown(() async {
      h.subscription.close();
      h.container.dispose();
      await h.sessions.close();
    });

    h.sessions.add(session('shipper-a', 1));
    await _settle(
      h.container,
      () =>
          repository.calls.length == 1 &&
          h.container.read(deliveryTaskListViewModelProvider).items.isNotEmpty,
    );
    await h.container
        .read(deliveryTaskListViewModelProvider.notifier)
        .setSearch('secret');

    final state = h.container.read(deliveryTaskListViewModelProvider);
    expect(repository.calls, hasLength(2));
    expect(state.query.query, isNull);
    expect(state.items, isEmpty);
    expect(state.counts, isNull);
    expect(state.filteredTotal, isNull);
    expect(state.nextCursor, isNull);
    expect(state.error?.code, OperationalFailureCode.sessionExpired);
  });

  test(
    'short terminal cursor page with unchanged total restarts from page one',
    () async {
      final repository = _FakeRepository();
      repository.responses
        ..add(
          (_) async => _page(
            items: List.generate(20, (index) => _task(id: _id(index + 1))),
            nextCursor: 'cursor-1',
            filteredTotal: 21,
            waiting: 21,
          ),
        )
        ..add((query) async {
          expect(query.cursor, 'cursor-1');
          return _page(items: const [], filteredTotal: 21, waiting: 21);
        })
        ..add((query) async {
          expect(query.cursor, isNull);
          return _page(
            items: [_task(id: '11111111-1111-4111-8111-111111111121')],
            filteredTotal: 1,
            waiting: 1,
          );
        });
      final h = _harness(repository);
      addTearDown(() async {
        h.subscription.close();
        h.container.dispose();
        await h.sessions.close();
      });
      h.sessions.add(session('shipper-a', 1));
      await _settle(h.container, () => repository.calls.length == 1);
      await h.container
          .read(deliveryTaskListViewModelProvider.notifier)
          .loadMore();
      final state = h.container.read(deliveryTaskListViewModelProvider);
      expect(repository.calls, hasLength(3));
      expect(state.items.single.taskId, '11111111-1111-4111-8111-111111111121');
      expect(state.filteredTotal, 1);
      expect(state.nextCursor, isNull);
      expect(state.error, isNull);
    },
  );

  test(
    'repeated page drift exhausts the consistency budget as invalid data',
    () async {
      final repository = _FakeRepository();
      DeliveryTaskPage fullPage() => _page(
        items: List.generate(20, (index) => _task(id: _id(index + 1))),
        nextCursor: 'cursor-1',
        filteredTotal: 21,
        waiting: 21,
      );
      DeliveryTaskPage driftPage() =>
          _page(items: const [], filteredTotal: 21, waiting: 21);
      repository.responses
        ..add((_) async => fullPage())
        ..add((_) async => driftPage())
        ..add((_) async => fullPage())
        ..add((_) async => driftPage());
      final h = _harness(repository);
      addTearDown(() async {
        h.subscription.close();
        h.container.dispose();
        await h.sessions.close();
      });
      h.sessions.add(session('shipper-a', 1));
      await _settle(h.container, () => repository.calls.length == 1);
      final viewModel = h.container.read(
        deliveryTaskListViewModelProvider.notifier,
      );
      await viewModel.loadMore();
      expect(repository.calls, hasLength(3));
      await viewModel.loadMore();

      final state = h.container.read(deliveryTaskListViewModelProvider);
      expect(repository.calls, hasLength(4));
      expect(state.error?.code, OperationalFailureCode.invalidData);
      expect(state.items, isEmpty);
      expect(state.counts, isNull);
      expect(state.filteredTotal, isNull);
      expect(state.nextCursor, isNull);
      expect(state.isLoadingMore, isFalse);
    },
  );

  test('load-more permission denial clears the committed page', () async {
    final repository = _FakeRepository();
    repository.responses
      ..add(
        (_) async => _page(
          items: List.generate(20, (index) => _task(id: _id(index + 1))),
          nextCursor: 'cursor-1',
          filteredTotal: 21,
          waiting: 21,
        ),
      )
      ..add(
        (_) => Future.error(
          const OperationalFailure(OperationalFailureCode.permissionDenied),
        ),
      );
    final h = _harness(repository);
    addTearDown(() async {
      h.subscription.close();
      h.container.dispose();
      await h.sessions.close();
    });
    h.sessions.add(session('shipper-a', 1));
    await _settle(
      h.container,
      () => h.container.read(deliveryTaskListViewModelProvider).hasMore,
    );
    await h.container
        .read(deliveryTaskListViewModelProvider.notifier)
        .loadMore();

    final state = h.container.read(deliveryTaskListViewModelProvider);
    expect(state.items, isEmpty);
    expect(state.counts, isNull);
    expect(state.filteredTotal, isNull);
    expect(state.nextCursor, isNull);
    expect(state.error?.code, OperationalFailureCode.permissionDenied);
    expect(state.loadMoreError, isNull);
    expect(state.isLoadingMore, isFalse);
  });
}
