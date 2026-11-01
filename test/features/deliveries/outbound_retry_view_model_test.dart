import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_dto.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_retry_command.dart';
import 'package:sports_store/features/deliveries/domain/repositories/outbound_retry_repository.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/outbound_retry_providers.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/outbound_retry_view_model.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/outbound_result_gate.dart';
import 'package:sports_store/features/deliveries/presentation/widgets/outbound_retry_action.dart';

import 'fixtures/delivery_dtos.dart';

const _failedTaskId = taskId;
const _retryTaskId = '55555555-5555-4555-8555-555555555555';
const _requestId = '66666666-6666-4666-8666-666666666666';

final _failedTask = DeliveryTaskDto.fromJson(maskedTaskDto()).toDomain();

DeliveryTaskDetails _retryDetails() {
  final json = currentTaskDto(
    task: _retryTaskId,
    status: 'assigned',
    acceptedAt: null,
    startedAt: null,
  )..['attempt_number'] = 2;
  return DeliveryTaskDetails(
    task: DeliveryTaskDto.fromJson(json).toDomain(),
    items: const [],
  );
}

class _RetryRepository implements OutboundRetryRepository {
  final commands = <OutboundRetryCommand>[];
  Object? nextError;

  @override
  Future<OutboundRetryAck> execute(OutboundRetryCommand command) async {
    commands.add(command);
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
    return const OutboundRetryAck(
      failedTaskId: _failedTaskId,
      retryTaskId: _retryTaskId,
      requestId: _requestId,
    );
  }
}

class _Harness {
  final sessions = StreamController<OperationalSession>.broadcast();
  final repo = _RetryRepository();
  var reads = 0;
  var listReloads = 0;
  Object? detailsError;
  Future<DeliveryTaskDetails> Function()? detailsHandler;
  late final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      operationalSessionProvider.overrideWith((ref) => sessions.stream),
      outboundRetryRepositoryProvider.overrideWithValue(repo),
      outboundRetryRequestIdProvider.overrideWithValue(() => _requestId),
      outboundRetryDetailsReloadProvider.overrideWithValue((_) async {
        reads++;
        final handler = detailsHandler;
        if (handler != null) return handler();
        final error = detailsError;
        if (error != null) {
          detailsError = null;
          throw error;
        }
        return _retryDetails();
      }),
      outboundRetryTaskListReloadProvider.overrideWithValue(() async {
        listReloads++;
      }),
    ],
  );

  void login({String user = 'shipper-a'}) {
    sessions.add(OperationalSession(userId: user, generation: reads + 1));
  }

  Future<void> close() async {
    container.dispose();
    await sessions.close();
  }
}

Future<void> _settle(ProviderContainer container, bool Function() done) async {
  for (var i = 0; i < 100; i++) {
    await Future<void>.delayed(Duration.zero);
    container.pump();
    if (done()) return;
  }
  fail('provider did not settle');
}

void main() {
  final provider = outboundRetryViewModelProvider(_failedTaskId);

  test(
    'creates task 2 only after an authoritative assigned-task read',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      final sub = h.container.listen(provider, (_, _) {});
      addTearDown(sub.close);
      h.login();
      await _settle(
        h.container,
        () => h.container.read(provider).error == null,
      );

      final retryTaskId = await h.container
          .read(provider.notifier)
          .submit(task: _failedTask);

      expect(retryTaskId, _retryTaskId);
      expect(h.repo.commands, hasLength(1));
      expect(h.repo.commands.single.taskId, _failedTaskId);
      expect(h.repo.commands.single.requestId, _requestId);
      expect(h.reads, 1);
      expect(h.listReloads, 1);
      expect(h.container.read(provider).confirmed, isTrue);
      expect(
        h.container.read(provider).retryDetails?.task.status,
        DeliveryTaskStatus.assigned,
      );
    },
  );

  test('uncertain response retries the exact request and never creates a second key', () async {
    final h = _Harness();
    addTearDown(h.close);
    final sub = h.container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    h.login();
    await _settle(h.container, () => h.container.read(provider).error == null);
    h.repo.nextError = TimeoutException('ambiguous');

    final first = await h.container
        .read(provider.notifier)
        .submit(task: _failedTask);
    expect(first, isNull);
    expect(h.container.read(provider).pendingCommand?.requestId, _requestId);
    expect(h.repo.commands, hasLength(1));

    final second = await h.container.read(provider.notifier).retry();
    expect(second, _retryTaskId);
    expect(h.repo.commands, hasLength(2));
    expect(h.repo.commands[0], h.repo.commands[1]);
    expect(h.reads, 1);
  });

  test('switching accounts during the authoritative read clears ACK, details and gate', () async {
    final h = _Harness();
    addTearDown(h.close);
    final sub = h.container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    final read = Completer<DeliveryTaskDetails>();
    h.detailsHandler = () => read.future;
    h.login(user: 'shipper-a');
    await _settle(h.container, () => h.container.read(provider).error == null);

    final write = h.container.read(provider.notifier).submit(task: _failedTask);
    await _settle(
      h.container,
      () => h.container.read(provider).acknowledgement != null,
    );
    expect(h.container.read(provider).retryDetails, isNull);
    expect(
      h.container.read(outboundResultGateProvider(_failedTaskId)),
      isNotNull,
    );

    h.login(user: 'shipper-b');
    await _settle(
      h.container,
      () =>
          h.container.read(provider).acknowledgement == null &&
          h.container.read(outboundResultGateProvider(_failedTaskId)) == null,
    );
    expect(h.container.read(provider).pendingCommand, isNull);
    expect(h.container.read(provider).retryDetails, isNull);
    expect(h.container.read(provider).confirmed, isFalse);

    read.complete(_retryDetails());
    await write;
    expect(h.container.read(provider).acknowledgement, isNull);
    expect(h.container.read(provider).retryDetails, isNull);
    expect(h.container.read(provider).confirmed, isFalse);
    expect(h.container.read(outboundResultGateProvider(_failedTaskId)), isNull);
  });

  testWidgets(
    'read recovery calls onCreated exactly once after task 2 is verified',
    (tester) async {
      final h = _Harness();
      addTearDown(h.close);
      h.detailsError = TimeoutException('ambiguous read');
      final created = <String>[];
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: OutboundRetryAction(
                task: _failedTask,
                onCreated: (retryTaskId) async => created.add(retryTaskId),
              ),
            ),
          ),
        ),
      );
      h.login();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('outbound-retry-open')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('outbound-retry-open')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('outbound-retry-confirm')));
      await tester.pumpAndSettle();
      expect(created, isEmpty);
      expect(
        find.byKey(const ValueKey('outbound-retry-retry')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('outbound-retry-retry')));
      await tester.pumpAndSettle();
      expect(created, [_retryTaskId]);
      await tester.pumpAndSettle();
      expect(created, hasLength(1));
    },
  );
}
