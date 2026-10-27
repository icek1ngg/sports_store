import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_dto.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_failure_command.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';
import 'package:sports_store/features/deliveries/domain/repositories/outbound_failure_repository.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/outbound_failure_providers.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/outbound_failure_view_model.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/outbound_result_gate.dart';
import 'package:sports_store/features/deliveries/presentation/widgets/outbound_failure_action.dart';

import 'fixtures/delivery_dtos.dart';

import 'package:sports_store/features/deliveries/domain/models/outbound_completion_command.dart';
import 'package:sports_store/features/deliveries/domain/repositories/outbound_completion_repository.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/outbound_completion_providers.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/outbound_completion_view_model.dart';

class CompletionRepo implements OutboundCompletionRepository {
  int writes = 0;
  @override
  Future<void> execute(OutboundCompletionCommand command) async {
    writes++;
  }
}

const keyId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
DeliveryTaskDetails details({
  bool failed = false,
  int attempt = 1,
  String kind = 'outbound',
  String status = 'in_transit',
}) {
  final dto = failed
      ? maskedTaskDto()
      : currentTaskDto(
          kind: kind,
          status: status,
          acceptedAt: '2026-10-25T09:00:00Z',
          startedAt: '2026-10-25T09:10:00Z',
        );
  dto['attempt_number'] = attempt;
  if (kind != 'outbound') dto['amount_to_collect_vnd'] = 0;
  return DeliveryTaskDetails(
    task: DeliveryTaskDto.fromJson(dto).toDomain(),
    items: const [],
  );
}

class Repo implements OutboundFailureRepository {
  final commands = <OutboundFailureCommand>[];
  Future<OutboundFailureAck> Function(OutboundFailureCommand)? handler;
  @override
  Future<OutboundFailureAck> execute(OutboundFailureCommand c) async {
    commands.add(c);
    return handler != null
        ? handler!(c)
        : OutboundFailureAck(
            taskId: c.taskId,
            requestId: c.requestId,
            attemptNumber: c.attemptNumber,
            disposition: OutboundFailureDisposition.forAttempt(c.attemptNumber),
          );
  }
}

class Harness {
  final sessions = StreamController<OperationalSession>.broadcast();
  final repo = Repo();
  final completionRepo = CompletionRepo();
  DeliveryTaskDetails remote = details();
  int reads = 0, reloads = 0, keys = 0;
  Future<DeliveryTaskDetails> Function()? read;
  late final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      operationalSessionProvider.overrideWith((ref) => sessions.stream),
      outboundFailureRepositoryProvider.overrideWithValue(repo),
      outboundCompletionRepositoryProvider.overrideWithValue(completionRepo),
      outboundCompletionDetailsReloadProvider.overrideWithValue(
        (_) async => remote,
      ),
      outboundCompletionRequestIdProvider.overrideWithValue(() => keyId),
      outboundFailureRequestIdProvider.overrideWithValue(() {
        keys++;
        return keyId;
      }),
      outboundFailureDetailsReloadProvider.overrideWithValue((_) async {
        reads++;
        return read != null ? read!() : remote;
      }),
      outboundFailureTaskListReloadProvider.overrideWithValue(() async {
        reloads++;
      }),
    ],
  );
  void login({String user = 'shipper-a'}) => sessions.add(
    OperationalSession(userId: user, generation: reads + keys + 1),
  );
  Future<void> close() async {
    container.dispose();
    await sessions.close();
  }
}

Future<void> settle(ProviderContainer c, bool Function() done) async {
  for (var i = 0; i < 100; i++) {
    await Future<void>.delayed(Duration.zero);
    await c.pump();
    if (done()) return;
  }
  fail('provider did not settle');
}

final provider = outboundFailureViewModelProvider(taskId);
Future<void> submit(
  Harness h, {
  OutboundFailureReason reason = OutboundFailureReason.unreachable,
  String? description,
}) async {
  final vm = h.container.read(provider.notifier);
  await vm.submit(
    reason: reason,
    description: description,
    sessionRevision: vm.sessionRevisionForConfirmation,
  );
}

void main() {
  test('production failure and completion providers cannot dispatch conflicting outcomes', () async {
    final h = Harness();
    addTearDown(h.close);
    final f = h.container.listen(provider, (_, _) {});
    addTearDown(f.close);
    final cp = outboundCompletionViewModelProvider(taskId);
    final c = h.container.listen(cp, (_, _) {});
    addTearDown(c.close);
    h.login();
    await settle(
      h.container,
      () =>
          h.container.read(provider).canFail &&
          h.container.read(cp).canComplete,
    );
    h.repo.handler = (_) async => throw TimeoutException('lost ACK');
    await submit(h);
    final vm = h.container.read(cp.notifier);
    await vm.submit(
      receivedAllItems: true,
      receivedFullCod: true,
      displayedAmountVnd: 550000,
      sessionRevision: vm.sessionRevisionForConfirmation,
    );
    expect(h.repo.commands.length, 1);
    expect(h.completionRepo.writes, 0);
    expect(h.container.read(provider).pendingCommand, isNotNull);
  });
  for (final attempt in [1, 2]) {
    test(
      'attempt $attempt validates restricted server result and refreshes MH10',
      () async {
        final h = Harness()..remote = details(attempt: attempt);
        addTearDown(h.close);
        final sub = h.container.listen(provider, (_, _) {});
        addTearDown(sub.close);
        h.login();
        await settle(h.container, () => h.container.read(provider).canFail);
        h.repo.handler = (c) async {
          h.remote = details(failed: true, attempt: attempt);
          return OutboundFailureAck(
            taskId: c.taskId,
            requestId: c.requestId,
            attemptNumber: attempt,
            disposition: OutboundFailureDisposition.forAttempt(attempt),
          );
        };
        await submit(h);
        expect(h.container.read(provider).confirmed, true);
        expect(
          h.container.read(provider).disposition,
          OutboundFailureDisposition.forAttempt(attempt),
        );
        expect(h.reloads, 1);
        expect(h.keys, 1);
        expect(h.container.read(outboundResultGateProvider(taskId)), isNull);
      },
    );
  }
  test(
    'timeout preserves exact key/payload and excludes opposite outcome',
    () async {
      final h = Harness();
      addTearDown(h.close);
      final sub = h.container.listen(provider, (_, _) {});
      addTearDown(sub.close);
      h.login();
      await settle(h.container, () => h.container.read(provider).canFail);
      h.repo.handler = (_) async => throw TimeoutException('private');
      await submit(
        h,
        reason: OutboundFailureReason.other,
        description: '  không gặp khách  ',
      );
      final pending = h.container.read(provider).pendingCommand;
      expect(pending, isNotNull);
      expect(h.keys, 1);
      expect(
        h.container
            .read(outboundResultGateProvider(taskId).notifier)
            .acquire(Object()),
        false,
      );
      h.repo.handler = (c) async {
        h.remote = details(failed: true);
        return OutboundFailureAck(
          taskId: c.taskId,
          requestId: c.requestId,
          attemptNumber: 1,
          disposition: OutboundFailureDisposition.managerDecision,
        );
      };
      await h.container.read(provider.notifier).retry();
      expect(h.repo.commands, [pending, pending]);
      expect(h.keys, 1);
      expect(h.container.read(provider).confirmed, true);
    },
  );
  test('ACK read failure retries read only and token refresh keeps recovery visible', () async {
    final h = Harness();
    addTearDown(h.close);
    final sub = h.container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    h.login();
    await settle(h.container, () => h.container.read(provider).canFail);
    h.repo.handler = (c) async {
      h.read = () async => throw TimeoutException('read');
      return OutboundFailureAck(
        taskId: c.taskId,
        requestId: c.requestId,
        attemptNumber: 1,
        disposition: OutboundFailureDisposition.managerDecision,
      );
    };
    await submit(h);
    expect(h.container.read(provider).pendingCommand, isNull);
    h.login();
    await settle(
      h.container,
      () => h.container.read(provider).requiresReadRetry,
    );
    h.read = () async => details(failed: true);
    await h.container.read(provider.notifier).retry();
    expect(h.repo.commands.length, 1);
    expect(h.container.read(provider).confirmed, true);
  });
  test(
    'account switch drops pending reason and ignores old response',
    () async {
      final h = Harness();
      addTearDown(h.close);
      final sub = h.container.listen(provider, (_, _) {});
      addTearDown(sub.close);
      h.login();
      await settle(h.container, () => h.container.read(provider).canFail);
      final gate = Completer<OutboundFailureAck>();
      h.repo.handler = (_) => gate.future;
      final write = submit(
        h,
        reason: OutboundFailureReason.other,
        description: 'private',
      );
      h.login(user: 'shipper-b');
      await settle(
        h.container,
        () => h.container.read(provider).pendingCommand == null,
      );
      gate.complete(
        const OutboundFailureAck(
          taskId: taskId,
          requestId: keyId,
          attemptNumber: 1,
          disposition: OutboundFailureDisposition.managerDecision,
        ),
      );
      await write;
      expect(h.container.read(provider).confirmed, false);
      expect(h.reloads, 0);
    },
  );
  test(
    'other is validated before network and wrong ACK never claims success',
    () async {
      final h = Harness();
      addTearDown(h.close);
      final sub = h.container.listen(provider, (_, _) {});
      addTearDown(sub.close);
      h.login();
      await settle(h.container, () => h.container.read(provider).canFail);
      await submit(
        h,
        reason: OutboundFailureReason.other,
        description: ' \n\t',
      );
      expect(h.repo.commands, isEmpty);
      h.repo.handler = (_) async => const OutboundFailureAck(
        taskId: taskId,
        requestId: keyId,
        attemptNumber: 2,
        disposition: OutboundFailureDisposition.storeReturnPending,
      );
      await submit(h);
      expect(h.container.read(provider).confirmed, false);
      expect(h.container.read(provider).pendingCommand, isNotNull);
    },
  );
  for (final code in [
    OutboundCommandFailureCode.permissionDenied,
    OutboundCommandFailureCode.staleState,
  ]) {
    test('real error $code does not fake a failed task', () async {
      final h = Harness();
      addTearDown(h.close);
      final sub = h.container.listen(provider, (_, _) {});
      addTearDown(sub.close);
      h.login();
      await settle(h.container, () => h.container.read(provider).canFail);
      h.repo.handler = (_) async => throw OutboundCommandFailure(code);
      await submit(h);
      expect(h.container.read(provider).confirmed, false);
      expect(h.container.read(provider).pendingCommand, isNull);
    });
  }
  testWidgets(
    'dialog other validation, no COD assertion, double tap writes once',
    (tester) async {
      final h = Harness();
      addTearDown(h.close);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: OutboundFailureAction(taskId: taskId)),
          ),
        ),
      );
      h.login();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('failure-open')));
      await tester.pumpAndSettle();
      expect(h.repo.commands, isEmpty);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('failure-confirm')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('failure-reason')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Khác').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('failure-confirm')))
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const ValueKey('failure-description')),
        '  ghi chú  ',
      );
      await tester.pump();
      h.repo.handler = (c) async {
        h.remote = details(failed: true);
        return OutboundFailureAck(
          taskId: c.taskId,
          requestId: c.requestId,
          attemptNumber: 1,
          disposition: OutboundFailureDisposition.managerDecision,
        );
      };
      final confirm = tester
          .widget<FilledButton>(find.byKey(const ValueKey('failure-confirm')))
          .onPressed!;
      confirm();
      confirm();
      await tester.pumpAndSettle();
      expect(h.repo.commands.length, 1);
      expect(h.repo.commands.single.trimmedDescription, 'ghi chú');
      expect(
        find.text('Giao thất bại. Chờ quản lý quyết định.'),
        findsOneWidget,
      );
      expect(find.textContaining('Đã thu đủ'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'account switch closes dialog and recovery never opens stale opposite action',
    (tester) async {
      final h = Harness();
      addTearDown(h.close);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: const MaterialApp(
            home: Scaffold(body: OutboundFailureAction(taskId: taskId)),
          ),
        ),
      );
      h.login();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('failure-open')));
      await tester.pumpAndSettle();
      h.login(user: 'shipper-b');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('failure-confirm')), findsNothing);
      expect(h.repo.commands, isEmpty);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: const MaterialApp(
            home: Scaffold(
              body: OutboundFailureAction(taskId: taskId, allowSubmit: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('failure-open')), findsNothing);
    },
  );
}
