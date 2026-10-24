import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_dto.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_query.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';
import 'package:sports_store/features/deliveries/domain/repositories/delivery_repository.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/operational_supabase_fixture.dart';
import 'fixtures/delivery_dtos.dart';

// Provider test fixture only. Production providers always use Supabase adapters.
class _FixtureRepository implements DeliveryRepository {
  _FixtureRepository(this.read);
  final Future<List<DeliveryTaskSnapshot>> Function() read;

  @override
  Future<List<DeliveryTaskSnapshot>> listTasks() => read();
  @override
  Future<DeliveryTaskPage> queryTasks(DeliveryTaskQuery query) =>
      throw UnimplementedError(
        'This legacy provider fixture does not query MH10 pages.',
      );
  @override
  Future<DeliveryTaskSnapshot> getTask(String taskId) async =>
      (await read()).single;
  @override
  Future<DeliveryTaskDetails> getTaskDetails(String taskId) async =>
      DeliveryTaskDetails(task: await getTask(taskId), items: const []);
}

Future<void> settleUntil(
  ProviderContainer container,
  bool Function() done,
) async {
  for (var index = 0; index < 100; index++) {
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    if (done()) return;
  }
  fail('Provider did not reach the expected state');
}

void main() {
  test('loading/data/error clear previous data on explicit reload', () async {
    final client = await fixtureClient(
      (request) async => jsonResponse(request, []),
    );
    var pending = Completer<List<DeliveryTaskSnapshot>>();
    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        deliveryRepositoryProvider.overrideWith(
          (ref) => _FixtureRepository(() => pending.future),
        ),
      ],
    );
    final subscription = container.listen(
      deliveryTasksProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await client.dispose();
    });
    await settleUntil(
      container,
      () => container.read(operationalSessionProvider).hasValue,
    );
    expect(container.read(deliveryTasksProvider).isLoading, isTrue);
    pending.complete([DeliveryTaskDto.fromJson(currentTaskDto()).toDomain()]);
    await settleUntil(
      container,
      () => container.read(deliveryTasksProvider).hasValue,
    );
    expect(
      container.read(deliveryTasksProvider).requireValue.single.taskId,
      taskId,
    );

    pending = Completer<List<DeliveryTaskSnapshot>>();
    container.read(operationalReadAccessProvider).refreshSession();
    await settleUntil(
      container,
      () => container.read(deliveryTasksProvider).isLoading,
    );
    expect(container.read(deliveryTasksProvider).asData, isNull);
    pending.completeError(
      const OperationalFailure(OperationalFailureCode.network),
    );
    await settleUntil(
      container,
      () => container.read(deliveryTasksProvider).hasError,
    );
    expect(container.read(deliveryTasksProvider).asData, isNull);
    expect(
      (container.read(deliveryTasksProvider).error! as OperationalFailure).code,
      OperationalFailureCode.network,
    );
  });

  test(
    'account switch and sign out discard cached and late account-A results',
    () async {
      final client = await fixtureClient(
        (request) async => jsonResponse(request, {}),
      );
      final lateA = Completer<List<DeliveryTaskSnapshot>>();
      var callsA = 0;
      final userBTask = currentTaskDto(
        task: '99999999-9999-4999-8999-999999999999',
      );
      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          deliveryRepositoryProvider.overrideWith(
            (ref) => _FixtureRepository(() {
              if (client.auth.currentUser?.id == shipperA) {
                callsA++;
                return lateA.future;
              }
              return Future.value([
                DeliveryTaskDto.fromJson(userBTask).toDomain(),
              ]);
            }),
          ),
        ],
      );
      final subscription = container.listen(
        deliveryTasksProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(() async {
        subscription.close();
        container.dispose();
        await client.dispose();
      });
      await settleUntil(container, () => callsA == 1);
      await recoverFixtureSession(client, shipperB);
      await settleUntil(
        container,
        () => container.read(deliveryTasksProvider).hasValue,
      );
      expect(
        container.read(deliveryTasksProvider).requireValue.single.taskId,
        userBTask['task_id'],
      );
      lateA.complete([DeliveryTaskDto.fromJson(currentTaskDto()).toDomain()]);
      await container.pump();
      expect(
        container.read(deliveryTasksProvider).requireValue.single.taskId,
        userBTask['task_id'],
      );
      await client.auth.signOut(scope: SignOutScope.local);
      await settleUntil(
        container,
        () => container.read(deliveryTasksProvider).hasError,
      );
      expect(container.read(deliveryTasksProvider).asData, isNull);
      expect(
        (container.read(deliveryTasksProvider).error! as OperationalFailure)
            .code,
        OperationalFailureCode.sessionExpired,
      );
    },
  );

  test(
    'detail provider exposes masked history without inventing current PII',
    () async {
      final client = await fixtureClient((request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        return jsonResponse(request, [
          maskedTaskDto(status: 'cancelled', scope: 'history'),
        ]);
      });
      final container = ProviderContainer(
        overrides: [supabaseClientProvider.overrideWithValue(client)],
      );
      final provider = deliveryTaskDetailsProvider(taskId);
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(() async {
        subscription.close();
        container.dispose();
        await client.dispose();
      });
      await settleUntil(container, () => container.read(provider).hasValue);
      final details = container.read(provider).requireValue;
      expect(details.task.scope, DeliverySnapshotScope.history);
      expect(details.task.destination, isNull);
      expect(details.itemsAvailable, isFalse);
    },
  );

  test(
    'disposed access closes its subscription and rejects an outstanding read',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final client = await fixtureClient((request) async {
        entered.complete();
        await release.future;
        return jsonResponse(request, [
          {'role': 'shipper'},
        ]);
      });
      final access = OperationalReadAccess(client);
      final states = <OperationalSession>[];
      final subscription = access.watchSession().listen(states.add);
      final pending = access.run(
        roles: const {'shipper'},
        action: (_) async => 'private-result',
      );
      final assertion = expectLater(
        pending,
        throwsA(isA<OperationalFailure>()),
      );
      await entered.future;
      await access.dispose();
      final before = states.length;
      await recoverFixtureSession(client, shipperB);
      expect(states.length, before);
      release.complete();
      await assertion;
      await subscription.cancel();
      await client.dispose();
    },
  );
}
