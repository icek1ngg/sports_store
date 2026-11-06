import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/maps/map_directions.dart';
import 'package:sports_store/core/maps/map_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_query.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';
import 'package:sports_store/features/deliveries/domain/repositories/delivery_repository.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_providers.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_task_map_view_model.dart';

import 'fixtures/delivery_dtos.dart';

import 'package:sports_store/features/deliveries/data/models/delivery_task_dto.dart';

/// Fake adapter used only to verify MH18's external-directions boundary.
final class _FakeDirectionsLauncher implements MapNavigationAdapter {
  final destinations = <SavedDestinationRecord>[];
  MapDirectionsOutcome result = MapDirectionsOutcome.opened;

  @override
  Future<MapDirectionsOutcome> openLocation(destination) async {
    destinations.add(
      SavedDestinationRecord(
        latitude: destination.latitude,
        longitude: destination.longitude,
      ),
    );
    return result;
  }
}

final class SavedDestinationRecord {
  const SavedDestinationRecord({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is SavedDestinationRecord &&
      latitude == other.latitude &&
      longitude == other.longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

final class _FakeDeliveryRepository implements DeliveryRepository {
  _FakeDeliveryRepository(this.read);

  FutureOr<DeliveryTaskDetails> Function(String taskId) read;
  int detailReads = 0;

  @override
  Future<DeliveryTaskDetails> getTaskDetails(String taskId) async {
    detailReads++;
    return read(taskId);
  }

  @override
  Future<DeliveryTaskSnapshot> getTask(String taskId) =>
      Future.error(UnimplementedError());

  @override
  Future<List<DeliveryTaskSnapshot>> listTasks() =>
      Future.error(UnimplementedError());

  @override
  Future<DeliveryTaskPage> queryTasks(DeliveryTaskQuery query) =>
      Future.error(UnimplementedError());
}

DeliveryTaskDetails _currentDetails() {
  return DeliveryTaskDetails(
    task: DeliveryTaskDto.fromJson(currentTaskDto(task: taskId)).toDomain(),
    items: const [],
  );
}

DeliveryTaskDetails _maskedDetails() {
  return DeliveryTaskDetails(
    task: DeliveryTaskDto.fromJson(maskedTaskDto()).toDomain(),
    items: const [],
  );
}

/// Test-only authorized-read/session harness; never an application fallback.
class _DataHarness {
  _DataHarness(this.repository, {this.id = taskId}) {
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        deliveryRepositoryProvider.overrideWithValue(repository),
        operationalSessionProvider.overrideWith((ref) => sessions.stream),
      ],
    );
    subscription = container.listen(
      deliveryTaskMapViewModelProvider(id),
      (_, _) {},
      fireImmediately: true,
    );
  }
  final _FakeDeliveryRepository repository;
  final String id;
  final sessions = StreamController<OperationalSession>.broadcast();
  late final ProviderContainer container;
  late final ProviderSubscription<AsyncValue<DeliveryTaskDetails>> subscription;
  Future<void> ready({bool error = false}) async {
    sessions.add(const OperationalSession(userId: 'shipper-a', generation: 1));
    await _settle(
      container,
      () => error
          ? container.read(deliveryTaskMapViewModelProvider(id)).hasError
          : container.read(deliveryTaskMapViewModelProvider(id)).hasValue,
    );
  }

  Future<void> dispose() async {
    subscription.close();
    container.dispose();
    await sessions.close();
  }
}

/// Simulates an epoch switch after a successful authorized read resolves,
/// before the caller can hand coordinates to an external application.
class _SwitchAfterReadViewModel extends DeliveryTaskMapViewModel {
  _SwitchAfterReadViewModel(this.afterRead) : super(taskId);
  final Future<void> Function() afterRead;
  @override
  Future<DeliveryTaskDetails> recheckAuthorizedDetails() async {
    final details = await super.recheckAuthorizedDetails();
    await afterRead();
    return details;
  }
}

Future<void> _settle(ProviderContainer container, bool Function() done) async {
  for (var index = 0; index < 200; index++) {
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    if (done()) return;
  }
  fail('Provider did not reach the expected state');
}

void main() {
  test(
    'late initial read cannot restore PII after a newer authorization denial',
    () async {
      final initial = Completer<DeliveryTaskDetails>();
      final repository = _FakeDeliveryRepository((_) => initial.future);
      final h = _DataHarness(repository);
      addTearDown(h.dispose);
      h.sessions.add(
        const OperationalSession(userId: 'shipper-a', generation: 1),
      );
      await _settle(h.container, () => repository.detailReads == 1);
      repository.read = (_) => throw const OperationalFailure(
        OperationalFailureCode.staleAssignment,
      );
      await expectLater(
        h.container
            .read(deliveryTaskMapViewModelProvider(taskId).notifier)
            .recheckAuthorizedDetails(),
        throwsA(isA<OperationalFailure>()),
      );
      initial.complete(_currentDetails());
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
        await h.container.pump();
      }
      final state = h.container.read(deliveryTaskMapViewModelProvider(taskId));
      expect(state.hasValue, isFalse);
      expect(
        (state.error as OperationalFailure).code,
        OperationalFailureCode.staleAssignment,
      );
    },
  );
  for (final code in [
    OperationalFailureCode.permissionDenied,
    OperationalFailureCode.staleAssignment,
    OperationalFailureCode.invalidData,
  ]) {
    test('a fresh $code denial clears the old recipient snapshot', () async {
      final repository = _FakeDeliveryRepository((_) => _currentDetails());
      final h = _DataHarness(repository);
      addTearDown(h.dispose);
      await h.ready();
      repository.read = (_) => throw OperationalFailure(code);
      await expectLater(
        h.container
            .read(deliveryTaskMapViewModelProvider(taskId).notifier)
            .recheckAuthorizedDetails(),
        throwsA(isA<OperationalFailure>()),
      );
      expect(
        h.container.read(deliveryTaskMapViewModelProvider(taskId)).hasValue,
        isFalse,
      );
      expect(
        h.container.read(deliveryTaskMapViewModelProvider(taskId)).hasError,
        isTrue,
      );
    });
  }
  test(
    'epoch change after successful read blocks coordinate handoff',
    () async {
      final sessions = StreamController<OperationalSession>.broadcast();
      final launcher = _FakeDirectionsLauncher();
      late ProviderContainer c;
      c = ProviderContainer(
        overrides: [
          operationalSessionProvider.overrideWith((ref) => sessions.stream),
          deliveryRepositoryProvider.overrideWithValue(
            _FakeDeliveryRepository((_) => _currentDetails()),
          ),
          mapNavigationAdapterProvider.overrideWithValue(launcher),
          deliveryTaskMapViewModelProvider(taskId).overrideWith(
            () => _SwitchAfterReadViewModel(() async {
              sessions.add(
                const OperationalSession(userId: 'shipper-b', generation: 2),
              );
              await _settle(
                c,
                () =>
                    c.read(operationalSessionProvider).asData?.value.userId ==
                        'shipper-b' &&
                    c.read(deliveryTaskMapViewModelProvider(taskId)).hasValue,
              );
            }),
          ),
        ],
      );
      final subscription = c.listen(
        deliveryTaskMapViewModelProvider(taskId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(() async {
        subscription.close();
        c.dispose();
        await sessions.close();
      });
      sessions.add(
        const OperationalSession(userId: 'shipper-a', generation: 1),
      );
      await _settle(
        c,
        () => c.read(deliveryTaskMapViewModelProvider(taskId)).hasValue,
      );
      await expectLater(
        c
            .read(deliveryTaskMapViewModelProvider(taskId).notifier)
            .openDirections(),
        throwsA(isA<OperationalFailure>()),
      );
      expect(launcher.destinations, isEmpty);
    },
  );
  for (final kind in DeliveryTaskKind.values) {
    test('P09.1 reads saved destination and kind for ${kind.name}', () async {
      final json = currentTaskDto(
        kind: kind.value,
        returnRequest: kind == DeliveryTaskKind.outbound
            ? null
            : returnRequestId,
        amount: kind == DeliveryTaskKind.outbound ? 550000 : 0,
        itemSource: kind == DeliveryTaskKind.outbound
            ? 'order_snapshot'
            : 'return_plan',
      );
      json['destination_name'] = 'Saved ${kind.name}';
      json['destination_latitude'] = 21.01 + kind.index / 100;
      final expected = DeliveryTaskDetails(
        task: DeliveryTaskDto.fromJson(json).toDomain(),
        items: const [],
      );
      final h = _DataHarness(
        _FakeDeliveryRepository((id) {
          expect(id, taskId);
          return expected;
        }),
      );
      addTearDown(h.dispose);
      await h.ready();
      final actual = h.container
          .read(deliveryTaskMapViewModelProvider(taskId))
          .requireValue;
      expect(actual.task.kind, kind);
      expect(actual.task.destination, expected.task.destination);
      expect(actual.task.destination!.phone, '0900000000');
      expect(actual.notes, isNull);
      expect(actual.notesSource, DeliveryNotesSource.unavailableSchema);
    });
  }
  test('invalid task UUID is rejected before a repository read', () async {
    final h = _DataHarness(
      _FakeDeliveryRepository((_) => _currentDetails()),
      id: 'invalid-id',
    );
    addTearDown(h.dispose);
    await h.ready(error: true);
    expect(h.repository.detailReads, 0);
  });
  test('unknown or unauthorized UUID never exposes destination', () async {
    final h = _DataHarness(
      _FakeDeliveryRepository(
        (_) => throw const OperationalFailure(
          OperationalFailureCode.permissionDenied,
        ),
      ),
      id: orderId,
    );
    addTearDown(h.dispose);
    await h.ready(error: true);
    expect(
      h.container.read(deliveryTaskMapViewModelProvider(orderId)).hasValue,
      isFalse,
    );
  });
  test(
    'missing location fails closed instead of inventing coordinates',
    () async {
      final missing = DeliveryTaskDetails(
        task: const DeliveryTaskSnapshot(
          taskId: taskId,
          kind: DeliveryTaskKind.outbound,
          status: DeliveryTaskStatus.assigned,
          attemptNumber: 1,
          scope: DeliverySnapshotScope.current,
          orderId: orderId,
          amountToCollectVnd: 550000,
          itemSource: DeliveryItemSource.orderSnapshot,
        ),
        items: const [],
      );
      final h = _DataHarness(_FakeDeliveryRepository((_) => missing));
      addTearDown(h.dispose);
      await h.ready(error: true);
      expect(
        (h.container.read(deliveryTaskMapViewModelProvider(taskId)).error
                as OperationalFailure)
            .code,
        OperationalFailureCode.invalidData,
      );
      for (final key in ['destination_latitude', 'destination_longitude']) {
        final json = currentTaskDto();
        json[key] = null;
        expect(
          () => DeliveryTaskDto.fromJson(json).toDomain(),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'late read after account switch cannot restore or clear the new snapshot',
    () async {
      final repository = _FakeDeliveryRepository((_) => _currentDetails());
      final h = _DataHarness(repository);
      addTearDown(h.dispose);
      await h.ready();
      final pending = Completer<DeliveryTaskDetails>();
      repository.read = (_) => pending.future;
      final old = h.container
          .read(deliveryTaskMapViewModelProvider(taskId).notifier)
          .recheckAuthorizedDetails();
      final expectation = expectLater(old, throwsA(isA<OperationalFailure>()));
      final nextJson = currentTaskDto();
      nextJson['destination_name'] = 'Account B recipient';
      repository.read = (_) => DeliveryTaskDetails(
        task: DeliveryTaskDto.fromJson(nextJson).toDomain(),
        items: const [],
      );
      h.sessions.add(
        const OperationalSession(userId: 'shipper-b', generation: 2),
      );
      await _settle(
        h.container,
        () =>
            h.container
                .read(deliveryTaskMapViewModelProvider(taskId))
                .asData
                ?.value
                .task
                .destination
                ?.name ==
            'Account B recipient',
      );
      pending.complete(_currentDetails());
      await expectation;
      expect(
        h.container
            .read(deliveryTaskMapViewModelProvider(taskId))
            .requireValue
            .task
            .destination!
            .name,
        'Account B recipient',
      );
    },
  );
  test(
    'network failure retains fallback data but cannot authorize an action',
    () async {
      final repository = _FakeDeliveryRepository((_) => _currentDetails());
      final h = _DataHarness(repository);
      addTearDown(h.dispose);
      await h.ready();
      repository.read = (_) =>
          throw const OperationalFailure(OperationalFailureCode.network);
      await expectLater(
        h.container
            .read(deliveryTaskMapViewModelProvider(taskId).notifier)
            .recheckAuthorizedDetails(),
        throwsA(isA<OperationalFailure>()),
      );
      expect(
        h.container.read(deliveryTaskMapViewModelProvider(taskId)).hasValue,
        isTrue,
      );
    },
  );
  test(
    'rechecks the authorized task before opening coordinate-only directions',
    () async {
      final sessions = StreamController<OperationalSession>.broadcast();
      final repository = _FakeDeliveryRepository((_) => _currentDetails());
      final launcher = _FakeDirectionsLauncher();
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          deliveryRepositoryProvider.overrideWithValue(repository),
          mapNavigationAdapterProvider.overrideWithValue(launcher),
          operationalSessionProvider.overrideWith((ref) => sessions.stream),
        ],
      );
      final subscription = container.listen(
        deliveryTaskMapViewModelProvider(taskId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(() async {
        subscription.close();
        container.dispose();
        await sessions.close();
      });

      sessions.add(
        const OperationalSession(userId: 'shipper-a', generation: 1),
      );
      await _settle(
        container,
        () => container.read(deliveryTaskMapViewModelProvider(taskId)).hasValue,
      );

      final outcome = await container
          .read(deliveryTaskMapViewModelProvider(taskId).notifier)
          .openDirections();

      expect(outcome, MapDirectionsOutcome.opened);
      expect(repository.detailReads, 2);
      expect(launcher.destinations, [
        const SavedDestinationRecord(
          latitude: 21.028511,
          longitude: 105.804817,
        ),
      ]);
    },
  );

  test(
    'does not expose a task that became restricted while the map was open',
    () async {
      final sessions = StreamController<OperationalSession>.broadcast();
      var current = true;
      final repository = _FakeDeliveryRepository(
        (_) => current ? _currentDetails() : _maskedDetails(),
      );
      final launcher = _FakeDirectionsLauncher();
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          deliveryRepositoryProvider.overrideWithValue(repository),
          mapNavigationAdapterProvider.overrideWithValue(launcher),
          operationalSessionProvider.overrideWith((ref) => sessions.stream),
        ],
      );
      final subscription = container.listen(
        deliveryTaskMapViewModelProvider(taskId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(() async {
        subscription.close();
        container.dispose();
        await sessions.close();
      });

      sessions.add(
        const OperationalSession(userId: 'shipper-a', generation: 1),
      );
      await _settle(
        container,
        () => container.read(deliveryTaskMapViewModelProvider(taskId)).hasValue,
      );
      current = false;

      await expectLater(
        container
            .read(deliveryTaskMapViewModelProvider(taskId).notifier)
            .openDirections(),
        throwsA(
          isA<OperationalFailure>().having(
            (failure) => failure.code,
            'code',
            OperationalFailureCode.staleAssignment,
          ),
        ),
      );
      expect(launcher.destinations, isEmpty);
      expect(
        container.read(deliveryTaskMapViewModelProvider(taskId)).hasValue,
        isFalse,
      );
      expect(
        container.read(deliveryTaskMapViewModelProvider(taskId)).hasError,
        isTrue,
      );
    },
  );

  test('session change cancels map actions before exposing old PII', () async {
    final sessions = StreamController<OperationalSession>.broadcast();
    final repository = _FakeDeliveryRepository((_) => _currentDetails());
    final launcher = _FakeDirectionsLauncher();
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        deliveryRepositoryProvider.overrideWithValue(repository),
        mapNavigationAdapterProvider.overrideWithValue(launcher),
        operationalSessionProvider.overrideWith((ref) => sessions.stream),
      ],
    );
    final subscription = container.listen(
      deliveryTaskMapViewModelProvider(taskId),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await sessions.close();
    });

    sessions.add(const OperationalSession(userId: 'shipper-a', generation: 1));
    await _settle(
      container,
      () => container.read(deliveryTaskMapViewModelProvider(taskId)).hasValue,
    );
    sessions.add(const OperationalSession(userId: null, generation: 2));
    await _settle(
      container,
      () => container.read(deliveryTaskMapViewModelProvider(taskId)).hasError,
    );

    await expectLater(
      container
          .read(deliveryTaskMapViewModelProvider(taskId).notifier)
          .openDirections(),
      throwsA(
        isA<OperationalFailure>().having(
          (failure) => failure.code,
          'code',
          OperationalFailureCode.sessionExpired,
        ),
      ),
    );
    expect(launcher.destinations, isEmpty);
  });
}
