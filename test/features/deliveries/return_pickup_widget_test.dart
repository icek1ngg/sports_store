import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_failure_command.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';
import 'package:sports_store/features/deliveries/domain/models/return_pickup_command.dart';
import 'package:sports_store/features/deliveries/domain/repositories/return_pickup_repository.dart';
import 'package:sports_store/features/deliveries/presentation/pages/delivery_task_detail_page.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_task_detail_view_model.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/return_pickup_providers.dart';
import 'package:sports_store/features/deliveries/presentation/widgets/return_pickup_action.dart';

const _taskId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _returnRequestId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const _orderId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const _requestId = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
const _itemA = '11111111-1111-4111-8111-111111111111';
const _itemB = '22222222-2222-4222-8222-222222222222';

const _expiredSession = OperationalSession(
  userId: null,
  generation: 0,
  failure: OperationalFailure(OperationalFailureCode.sessionExpired),
);

class _PickupRepository implements ReturnPickupRepository {
  final commands = <ReturnPickupCommand>[];
  Future<ReturnPickupAck> Function(ReturnPickupCommand command)? handler;

  @override
  Future<ReturnPickupAck> execute(ReturnPickupCommand command) {
    commands.add(command);
    final callback = handler;
    return callback == null
        ? Future<ReturnPickupAck>.value(_ack(command))
        : callback(command);
  }
}

class _FixtureDetailViewModel extends DeliveryTaskDetailViewModel {
  _FixtureDetailViewModel(super.taskId, this.initial);

  final AsyncValue<DeliveryTaskDetails> initial;

  @override
  AsyncValue<DeliveryTaskDetails> build() => initial;
}

class _Harness {
  _Harness(this.initial, {this.handoverStatus}) {
    sessions = StreamController<OperationalSession>.broadcast();
    repository = _PickupRepository();
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        operationalSessionProvider.overrideWith((ref) => sessions.stream),
        returnPickupRepositoryProvider.overrideWithValue(repository),
        returnPickupRequestIdProvider.overrideWithValue(() => _requestId),
        returnPickupDetailsReloadProvider.overrideWithValue((_) async {
          reloadCount++;
          return reloaded;
        }),
        returnPickupTaskListReloadProvider.overrideWithValue(() async {
          taskListReloadCount++;
        }),
        returnPickupHandoverStatusProvider.overrideWithValue(
          handoverStatus ??
              (_) => Future<ReturnPickupHandoverStatus>.error(
                UnsupportedError('marker unavailable in this fixture'),
              ),
        ),
        deliveryTaskDetailViewModelProvider(initial.task.taskId).overrideWith(
          () =>
              _FixtureDetailViewModel(initial.task.taskId, AsyncData(initial)),
        ),
      ],
    );
  }

  final DeliveryTaskDetails initial;
  final Future<ReturnPickupHandoverStatus> Function(String)? handoverStatus;
  late final StreamController<OperationalSession> sessions;
  late final _PickupRepository repository;
  late final ProviderContainer container;
  late DeliveryTaskDetails reloaded = initial;
  var reloadCount = 0;
  var taskListReloadCount = 0;

  Future<void> dispose() async {
    container.dispose();
    await sessions.close();
  }
}

void main() {
  testWidgets('collect dialog is manual, exact-full, and sends one command', (
    tester,
  ) async {
    final h = _Harness(_assignedDetails());
    addTearDown(h.dispose);
    h.reloaded = _inTransitDetails();
    await tester.pumpWidget(_actionApp(h.container));
    h.sessions.add(
      const OperationalSession(userId: 'shipper-a', generation: 1),
    );
    await _pumpUntil(tester, find.byKey(const ValueKey('pickup-collect-open')));

    // Opening MH11 must never auto-accept/collect anything.
    expect(h.repository.commands, isEmpty);
    await tester.tap(find.byKey(const ValueKey('pickup-collect-open')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Số lượng: 2'), findsOneWidget);
    expect(find.textContaining('Số lượng: 1'), findsOneWidget);
    final confirm = find.byKey(const ValueKey('pickup-collect-confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    // The server contract is exact-full: a single manual checkbox is required.
    await tester.tap(find.byKey(const ValueKey('pickup-collect-all')));
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('pickup-collect-confirmed')),
    );
    expect(h.repository.commands, hasLength(1));
    final command = h.repository.commands.single;
    expect(command.operation, ReturnPickupOperation.collect);
    expect(command.taskId, _taskId);
    expect(command.requestId, _requestId);
    expect(command.returnRequestId, _returnRequestId);
    expect(command.orderId, _orderId);
    expect(command.items, const [
      ReturnPickupItem(returnItemId: _itemA, quantity: 2),
      ReturnPickupItem(returnItemId: _itemB, quantity: 1),
    ]);
    expect(h.reloadCount, 1);
    expect(h.taskListReloadCount, 1);
  });

  testWidgets('duplicate confirmation taps dispatch exactly one RPC command', (
    tester,
  ) async {
    final h = _Harness(_assignedDetails());
    addTearDown(h.dispose);
    h.reloaded = _inTransitDetails();
    await tester.pumpWidget(_actionApp(h.container));
    h.sessions.add(
      const OperationalSession(userId: 'shipper-a', generation: 1),
    );
    await _pumpUntil(tester, find.byKey(const ValueKey('pickup-collect-open')));
    await tester.tap(find.byKey(const ValueKey('pickup-collect-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pickup-collect-all')));
    await tester.pump();
    final confirm = find.byKey(const ValueKey('pickup-collect-confirm'));
    await tester.tap(confirm);
    await tester.tap(confirm, warnIfMissed: false);
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('pickup-collect-confirmed')),
    );
    expect(h.repository.commands, hasLength(1));
  });

  testWidgets('Other failure requires description and trims reason payload', (
    tester,
  ) async {
    final h = _Harness(_assignedDetails());
    addTearDown(h.dispose);
    h.reloaded = DeliveryTaskDetails(
      task: DeliveryTaskSnapshot(
        taskId: _taskId,
        kind: DeliveryTaskKind.returnPickup,
        status: DeliveryTaskStatus.failed,
        attemptNumber: 1,
        scope: DeliverySnapshotScope.restricted,
        itemSource: DeliveryItemSource.unavailable,
        completedAt: DateTime.utc(2026, 10, 28, 8),
      ),
      items: [],
    );
    await tester.pumpWidget(_actionApp(h.container));
    h.sessions.add(
      const OperationalSession(userId: 'shipper-a', generation: 1),
    );
    await _pumpUntil(tester, find.byKey(const ValueKey('pickup-failure-open')));
    await tester.tap(find.byKey(const ValueKey('pickup-failure-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pickup-failure-reason')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Khác').last);
    await tester.pump();
    final confirm = find.byKey(const ValueKey('pickup-failure-confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('pickup-failure-description')),
      '  cổng đóng  ',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('pickup-failure-confirmed')),
    );
    expect(h.repository.commands, hasLength(1));
    expect(h.repository.commands.single.reason, OutboundFailureReason.other);
    expect(h.repository.commands.single.trimmedDescription, 'cổng đóng');
  });

  testWidgets(
    'permission denial and business failure stay safe and pickup-only',
    (tester) async {
      final h = _Harness(_assignedDetails());
      addTearDown(h.dispose);
      h.repository.handler = (_) async {
        throw const OperationalFailure(OperationalFailureCode.permissionDenied);
      };
      await tester.pumpWidget(_actionApp(h.container));
      h.sessions.add(
        const OperationalSession(userId: 'shipper-a', generation: 1),
      );
      await _pumpUntil(
        tester,
        find.byKey(const ValueKey('pickup-collect-open')),
      );
      await _confirmCollection(tester);
      await _pumpUntil(tester, find.byKey(const ValueKey('pickup-error')));
      expect(
        find.text('Phiên làm việc hoặc quyền giao hàng đã thay đổi.'),
        findsOneWidget,
      );
      expect(find.textContaining('private'), findsNothing);
      expect(find.textContaining('/ 2'), findsNothing);
      expect(
        h.repository.commands.single.operation,
        ReturnPickupOperation.collect,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final business = _Harness(_assignedDetails());
      addTearDown(business.dispose);
      business.repository.handler = (_) async {
        throw const OutboundBusinessFailure(
          OutboundBusinessFailureCode.itemsMismatch,
        );
      };
      await tester.pumpWidget(_actionApp(business.container));
      business.sessions.add(
        const OperationalSession(userId: 'shipper-a', generation: 2),
      );
      await _pumpUntil(
        tester,
        find.byKey(const ValueKey('pickup-collect-open')),
      );
      await _confirmCollection(tester);
      await _pumpUntil(tester, find.byKey(const ValueKey('pickup-error')));
      expect(
        find.text('Thông tin hàng không khớp. Liên hệ quản lý để kiểm tra.'),
        findsOneWidget,
      );
      expect(find.textContaining('STATE_CONFLICT'), findsNothing);
      expect(find.textContaining('PGRST'), findsNothing);
    },
  );

  testWidgets(
    'in-transit page shows full collected quantities and blocked handover',
    (tester) async {
      final details = _inTransitDetails();
      final h = _Harness(details);
      addTearDown(h.dispose);
      await tester.pumpWidget(
        _actionApp(
          h.container,
          child: DeliveryTaskDetailPage(taskId: details.task.taskId),
        ),
      );
      h.sessions.add(
        const OperationalSession(userId: 'shipper-a', generation: 1),
      );
      await tester.pumpAndSettle();
      expect(find.text('Đã nhận: 2'), findsOneWidget);
      expect(find.text('Đã nhận: 1'), findsOneWidget);
      expect(find.text('Không thu tiền'), findsOneWidget);
      expect(find.text('Ghi chú chưa khả dụng.'), findsOneWidget);
      expect(find.textContaining('/ 2'), findsNothing);
      expect(find.textContaining('ngân'), findsNothing);
      expect(find.textContaining('video'), findsNothing);
      expect(
        find.byKey(const ValueKey('pickup-handover-disabled')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('pickup-handover-disabled')),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.text(
          'Báo bàn giao chưa khả dụng. Liên hệ chủ cửa hàng; việc nhận và kiểm tra được xác nhận riêng.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'handover confirmation is full-plan, idempotent, and marker-backed',
    (tester) async {
      var reported = false;
      final h = _Harness(
        _inTransitDetails(),
        handoverStatus: (_) async => ReturnPickupHandoverStatus(
          taskId: _taskId,
          reported: reported,
          reportedAt: reported ? DateTime.utc(2026, 10, 28, 9) : null,
        ),
      );
      addTearDown(h.dispose);
      h.repository.handler = (command) async {
        expect(command.operation, ReturnPickupOperation.handover);
        reported = true;
        return _ack(command);
      };
      await tester.pumpWidget(_actionApp(h.container));
      h.sessions.add(
        const OperationalSession(userId: 'shipper-a', generation: 1),
      );
      await _pumpUntil(
        tester,
        find.byKey(const ValueKey('pickup-handover-open')),
      );
      await tester.tap(find.byKey(const ValueKey('pickup-handover-open')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Số lượng: 2'), findsOneWidget);
      expect(find.textContaining('Số lượng: 1'), findsOneWidget);
      final confirm = find.byKey(const ValueKey('pickup-handover-confirm'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('pickup-handover-all')));
      await tester.pump();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await tester.tap(confirm);
      await _pumpUntil(
        tester,
        find.byKey(const ValueKey('pickup-handover-confirmed')),
      );
      expect(h.repository.commands, hasLength(1));
      expect(h.repository.commands.single.items, const [
        ReturnPickupItem(returnItemId: _itemA, quantity: 2),
        ReturnPickupItem(returnItemId: _itemB, quantity: 1),
      ]);
      expect(find.byKey(const ValueKey('pickup-handover-open')), findsNothing);
      expect(
        find.byKey(const ValueKey('pickup-handover-reported')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'collect dialog remains scrollable at narrow width and large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = _Harness(_assignedDetails());
      addTearDown(h.dispose);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: _actionApp(h.container),
        ),
      );
      h.sessions.add(
        const OperationalSession(userId: 'shipper-a', generation: 1),
      );
      await _pumpUntil(
        tester,
        find.byKey(const ValueKey('pickup-collect-open')),
      );
      await tester.tap(find.byKey(const ValueKey('pickup-collect-open')));
      await tester.pumpAndSettle();
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('redelivery remains unchanged and has no pickup action', (
    tester,
  ) async {
    final details = _redeliveryDetails();
    final vm = _FixtureDetailViewModel(details.task.taskId, AsyncData(details));
    await tester.pumpWidget(_pageApp(details.task.taskId, vm));
    expect(find.text('Giao lại miễn phí'), findsWidgets);
    expect(find.text('Không thu COD'), findsOneWidget);
    expect(find.byKey(const ValueKey('pickup-collect-open')), findsNothing);
    expect(find.byKey(const ValueKey('pickup-failure-open')), findsNothing);
    expect(find.text('Báo bàn giao cửa hàng'), findsNothing);
  });
}

Future<void> _confirmCollection(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('pickup-collect-open')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('pickup-collect-all')));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('pickup-collect-confirm')));
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var index = 0; index < 100; index++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Widget did not settle: $finder');
}

Widget _actionApp(ProviderContainer container, {Widget? child}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: child ?? const ReturnPickupAction(taskId: _taskId),
        ),
      ),
    );

Widget _pageApp(String taskId, _FixtureDetailViewModel vm) => ProviderScope(
  overrides: [
    deliveryTaskDetailViewModelProvider(taskId).overrideWith(() => vm),
    operationalSessionProvider.overrideWithValue(
      const AsyncData(_expiredSession),
    ),
  ],
  child: MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: DeliveryTaskDetailPage(taskId: taskId)),
  ),
);

ReturnPickupAck _ack(ReturnPickupCommand command) {
  final timestamp = DateTime.utc(2026, 10, 28, 8);
  final handover = command.isHandover;
  return ReturnPickupAck(
    taskId: command.taskId,
    returnRequestId: command.returnRequestId,
    orderId: command.orderId,
    operation: command.operation,
    taskStatus: command.isCollect || handover ? 'in_transit' : 'failed',
    returnStatus: command.isCollect || handover
        ? 'returning_to_store'
        : 'awaiting_return_pickup',
    eventId: '99999999-9999-4999-8999-999999999999',
    requestId: command.requestId,
    occurredAt: timestamp,
    acceptedAt: command.isCollect ? timestamp : null,
    startedAt: command.isCollect ? timestamp : null,
    reportedAt: handover ? timestamp : null,
    failedAt: command.isFail ? timestamp : null,
    reason: command.reason,
    description: command.trimmedDescription,
  );
}

DeliveryTaskDetails _assignedDetails() => DeliveryTaskDetails(
  task: DeliveryTaskSnapshot(
    taskId: _taskId,
    kind: DeliveryTaskKind.returnPickup,
    status: DeliveryTaskStatus.assigned,
    attemptNumber: 1,
    scope: DeliverySnapshotScope.current,
    orderId: _orderId,
    returnRequestId: _returnRequestId,
    amountToCollectVnd: 0,
    destination: _destination,
    assignedAt: _assignedAt,
    itemSource: DeliveryItemSource.returnPlan,
  ),
  items: [
    DeliveryTaskItem(
      itemId: _itemA,
      itemSource: DeliveryItemSource.returnPlan,
      productName: 'Bóng đá',
      quantity: 2,
      quantityCollected: 0,
    ),
    DeliveryTaskItem(
      itemId: _itemB,
      itemSource: DeliveryItemSource.returnPlan,
      productName: 'Giày thể thao',
      quantity: 1,
      quantityCollected: 0,
    ),
  ],
);

DeliveryTaskDetails _inTransitDetails() {
  final assigned = _assignedDetails();
  final acceptedAt = DateTime.utc(2026, 10, 28, 8);
  return DeliveryTaskDetails(
    task: DeliveryTaskSnapshot(
      taskId: assigned.task.taskId,
      kind: assigned.task.kind,
      status: DeliveryTaskStatus.inTransit,
      attemptNumber: 1,
      scope: DeliverySnapshotScope.current,
      orderId: assigned.task.orderId,
      returnRequestId: assigned.task.returnRequestId,
      amountToCollectVnd: 0,
      destination: assigned.task.destination,
      assignedAt: assigned.task.assignedAt,
      acceptedAt: acceptedAt,
      startedAt: acceptedAt,
      itemSource: DeliveryItemSource.returnPlan,
    ),
    items: [
      DeliveryTaskItem(
        itemId: _itemA,
        itemSource: DeliveryItemSource.returnPlan,
        productName: 'Bóng đá',
        quantity: 2,
        quantityCollected: 2,
      ),
      DeliveryTaskItem(
        itemId: _itemB,
        itemSource: DeliveryItemSource.returnPlan,
        productName: 'Giày thể thao',
        quantity: 1,
        quantityCollected: 1,
      ),
    ],
  );
}

DeliveryTaskDetails _redeliveryDetails() => DeliveryTaskDetails(
  task: DeliveryTaskSnapshot(
    taskId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    kind: DeliveryTaskKind.redelivery,
    status: DeliveryTaskStatus.accepted,
    attemptNumber: 1,
    scope: DeliverySnapshotScope.current,
    orderId: _orderId,
    returnRequestId: _returnRequestId,
    amountToCollectVnd: 0,
    destination: _destination,
    itemSource: DeliveryItemSource.unavailableRedeliveryPlan,
  ),
  items: [],
);

final _assignedAt = DateTime.utc(2026, 10, 28, 7);
const _destination = DeliveryDestination(
  name: 'Khách hàng Hà Nội',
  phone: '0900000000',
  address: 'Hà Nội',
  latitude: 21.028511,
  longitude: 105.804817,
);
