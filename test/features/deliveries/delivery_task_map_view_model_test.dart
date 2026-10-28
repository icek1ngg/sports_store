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
final class _FakeDirectionsLauncher implements MapDirectionsLauncher {
  final destinations = <SavedDestinationRecord>[];
  MapDirectionsOutcome result = MapDirectionsOutcome.opened;

  @override
  Future<MapDirectionsOutcome> openDirections(destination) async {
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

  DeliveryTaskDetails Function(String taskId) read;
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
    'rechecks the authorized task before opening coordinate-only directions',
    () async {
      final sessions = StreamController<OperationalSession>.broadcast();
      final repository = _FakeDeliveryRepository((_) => _currentDetails());
      final launcher = _FakeDirectionsLauncher();
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          deliveryRepositoryProvider.overrideWithValue(repository),
          mapDirectionsLauncherProvider.overrideWithValue(launcher),
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
          mapDirectionsLauncherProvider.overrideWithValue(launcher),
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
        mapDirectionsLauncherProvider.overrideWithValue(launcher),
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
