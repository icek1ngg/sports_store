import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';
import 'package:sports_store/features/deliveries/presentation/pages/delivery_task_detail_page.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_task_detail_view_model.dart';

const _taskId = '11111111-1111-4111-8111-111111111111';
const _returnTaskId = '66666666-6666-4666-8666-666666666666';
const _redeliveryTaskId = '88888888-8888-4888-8888-888888888888';

class _FixtureDetailViewModel extends DeliveryTaskDetailViewModel {
  _FixtureDetailViewModel(super.taskId, this.initial);

  final AsyncValue<DeliveryTaskDetails> initial;
  var refreshes = 0;

  @override
  AsyncValue<DeliveryTaskDetails> build() => initial;

  @override
  Future<void> refresh() async {
    refreshes++;
    state = initial;
  }
}

void main() {
  for (final kind in [DeliveryTaskKind.outbound, DeliveryTaskKind.redelivery]) {
    testWidgets('mock scenario: ${kind.value} in transit is read-only', (
      tester,
    ) async {
      final details = _inTransitDetails(kind);
      final vm = _FixtureDetailViewModel(
        details.task.taskId,
        AsyncData(details),
      );
      await tester.pumpWidget(_app(details.task.taskId, vm));
      expect(find.text('Đang vận chuyển'), findsOneWidget);
      final actions = kind == DeliveryTaskKind.outbound
          ? ['Giao thành công', 'Báo giao thất bại']
          : ['Giao lại thành công', 'Báo giao lại thất bại'];
      for (final label in actions) {
        final action = find.widgetWithText(OutlinedButton, label);
        expect(action, findsOneWidget);
        expect(tester.widget<OutlinedButton>(action).onPressed, isNull);
      }
      expect(find.text('Nhận hàng'), findsNothing);
      expect(find.text('Bắt đầu giao lại'), findsNothing);
      if (kind == DeliveryTaskKind.outbound) {
        expect(find.text('Lần giao: 1 / 2'), findsOneWidget);
        expect(find.text('550.000 đ'), findsOneWidget);
        expect(find.text('Không thu COD'), findsNothing);
      } else {
        expect(find.text('Không thu COD'), findsOneWidget);
        expect(
          find.text('Danh sách hàng giao lại chưa khả dụng.'),
          findsOneWidget,
        );
        expect(find.text('Lần giao: 1 / 2'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('renders current outbound projection without inventing data', (
    tester,
  ) async {
    final vm = _FixtureDetailViewModel(_taskId, AsyncData(_outboundDetails()));
    await tester.pumpWidget(_app(_taskId, vm));

    expect(find.text('Giao đơn hàng'), findsOneWidget);
    expect(find.text('Đã phân công'), findsOneWidget);
    expect(find.text(_taskId), findsOneWidget);
    expect(find.text('Nguyễn Văn A'), findsOneWidget);
    expect(find.text('0900000000'), findsOneWidget);
    expect(find.text('550.000 đ'), findsOneWidget);
    expect(find.text('Lần dự kiến: 1 / 2'), findsOneWidget);
    expect(find.text('Ảnh chưa được cung cấp'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey(
          'image-placeholder-44444444-4444-4444-8444-444444444444',
        ),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('task-detail-call')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-detail-map')), findsOneWidget);
    expect(
      find.text(
        'Gọi điện chưa khả dụng. Bạn có thể sao chép số điện thoại để liên hệ.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Chưa có chi tiết tiền hàng và phí giao hàng.'),
      findsOneWidget,
    );
    expect(find.text('Ghi chú chưa khả dụng.'), findsOneWidget);
    expect(find.text('Ghi chú riêng tư không được phép'), findsNothing);
    expect(find.text('Tổng COD cần thu'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('task-detail-call')),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('Không có khả năng gọi điện'), findsNothing);
    expect(find.text('Nhận hàng'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders return-pickup detail with collected quantity', (
    tester,
  ) async {
    final vm = _FixtureDetailViewModel(
      _returnTaskId,
      AsyncData(_returnPickupDetails()),
    );
    await tester.pumpWidget(_app(_returnTaskId, vm));

    expect(find.text('Lấy hàng hoàn'), findsOneWidget);
    expect(find.text('Đã nhận: 1'), findsOneWidget);
    expect(find.text('Không thu COD'), findsOneWidget);
    expect(find.text('Lần dự kiến: 1 / 2'), findsNothing);
    expect(find.text('Không áp dụng hạn mức 2 lần giao đi'), findsOneWidget);
    expect(find.text('Xác nhận lấy hàng'), findsOneWidget);
    expect(find.text('Bóng đá bị lỗi'), findsOneWidget);
  });

  testWidgets('renders redelivery as explicit item-plan unavailable', (
    tester,
  ) async {
    final vm = _FixtureDetailViewModel(
      _redeliveryTaskId,
      AsyncData(_redeliveryDetails()),
    );
    await tester.pumpWidget(_app(_redeliveryTaskId, vm));

    expect(find.text('Giao lại'), findsOneWidget);
    expect(find.text('Danh sách hàng giao lại chưa khả dụng.'), findsOneWidget);
    expect(find.text('Không thu COD'), findsOneWidget);
    expect(find.text('Không áp dụng hạn mức 2 lần giao đi'), findsOneWidget);
    expect(find.textContaining('/ 2'), findsNothing);
    expect(find.text('Bắt đầu giao lại'), findsOneWidget);
  });

  testWidgets('history projection does not render private detail fields', (
    tester,
  ) async {
    final vm = _FixtureDetailViewModel(_taskId, AsyncData(_historyDetails()));
    await tester.pumpWidget(_app(_taskId, vm));

    expect(find.text('Lịch sử'), findsOneWidget);
    expect(
      find.text('Thông tin người nhận và địa chỉ đã được giới hạn.'),
      findsOneWidget,
    );
    expect(find.text('Thông tin COD đã được giới hạn.'), findsOneWidget);
    expect(find.text('Nguyễn Văn A'), findsNothing);
    expect(find.text('0900000000'), findsNothing);
    expect(find.text('550.000 đ'), findsNothing);
    expect(find.text('Bóng đá'), findsNothing);
    expect(find.text('Dữ liệu riêng tư bị lộ'), findsNothing);
    expect(find.byKey(const ValueKey('task-detail-map')), findsNothing);
  });

  testWidgets('loading and failures never retain old private data', (
    tester,
  ) async {
    final loading = _FixtureDetailViewModel(_taskId, const AsyncLoading());
    await tester.pumpWidget(_app(_taskId, loading));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Nguyễn Văn A'), findsNothing);
    expect(find.byKey(const ValueKey('task-detail-retry')), findsNothing);

    final failure = _FixtureDetailViewModel(
      _taskId,
      const AsyncError(
        OperationalFailure(OperationalFailureCode.permissionDenied),
        StackTrace.empty,
      ),
    );
    await tester.pumpWidget(_app(_taskId, failure));
    await tester.pump();
    expect(find.text('Bạn không có quyền truy cập.'), findsOneWidget);
    expect(find.text('Nguyễn Văn A'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('task-detail-retry')));
    await tester.pump();
    expect(failure.refreshes, 1);
  });

  testWidgets('map action uses only the task route and no PII query', (
    tester,
  ) async {
    const mapTaskId = 'ABCDEF12-3456-7ABC-8DEF-0123456789AB';
    final vm = _FixtureDetailViewModel(
      mapTaskId,
      AsyncData(_outboundDetails(mapTaskId)),
    );
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              Scaffold(body: DeliveryTaskDetailPage(taskId: mapTaskId)),
        ),
        GoRoute(
          path: '/shipper/tasks/:taskId/map',
          builder: (context, state) =>
              Text('map:${state.pathParameters['taskId']}'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deliveryTaskDetailViewModelProvider(mapTaskId).overrideWith(() => vm),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-detail-map')));
    await tester.pumpAndSettle();
    expect(find.text('map:$mapTaskId'), findsOneWidget);
    expect(router.state.uri.queryParameters, isEmpty);
    router.pop();
    await tester.pumpAndSettle();
    expect(vm.refreshes, 1);
  });

  testWidgets('read-only detail stays usable at 320px and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final vm = _FixtureDetailViewModel(_taskId, AsyncData(_outboundDetails()));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: _app(_taskId, vm),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _app(String taskId, _FixtureDetailViewModel vm) {
  return ProviderScope(
    key: ValueKey(vm),
    overrides: [
      deliveryTaskDetailViewModelProvider(taskId).overrideWith(() => vm),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: DeliveryTaskDetailPage(taskId: taskId)),
    ),
  );
}

DeliveryTaskDetails _inTransitDetails(DeliveryTaskKind kind) {
  final base = kind == DeliveryTaskKind.outbound
      ? _outboundDetails()
      : _redeliveryDetails();
  final task = base.task;
  return DeliveryTaskDetails(
    task: DeliveryTaskSnapshot(
      taskId: task.taskId,
      kind: kind,
      status: DeliveryTaskStatus.inTransit,
      attemptNumber: task.attemptNumber,
      scope: DeliverySnapshotScope.current,
      orderId: task.orderId,
      returnRequestId: task.returnRequestId,
      amountToCollectVnd: task.amountToCollectVnd,
      destination: task.destination,
      assignedAt: DateTime.utc(2026, 10, 24, 1),
      acceptedAt: DateTime.utc(2026, 10, 24, 2),
      startedAt: DateTime.utc(2026, 10, 24, 3),
      itemSource: task.itemSource,
    ),
    items: base.items,
  );
}

DeliveryTaskDetails _outboundDetails([String taskId = _taskId]) {
  return DeliveryTaskDetails(
    task: DeliveryTaskSnapshot(
      taskId: taskId,
      kind: DeliveryTaskKind.outbound,
      status: DeliveryTaskStatus.assigned,
      attemptNumber: 1,
      scope: DeliverySnapshotScope.current,
      orderId: '22222222-2222-4222-8222-222222222222',
      amountToCollectVnd: 550000,
      destination: _destination,
      itemSource: DeliveryItemSource.orderSnapshot,
    ),
    notes: 'Ghi chú riêng tư không được phép',
    items: [
      DeliveryTaskItem(
        itemId: '44444444-4444-4444-8444-444444444444',
        itemSource: DeliveryItemSource.orderSnapshot,
        productName: 'Bóng đá',
        variantLabel: 'Size 5',
        attributes: const {'color': 'white'},
        quantity: 2,
      ),
    ],
  );
}

DeliveryTaskDetails _returnPickupDetails() {
  return DeliveryTaskDetails(
    task: const DeliveryTaskSnapshot(
      taskId: _returnTaskId,
      kind: DeliveryTaskKind.returnPickup,
      status: DeliveryTaskStatus.assigned,
      attemptNumber: 1,
      scope: DeliverySnapshotScope.current,
      returnRequestId: '33333333-3333-4333-8333-333333333333',
      amountToCollectVnd: 0,
      destination: _destination,
      itemSource: DeliveryItemSource.returnPlan,
    ),
    items: [
      DeliveryTaskItem(
        itemId: '44444444-4444-4444-8444-444444444444',
        itemSource: DeliveryItemSource.returnPlan,
        productName: 'Bóng đá bị lỗi',
        quantity: 2,
        quantityCollected: 1,
      ),
    ],
  );
}

DeliveryTaskDetails _redeliveryDetails() {
  return DeliveryTaskDetails(
    task: const DeliveryTaskSnapshot(
      taskId: _redeliveryTaskId,
      kind: DeliveryTaskKind.redelivery,
      status: DeliveryTaskStatus.accepted,
      attemptNumber: 1,
      scope: DeliverySnapshotScope.current,
      returnRequestId: '33333333-3333-4333-8333-333333333333',
      amountToCollectVnd: 0,
      destination: _destination,
      itemSource: DeliveryItemSource.unavailableRedeliveryPlan,
    ),
    items: const [],
  );
}

DeliveryTaskDetails _historyDetails() {
  return DeliveryTaskDetails(
    task: const DeliveryTaskSnapshot(
      taskId: _taskId,
      kind: DeliveryTaskKind.outbound,
      status: DeliveryTaskStatus.delivered,
      attemptNumber: 1,
      scope: DeliverySnapshotScope.history,
      amountToCollectVnd: 550000,
      destination: _destination,
      itemSource: DeliveryItemSource.unavailable,
    ),
    items: [
      DeliveryTaskItem(
        itemId: '44444444-4444-4444-8444-444444444444',
        itemSource: DeliveryItemSource.orderSnapshot,
        productName: 'Dữ liệu riêng tư bị lộ',
        quantity: 1,
      ),
    ],
    notes: 'Dữ liệu riêng tư bị lộ',
  );
}

const _destination = DeliveryDestination(
  name: 'Nguyễn Văn A',
  phone: '0900000000',
  address: 'Hà Nội',
  latitude: 21.028511,
  longitude: 105.804817,
);
