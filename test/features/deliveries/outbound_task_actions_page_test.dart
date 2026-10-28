import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_query.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';
import 'package:sports_store/features/deliveries/domain/repositories/delivery_repository.dart';
import 'package:sports_store/features/deliveries/domain/repositories/outbound_task_command_repository.dart';
import 'package:sports_store/features/deliveries/presentation/pages/delivery_task_detail_page.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_providers.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/outbound_action_providers.dart';

const _taskId = '11111111-1111-4111-8111-111111111111';
const _requestId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _requestId2 = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

const _validSession = OperationalSession(userId: 'shipper-a', generation: 1);

const _expiredSession = OperationalSession(
  userId: null,
  generation: 2,
  failure: OperationalFailure(OperationalFailureCode.sessionExpired),
);

class _ScriptedCommandRepository implements OutboundTaskCommandRepository {
  final commands = <OutboundTaskCommand>[];
  Future<void> Function(OutboundTaskCommand command)? handler;

  @override
  Future<void> execute(OutboundTaskCommand command) {
    commands.add(command);
    return handler?.call(command) ?? Future<void>.value();
  }
}

class _ScriptedDeliveryRepository implements DeliveryRepository {
  _ScriptedDeliveryRepository(this.remote);

  DeliveryTaskDetails remote;
  final readFailures = <Object>[];
  final detailTaskIds = <String>[];
  final queries = <DeliveryTaskQuery>[];
  Future<void>? detailGate;

  int get detailReads => detailTaskIds.length;

  @override
  Future<List<DeliveryTaskSnapshot>> listTasks() async => [remote.task];

  @override
  Future<DeliveryTaskPage> queryTasks(DeliveryTaskQuery query) async {
    queries.add(query);
    return DeliveryTaskPage(
      items: [remote.task],
      nextCursor: null,
      filteredTotal: 1,
      counts: const DeliveryTaskCounts(
        waiting: 1,
        inTransit: 0,
        completed: 0,
        ungrouped: 0,
      ),
      asOf: DateTime.utc(2026, 10, 26),
    );
  }

  @override
  Future<DeliveryTaskSnapshot> getTask(String taskId) async => remote.task;

  @override
  Future<DeliveryTaskDetails> getTaskDetails(String taskId) async {
    detailTaskIds.add(taskId);
    await detailGate;
    if (readFailures.isNotEmpty) throw readFailures.removeAt(0);
    if (taskId != remote.task.taskId) {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }
    return remote;
  }
}

class _ActionHarness {
  _ActionHarness({DeliveryTaskDetails? initial})
    : repository = _ScriptedDeliveryRepository(initial ?? _details()) {
    commandRepository.handler = (command) async {
      repository.remote = _after(command.action, repository.remote);
    };
  }

  final sessions = StreamController<OperationalSession>.broadcast(sync: true);
  final _ScriptedDeliveryRepository repository;
  final commandRepository = _ScriptedCommandRepository();
  var listReloads = 0;
  var nextRequest = 0;

  String createRequestId() {
    nextRequest++;
    return nextRequest == 1 ? _requestId : _requestId2;
  }

  Future<void> close() async {
    await sessions.close();
  }
}

Widget _app(_ActionHarness harness, {double textScale = 1}) {
  return ProviderScope(
    overrides: [
      operationalSessionProvider.overrideWith((ref) => harness.sessions.stream),
      deliveryRepositoryProvider.overrideWithValue(harness.repository),
      outboundTaskCommandRepositoryProvider.overrideWithValue(
        harness.commandRepository,
      ),
      outboundTaskRequestIdProvider.overrideWithValue(harness.createRequestId),
      // The action tests use the real, session-keyed detail reload above. MH10
      // list refresh is intentionally just observed here so it cannot add a
      // second UI surface to these MH11 integration tests.
      outboundTaskListReloadProvider.overrideWithValue(() async {
        harness.listReloads++;
      }),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: const Scaffold(body: DeliveryTaskDetailPage(taskId: _taskId)),
      ),
    ),
  );
}

Future<void> _pumpReady(
  WidgetTester tester,
  _ActionHarness harness, {
  double textScale = 1,
  OperationalSession session = _validSession,
}) async {
  await tester.pumpWidget(_app(harness, textScale: textScale));
  harness.sessions.add(session);
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _openAction(WidgetTester tester, String key) async {
  final action = find.byKey(ValueKey(key));
  expect(action, findsOneWidget);
  // MH11 is a long sliver page. Scroll first, then use ensureVisible for the
  // production action control so the test never taps an off-screen RenderBox.
  await tester.drag(
    find.byKey(const ValueKey('task-detail-scroll')),
    const Offset(0, -1000),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(action);
  await tester.pump();
  await tester.tap(action);
  await tester.pumpAndSettle();
  expect(
    find.byKey(const ValueKey('outbound-confirm-custody')),
    findsOneWidget,
  );
}

Future<void> _checkAndSubmit(WidgetTester tester) async {
  final checkbox = find.byKey(const ValueKey('outbound-confirm-custody'));
  await tester.ensureVisible(checkbox);
  await tester.tap(checkbox);
  await tester.pump();
  final submit = find.byKey(const ValueKey('outbound-confirm-submit'));
  expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
  await tester.tap(submit);
}

void main() {
  testWidgets('slow authoritative refetch keeps action controller mounted', (
    tester,
  ) async {
    final harness = _ActionHarness();
    addTearDown(harness.close);
    final gate = Completer<void>();
    harness.commandRepository.handler = (command) async {
      harness.repository.remote = _after(
        command.action,
        harness.repository.remote,
      );
      harness.repository.detailGate = gate.future;
    };
    await _pumpReady(tester, harness);
    await _openAction(tester, 'outbound-accept-goods');
    await _checkAndSubmit(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    gate.complete();
    await tester.pumpAndSettle();
    final start = find.byKey(const ValueKey('outbound-start-delivery'));
    expect(start, findsOneWidget);
    expect(tester.widget<ButtonStyleButton>(start).onPressed, isNotNull);
    expect(harness.repository.detailReads, lessThan(5));
    expect(harness.commandRepository.commands, hasLength(1));
  });

  testWidgets('opening and cancelling confirmation never sends a command', (
    tester,
  ) async {
    final harness = _ActionHarness();
    addTearDown(harness.close);
    await _pumpReady(tester, harness);

    expect(harness.commandRepository.commands, isEmpty);
    await _openAction(tester, 'outbound-accept-goods');
    expect(harness.commandRepository.commands, isEmpty);
    await tester.tap(find.byKey(const ValueKey('outbound-confirm-cancel')));
    await tester.pumpAndSettle();
    expect(harness.commandRepository.commands, isEmpty);
  });

  testWidgets('manual custody checkbox guards the submit button', (
    tester,
  ) async {
    final harness = _ActionHarness();
    addTearDown(harness.close);
    await _pumpReady(tester, harness);
    await _openAction(tester, 'outbound-accept-goods');

    final submit = find.byKey(const ValueKey('outbound-confirm-submit'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.tap(submit);
    await tester.pump();
    expect(harness.commandRepository.commands, isEmpty);

    await tester.tap(find.byKey(const ValueKey('outbound-confirm-custody')));
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
  });

  testWidgets(
    'accept refetches accepted, then start refetches in-transit with correct buttons',
    (tester) async {
      final harness = _ActionHarness();
      addTearDown(harness.close);
      await _pumpReady(tester, harness);

      await _openAction(tester, 'outbound-accept-goods');
      await _checkAndSubmit(tester);
      await tester.pumpAndSettle();
      expect(
        harness.commandRepository.commands.single.action,
        OutboundTaskAction.acceptGoods,
      );
      expect(find.text('Đã nhận hàng'), findsOneWidget);
      expect(find.byKey(const ValueKey('outbound-accept-goods')), findsNothing);
      expect(
        find.byKey(const ValueKey('outbound-start-delivery')),
        findsOneWidget,
      );
      expect(harness.listReloads, 1);

      await _openAction(tester, 'outbound-start-delivery');
      await _checkAndSubmit(tester);
      await tester.pumpAndSettle();
      expect(
        harness.commandRepository.commands.map((command) => command.action),
        [OutboundTaskAction.acceptGoods, OutboundTaskAction.startDelivery],
      );
      expect(find.text('Đang vận chuyển'), findsOneWidget);
      expect(find.byKey(const ValueKey('outbound-accept-goods')), findsNothing);
      expect(
        find.byKey(const ValueKey('outbound-start-delivery')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('completion-open')), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Báo giao thất bại'),
            )
            .onPressed,
        isNotNull,
      );
      expect(harness.listReloads, 2);
    },
  );

  testWidgets('slow response and repeated taps dispatch one command', (
    tester,
  ) async {
    final harness = _ActionHarness();
    addTearDown(harness.close);
    final response = Completer<void>();
    harness.commandRepository.handler = (_) async {
      await response.future;
      harness.repository.remote = _details(status: DeliveryTaskStatus.accepted);
    };
    await _pumpReady(tester, harness);

    final action = find.byKey(const ValueKey('outbound-accept-goods'));
    await tester.drag(
      find.byKey(const ValueKey('task-detail-scroll')),
      const Offset(0, -1000),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.tap(action, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('outbound-confirm-submit')),
      findsOneWidget,
    );
    await _checkAndSubmit(tester);
    await tester.pump();
    expect(harness.commandRepository.commands, hasLength(1));
    expect(
      find.byKey(const ValueKey('outbound-action-loading')),
      findsOneWidget,
    );
    expect(tester.widget<OutlinedButton>(action).onPressed, isNull);

    response.complete();
    await tester.pumpAndSettle();
    expect(find.text('Đã nhận hàng'), findsOneWidget);
  });

  testWidgets('timeout retry reuses the exact command key and payload', (
    tester,
  ) async {
    final harness = _ActionHarness();
    addTearDown(harness.close);
    var attempts = 0;
    harness.commandRepository.handler = (command) async {
      harness.repository.remote = _details(status: DeliveryTaskStatus.accepted);
      if (attempts++ == 0) throw TimeoutException('response lost');
    };
    await _pumpReady(tester, harness);
    await _openAction(tester, 'outbound-accept-goods');
    await _checkAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('outbound-action-error')), findsOneWidget);
    expect(find.textContaining('Chưa xác định kết quả'), findsOneWidget);
    expect(find.byKey(const ValueKey('outbound-action-retry')), findsOneWidget);
    expect(harness.commandRepository.commands, hasLength(1));
    expect(harness.listReloads, 0);

    await tester.tap(find.byKey(const ValueKey('outbound-action-retry')));
    await tester.pumpAndSettle();
    expect(harness.commandRepository.commands, hasLength(2));
    expect(
      harness.commandRepository.commands[0],
      same(harness.commandRepository.commands[1]),
    );
    expect(harness.commandRepository.commands[0].requestId, _requestId);
    expect(
      harness.commandRepository.commands[1].action,
      OutboundTaskAction.acceptGoods,
    );
    expect(find.text('Đã nhận hàng'), findsOneWidget);
    expect(harness.listReloads, 1);
  });

  testWidgets('ACK read failure exposes read retry without sending again', (
    tester,
  ) async {
    final harness = _ActionHarness();
    addTearDown(harness.close);
    harness.commandRepository.handler = (_) async {
      harness.repository.remote = _details(status: DeliveryTaskStatus.accepted);
      harness.repository.readFailures.add(TimeoutException('detail read lost'));
    };
    await _pumpReady(tester, harness);
    await _openAction(tester, 'outbound-accept-goods');
    await _checkAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(harness.commandRepository.commands, hasLength(1));
    expect(find.byKey(const ValueKey('task-detail-retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('outbound-action-retry')), findsNothing);

    // The shared detail provider was invalidated by the authoritative read.
    // Restore the visible detail projection first; the action retry below is
    // still read-only because the command remains acknowledged in the VM.
    await tester.tap(find.byKey(const ValueKey('task-detail-retry')));
    await tester.pumpAndSettle();
    expect(find.text('Đã nhận hàng'), findsOneWidget);
    expect(find.byKey(const ValueKey('outbound-action-retry')), findsOneWidget);
    final beforeRetryReads = harness.repository.detailReads;
    final actionRetry = find.byKey(const ValueKey('outbound-action-retry'));
    await tester.ensureVisible(actionRetry);
    await tester.pump();
    await tester.tap(actionRetry);
    await tester.pumpAndSettle();

    expect(harness.commandRepository.commands, hasLength(1));
    expect(harness.repository.detailReads, greaterThan(beforeRetryReads));
    expect(harness.listReloads, 1);
    expect(find.text('Đã nhận hàng'), findsOneWidget);
  });

  testWidgets('stale business code remains visible without local success', (
    tester,
  ) async {
    final harness = _ActionHarness();
    addTearDown(harness.close);
    harness.commandRepository.handler = (_) async {
      throw const OutboundBusinessFailure(
        OutboundBusinessFailureCode.attemptLimit,
      );
    };
    await _pumpReady(tester, harness);
    await _openAction(tester, 'outbound-accept-goods');
    await _checkAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(harness.commandRepository.commands, hasLength(1));
    expect(find.text('Đơn đã đạt giới hạn số lần giao.'), findsOneWidget);
    expect(find.text('Đã phân công'), findsOneWidget);
    expect(find.text('Đã nhận hàng'), findsNothing);
    expect(find.byKey(const ValueKey('outbound-start-delivery')), findsNothing);
  });

  testWidgets('permission denial does not manufacture accepted state', (
    tester,
  ) async {
    final harness = _ActionHarness();
    addTearDown(harness.close);
    harness.commandRepository.handler = (_) async {
      throw const OutboundCommandFailure(
        OutboundCommandFailureCode.permissionDenied,
      );
    };
    await _pumpReady(tester, harness);
    await _openAction(tester, 'outbound-accept-goods');
    await _checkAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(harness.commandRepository.commands, hasLength(1));
    expect(find.text('Đã phân công'), findsOneWidget);
    expect(find.text('Đã nhận hàng'), findsNothing);
    expect(find.byKey(const ValueKey('outbound-start-delivery')), findsNothing);
  });

  testWidgets('session epoch change closes confirmation and redacts detail', (
    tester,
  ) async {
    final harness = _ActionHarness();
    addTearDown(harness.close);
    await _pumpReady(tester, harness);
    await _openAction(tester, 'outbound-accept-goods');

    harness.sessions.add(_expiredSession);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('outbound-confirm-submit')), findsNothing);
    expect(find.text('Nguyễn Văn A'), findsNothing);
    expect(find.text('0900000000'), findsNothing);
    expect(find.text('Phiên đăng nhập đã hết hạn.'), findsOneWidget);
    expect(harness.commandRepository.commands, isEmpty);
  });

  testWidgets('expired session blocks action and never reads private detail', (
    tester,
  ) async {
    final harness = _ActionHarness();
    addTearDown(harness.close);
    await _pumpReady(tester, harness, session: _expiredSession);

    expect(find.text('Phiên đăng nhập đã hết hạn.'), findsOneWidget);
    expect(find.text('Nguyễn Văn A'), findsNothing);
    expect(find.byKey(const ValueKey('outbound-accept-goods')), findsNothing);
    expect(harness.repository.detailReads, 0);
    expect(harness.commandRepository.commands, isEmpty);
  });

  testWidgets(
    'third outbound attempt is guarded and eligible transit exposes failure',
    (tester) async {
      final thirdAttempt = _ActionHarness(initial: _details(attemptNumber: 3));
      addTearDown(thirdAttempt.close);
      await _pumpReady(tester, thirdAttempt);
      expect(find.byKey(const ValueKey('outbound-accept-goods')), findsNothing);
      expect(
        find.byKey(const ValueKey('outbound-start-delivery')),
        findsNothing,
      );
      expect(find.text('Lần dự kiến: 3 / 2'), findsOneWidget);

      final transit = _ActionHarness(
        initial: _details(
          status: DeliveryTaskStatus.inTransit,
          attemptNumber: 2,
        ),
      );
      addTearDown(transit.close);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _pumpReady(tester, transit);
      for (final label in ['Báo giao thất bại']) {
        final button = find.widgetWithText(OutlinedButton, label);
        expect(button, findsOneWidget);
        expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
      }
      expect(transit.commandRepository.commands, isEmpty);
    },
  );

  testWidgets(
    'production detail action is usable at a narrow large-text layout',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final harness = _ActionHarness();
      addTearDown(harness.close);
      await _pumpReady(tester, harness, textScale: 2);
      final action = find.byKey(const ValueKey('outbound-accept-goods'));
      await tester.ensureVisible(action);
      expect(tester.takeException(), isNull);
    },
  );
}

DeliveryTaskDetails _details({
  DeliveryTaskStatus status = DeliveryTaskStatus.assigned,
  int attemptNumber = 1,
}) {
  final accepted = status.index >= DeliveryTaskStatus.accepted.index;
  final started = status.index >= DeliveryTaskStatus.inTransit.index;
  return DeliveryTaskDetails(
    task: DeliveryTaskSnapshot(
      taskId: _taskId,
      kind: DeliveryTaskKind.outbound,
      status: status,
      attemptNumber: attemptNumber,
      scope: DeliverySnapshotScope.current,
      orderId: '22222222-2222-4222-8222-222222222222',
      amountToCollectVnd: 550000,
      destination: _destination,
      assignedAt: DateTime.utc(2026, 10, 26, 1),
      acceptedAt: accepted ? DateTime.utc(2026, 10, 26, 2) : null,
      startedAt: started ? DateTime.utc(2026, 10, 26, 3) : null,
      itemSource: DeliveryItemSource.orderSnapshot,
    ),
    items: [
      DeliveryTaskItem(
        itemId: '44444444-4444-4444-8444-444444444444',
        itemSource: DeliveryItemSource.orderSnapshot,
        productName: 'Bóng đá',
        variantLabel: 'Size 5',
        quantity: 2,
      ),
    ],
  );
}

DeliveryTaskDetails _after(
  OutboundTaskAction action,
  DeliveryTaskDetails current,
) => _details(
  status: action == OutboundTaskAction.acceptGoods
      ? DeliveryTaskStatus.accepted
      : DeliveryTaskStatus.inTransit,
  attemptNumber: current.task.attemptNumber,
);

const _destination = DeliveryDestination(
  name: 'Nguyễn Văn A',
  phone: '0900000000',
  address: 'Hà Nội',
  latitude: 21.028511,
  longitude: 105.804817,
);
