import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_reporting.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';
import 'package:sports_store/features/deliveries/domain/repositories/delivery_reporting_repository.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_reporting_providers.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_reporting_view_model.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/outbound_result_gate.dart';
import 'package:sports_store/features/deliveries/presentation/widgets/delivery_reporting_action.dart';

const _taskId = '11111111-1111-4111-8111-111111111111';
const _requestId = '22222222-2222-4222-8222-222222222222';
const _orderId = '33333333-3333-4333-8333-333333333333';
const _itemId = '44444444-4444-4444-8444-444444444444';
const _eventId = '55555555-5555-4555-8555-555555555555';

final class _ReportingRepo implements DeliveryReportingRepository {
  ReportingContext value = _context();
  final commands = <ReportingCommand>[];
  Future<ReportingAck> Function(ReportingCommand command)? handler;
  Future<ReportingContext> Function(String taskId)? contextHandler;
  var contextReads = 0;

  @override
  Future<ReportingContext> getContext(String taskId) async {
    contextReads++;
    if (taskId != value.taskId) throw StateError('wrong task');
    final read = contextHandler;
    if (read != null) return read(taskId);
    return value;
  }

  @override
  Future<ReportingAck> execute(ReportingCommand command) async {
    commands.add(command);
    final execute = handler;
    if (execute != null) return execute(command);
    return _ack(command);
  }
}

final class _Harness {
  final sessions = StreamController<OperationalSession>.broadcast();
  final repo = _ReportingRepo();
  var detailsRefreshes = 0;
  var listRefreshes = 0;
  late final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      operationalSessionProvider.overrideWith((ref) => sessions.stream),
      deliveryReportingRepositoryProvider.overrideWithValue(repo),
      deliveryReportingRequestIdProvider.overrideWithValue(() => _requestId),
      deliveryReportingDetailsReloadProvider.overrideWith((ref) {
        return (taskId) async {
          detailsRefreshes++;
          return _details();
        };
      }),
      deliveryReportingTaskListReloadProvider.overrideWith((ref) {
        return () async => listRefreshes++;
      }),
    ],
  );

  void login({String userId = 'shipper-a'}) => sessions.add(
    OperationalSession(userId: userId, generation: detailsRefreshes + 1),
  );

  Future<void> close() async {
    container.dispose();
    await sessions.close();
  }
}

Future<void> _settle(ProviderContainer container, bool Function() done) async {
  for (var index = 0; index < 100; index++) {
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    if (done()) return;
  }
  fail('reporting provider did not settle');
}

void main() {
  test(
    'an older context error cannot replace a newer authorized snapshot',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      final provider = deliveryReportingViewModelProvider(_taskId);
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      harness.login();
      await _settle(
        harness.container,
        () => harness.container.read(provider).canHandover,
      );
      final older = Completer<ReportingContext>();
      var reads = 0;
      harness.repo.contextHandler = (_) async {
        if (++reads == 1) return older.future;
        return _context(canHandover: false, items: const []);
      };
      final vm = harness.container.read(provider.notifier);
      final oldRead = vm.refreshContext();
      await _settle(harness.container, () => reads == 1);
      await vm.refreshContext();
      older.completeError(
        const OperationalFailure(OperationalFailureCode.network),
      );
      await oldRead;
      final state = harness.container.read(provider);
      expect(state.context.hasError, isFalse);
      expect(state.context.requireValue.canHandover, isFalse);
      expect(state.canIncident, isTrue);
      expect(state.requiresReadRetry, isFalse);
    },
  );

  test(
    'timeout retains exact reporting key/payload and blocks other actions',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      final provider = deliveryReportingViewModelProvider(_taskId);
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      harness.login();
      await _settle(
        harness.container,
        () => harness.container.read(provider).canHandover,
      );

      harness.repo.handler = (_) async => throw TimeoutException('uncertain');
      final vm = harness.container.read(provider.notifier);
      await vm.submitHandover(
        sessionRevision: vm.sessionRevisionForConfirmation,
      );

      final state = harness.container.read(provider);
      expect(state.pendingCommand, isNotNull);
      expect(state.pendingCommand!.requestId, _requestId);
      expect(state.pendingCommand!.items, _context().items);
      expect(
        harness.container.read(outboundResultGateProvider(_taskId)),
        same(vm),
      );
      expect(harness.detailsRefreshes, 0);
      expect(harness.listRefreshes, 0);

      harness.repo.handler = (command) async => _ack(command);
      await vm.retry();
      expect(harness.repo.commands, hasLength(2));
      expect(harness.repo.commands[0], harness.repo.commands[1]);
      expect(harness.container.read(provider).pendingCommand, isNull);
      expect(harness.detailsRefreshes, 1);
      expect(harness.listRefreshes, 1);
    },
  );

  test('incident reason is validated before dispatch and ordinary failure stays separate', () async {
    final harness = _Harness();
    addTearDown(harness.close);
    final provider = deliveryReportingViewModelProvider(_taskId);
    final subscription = harness.container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    harness.login();
    await _settle(
      harness.container,
      () => harness.container.read(provider).canIncident,
    );

    final vm = harness.container.read(provider.notifier);
    await vm.submitIncident(
      kind: ReportingIncidentKind.damaged,
      reason: ' \n\t ',
      sessionRevision: vm.sessionRevisionForConfirmation,
    );
    expect(harness.repo.commands, isEmpty);
    expect(
      harness.container.read(provider).error?.code,
      OutboundCommandFailureCode.invalidData,
    );
  });

  test(
    'server business error is surfaced without fake completion or pending key',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      final provider = deliveryReportingViewModelProvider(_taskId);
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      harness.login();
      await _settle(
        harness.container,
        () => harness.container.read(provider).canHandover,
      );
      harness.repo.handler = (_) async => throw const OutboundBusinessFailure(
        OutboundBusinessFailureCode.stateConflict,
      );

      final vm = harness.container.read(provider.notifier);
      await vm.submitHandover(
        sessionRevision: vm.sessionRevisionForConfirmation,
      );

      final state = harness.container.read(provider);
      expect(state.acknowledgement, isNull);
      expect(state.pendingCommand, isNull);
      expect(state.error, isA<OutboundBusinessFailure>());
      expect(state.error!.toString(), contains('staleState'));
    },
  );

  test(
    'late ACK after account switch cannot restore the old pending report',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      final provider = deliveryReportingViewModelProvider(_taskId);
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      harness.login();
      await _settle(
        harness.container,
        () => harness.container.read(provider).canHandover,
      );

      final response = Completer<ReportingAck>();
      harness.repo.handler = (_) => response.future;
      final vm = harness.container.read(provider.notifier);
      final oldRevision = vm.sessionRevisionForConfirmation;
      final write = vm.submitHandover(sessionRevision: oldRevision);
      await _settle(harness.container, () => harness.repo.commands.length == 1);

      harness.login(userId: 'shipper-b');
      await _settle(
        harness.container,
        () =>
            vm.sessionRevisionForConfirmation != oldRevision &&
            harness.container.read(provider).pendingCommand == null,
      );
      response.complete(_ack(harness.repo.commands.single));
      await write;
      final state = harness.container.read(provider);
      expect(state.acknowledgement, isNull);
      expect(state.pendingCommand, isNull);
      expect(harness.detailsRefreshes, 0);
    },
  );

  test(
    'ACK context read retry reconciles detail/list and releases the gate',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      final provider = deliveryReportingViewModelProvider(_taskId);
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      harness.login();
      await _settle(
        harness.container,
        () => harness.container.read(provider).canHandover,
      );
      final initialReads = harness.repo.contextReads;
      harness.repo.contextHandler = (_) async {
        if (harness.repo.contextReads == initialReads + 1) {
          throw TimeoutException('context read');
        }
        return harness.repo.value;
      };
      final vm = harness.container.read(provider.notifier);
      await vm.submitHandover(
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      expect(harness.container.read(provider).acknowledgement, isNotNull);
      expect(harness.container.read(provider).pendingCommand, isNull);
      expect(harness.container.read(provider).requiresReadRetry, isTrue);
      expect(
        harness.container.read(outboundResultGateProvider(_taskId)),
        same(vm),
      );

      await vm.retry();
      final state = harness.container.read(provider);
      expect(state.acknowledgement, isNotNull);
      expect(state.requiresReadRetry, isFalse);
      expect(harness.detailsRefreshes, 1);
      expect(harness.listRefreshes, 1);
      expect(
        harness.container.read(outboundResultGateProvider(_taskId)),
        isNull,
      );
    },
  );

  test(
    'same-user token refresh resumes an interrupted reconciliation',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      final provider = deliveryReportingViewModelProvider(_taskId);
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      harness.login();
      await _settle(
        harness.container,
        () => harness.container.read(provider).canHandover,
      );
      final initialReads = harness.repo.contextReads;
      harness.repo.contextHandler = (_) async {
        if (harness.repo.contextReads == initialReads + 1) {
          throw TimeoutException('context read');
        }
        return harness.repo.value;
      };
      final vm = harness.container.read(provider.notifier);
      await vm.submitHandover(
        sessionRevision: vm.sessionRevisionForConfirmation,
      );
      final oldRevision = vm.sessionRevisionForConfirmation;
      harness.login();
      await _settle(
        harness.container,
        () =>
            vm.sessionRevisionForConfirmation != oldRevision &&
            harness.detailsRefreshes == 1 &&
            harness.listRefreshes == 1 &&
            harness.container.read(outboundResultGateProvider(_taskId)) == null,
      );
      expect(harness.container.read(provider).acknowledgement, isNotNull);
      expect(harness.container.read(provider).requiresReadRetry, isFalse);
    },
  );

  test('permission denial exposes no reporting action', () async {
    final harness = _Harness();
    addTearDown(harness.close);
    final provider = deliveryReportingViewModelProvider(_taskId);
    final subscription = harness.container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    harness.repo.contextHandler = (_) async =>
        throw const OperationalFailure(OperationalFailureCode.permissionDenied);
    harness.login();
    await _settle(
      harness.container,
      () => harness.container.read(provider).context.hasError,
    );
    expect(harness.container.read(provider).canHandover, isFalse);
    expect(harness.container.read(provider).canIncident, isFalse);
    expect(harness.repo.commands, isEmpty);
  });

  test(
    'refreshContext updates eligibility without dispatching a report',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      harness.repo.value = _context(
        status: DeliveryTaskStatus.assigned,
        canHandover: false,
        canIncident: false,
      );
      final provider = deliveryReportingViewModelProvider(_taskId);
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      harness.login();
      await _settle(
        harness.container,
        () => harness.container.read(provider).context.hasValue,
      );
      final vm = harness.container.read(provider.notifier);
      expect(harness.container.read(provider).canHandover, isFalse);
      expect(harness.container.read(provider).canIncident, isFalse);

      harness.repo.value = _context(
        status: DeliveryTaskStatus.inTransit,
        canHandover: false,
        canIncident: true,
      );
      await vm.refreshContext();
      expect(harness.container.read(provider).canHandover, isFalse);
      expect(harness.container.read(provider).canIncident, isTrue);
      expect(harness.repo.commands, isEmpty);
    },
  );

  testWidgets(
    'server flags and non-outbound contexts render no report buttons',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.close);
      harness.repo.value = _context(
        status: DeliveryTaskStatus.assigned,
        canHandover: false,
        canIncident: false,
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: harness.container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: DeliveryReportingAction(taskId: _taskId),
            ),
          ),
        ),
      );
      harness.login();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reporting-handover-open')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('reporting-incident-open')),
        findsNothing,
      );

      harness.repo.value = _context(
        status: DeliveryTaskStatus.delivered,
        canHandover: false,
        canIncident: false,
      );
      await harness.container
          .read(deliveryReportingViewModelProvider(_taskId).notifier)
          .refreshContext();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reporting-handover-open')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('reporting-incident-open')),
        findsNothing,
      );

      harness.repo.value = _context(
        kind: DeliveryTaskKind.returnPickup,
        status: DeliveryTaskStatus.failed,
        canHandover: true,
        canIncident: true,
      );
      await harness.container
          .read(deliveryReportingViewModelProvider(_taskId).notifier)
          .refreshContext();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reporting-handover-open')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('reporting-incident-open')),
        findsNothing,
      );
      expect(harness.repo.commands, isEmpty);
    },
  );

  testWidgets(
    'restricted cancelled task can report handover without completed/restock claim',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.close);
      harness.repo.value = _context(
        status: DeliveryTaskStatus.cancelled,
        orderStatus: 'awaiting_store_return',
        canHandover: true,
        canIncident: false,
      );
      harness.repo.handler = (command) async =>
          _ack(command, taskStatus: 'cancelled');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: harness.container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: DeliveryReportingAction(taskId: _taskId),
            ),
          ),
        ),
      );
      harness.login();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reporting-handover-open')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('reporting-handover-open')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('reporting-handover-confirmation')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('reporting-handover-confirm')),
      );
      await tester.pumpAndSettle();

      final state = harness.container.read(
        deliveryReportingViewModelProvider(_taskId),
      );
      expect(state.context.requireValue.status, DeliveryTaskStatus.cancelled);
      expect(harness.repo.commands, hasLength(1));
      expect(harness.repo.commands.single.isHandover, isTrue);
      expect(find.textContaining('Đã giao thành công'), findsNothing);
      expect(find.textContaining('Đã nhập lại tồn kho'), findsNothing);
    },
  );

  testWidgets(
    'incident dialog requires trimmed reason and surfaces safe API error',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.close);
      harness.repo.value = _context(
        status: DeliveryTaskStatus.inTransit,
        canHandover: false,
        canIncident: true,
      );
      harness.repo.handler = (_) async => throw const OutboundBusinessFailure(
        OutboundBusinessFailureCode.custodyUnresolved,
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: harness.container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: DeliveryReportingAction(taskId: _taskId),
            ),
          ),
        ),
      );
      harness.login();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reporting-incident-open')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reporting-incident-kind')));
      await tester.pumpAndSettle();
      expect(find.text('Hàng bị hỏng'), findsOneWidget);
      expect(find.text('Hàng bị mất'), findsOneWidget);
      expect(find.text('Sự cố khác'), findsOneWidget);
      await tester.tap(find.text('Hàng bị hỏng').last);
      await tester.enterText(
        find.byKey(const ValueKey('reporting-incident-reason')),
        '   ',
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('reporting-incident-confirm')),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const ValueKey('reporting-incident-reason')),
        '  Hộp hàng bị rách  ',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('reporting-incident-confirm')),
      );
      await tester.pumpAndSettle();

      expect(harness.repo.commands, hasLength(1));
      expect(
        harness.repo.commands.single.incidentKind,
        ReportingIncidentKind.damaged,
      );
      expect(harness.repo.commands.single.reason, 'Hộp hàng bị rách');
      expect(
        find.textContaining('Chưa xác minh được việc giữ hàng'),
        findsOneWidget,
      );
      expect(find.textContaining('CUSTODY_UNRESOLVED'), findsNothing);
    },
  );

  testWidgets(
    'handover confirmation shows exact items and non-receipt wording',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.close);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: harness.container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: DeliveryReportingAction(taskId: _taskId),
            ),
          ),
        ),
      );
      harness.login();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('reporting-handover-open')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Bóng đá'), findsOneWidget);
      expect(
        find.textContaining('không phải xác nhận nhận hàng'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('reporting-handover-confirm')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(
        find.byKey(const ValueKey('reporting-handover-confirmation')),
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('reporting-handover-confirm')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(
        find.byKey(const ValueKey('reporting-handover-confirm')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('chưa phải xác nhận'), findsOneWidget);
      expect(find.textContaining('Đã nhận hàng thành công'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a conflicting outbound action closes the reporting dialog', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.close);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: DeliveryReportingAction(taskId: _taskId)),
        ),
      ),
    );
    harness.login();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reporting-handover-open')));
    await tester.pumpAndSettle();
    final owner = Object();
    expect(
      harness.container
          .read(outboundResultGateProvider(_taskId).notifier)
          .acquire(owner),
      isTrue,
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('reporting-handover-confirm')),
      findsNothing,
    );
    expect(harness.repo.commands, isEmpty);
  });
}

ReportingContext _context({
  DeliveryTaskKind kind = DeliveryTaskKind.outbound,
  DeliveryTaskStatus status = DeliveryTaskStatus.failed,
  String? orderStatus = 'awaiting_store_return',
  bool canHandover = true,
  bool canIncident = true,
  bool handoverReported = false,
  List<ReportItem>? items,
}) => ReportingContext(
  taskId: _taskId,
  kind: kind,
  status: status,
  orderStatus: orderStatus,
  canHandover: canHandover,
  canIncident: canIncident,
  handoverReported: handoverReported,
  items:
      items ??
      [
        const ReportItem(
          orderItemId: _itemId,
          productName: 'Bóng đá',
          variantLabel: 'Size 5',
          quantity: 2,
        ),
      ],
);

DeliveryTaskDetails _details() => DeliveryTaskDetails(
  task: DeliveryTaskSnapshot(
    taskId: _taskId,
    kind: DeliveryTaskKind.outbound,
    status: DeliveryTaskStatus.failed,
    attemptNumber: 1,
    scope: DeliverySnapshotScope.restricted,
    orderId: _orderId,
    itemSource: DeliveryItemSource.unavailable,
  ),
  items: const [],
);

ReportingAck _ack(
  ReportingCommand command, {
  String taskStatus = 'failed',
  String orderStatus = 'awaiting_store_return',
}) => ReportingAck(
  taskId: command.taskId,
  orderId: _orderId,
  operation: command.operation.rpcName,
  requestId: command.requestId,
  eventId: _eventId,
  reportedAt: DateTime.utc(2026, 10, 27, 3),
  taskStatus: taskStatus,
  orderStatus: orderStatus,
);
