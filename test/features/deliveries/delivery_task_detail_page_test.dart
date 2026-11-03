import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';
import 'package:sports_store/features/deliveries/presentation/pages/delivery_task_detail_page.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_task_detail_view_model.dart';

const _taskId = '11111111-1111-4111-8111-111111111111';
const _returnTaskId = '66666666-6666-4666-8666-666666666666';
const _redeliveryTaskId = '88888888-8888-4888-8888-888888888888';

const _expiredOperationalSession = OperationalSession(
  userId: null,
  generation: 0,
  failure: OperationalFailure(OperationalFailureCode.sessionExpired),
);

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
  testWidgets('renders product URL and handles network image failure', (
    tester,
  ) async {
    const url = 'https://example.com/ball.webp';
    final vm = _FixtureDetailViewModel(
      _taskId,
      AsyncData(_outboundDetails(_taskId, url)),
    );
    await tester.pumpWidget(_app(_taskId, vm));
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as NetworkImage).url, url);
    expect(image.semanticLabel, 'Bóng đá');
    expect(image.loadingBuilder, isNotNull);
    expect(image.errorBuilder, isNotNull);
    await tester.pumpAndSettle();
    expect(find.text('Bóng đá'), findsOneWidget);
    expect(find.text('Ảnh chưa được cung cấp'), findsNothing);
    expect(tester.takeException(), isNull);
  });
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
          ? <String>[]
          : ['Giao lại thành công', 'Báo giao lại thất bại'];
      for (final label in actions) {
        final action = label == 'Giao lại thành công'
            ? find.widgetWithText(FilledButton, label)
            : find.widgetWithText(OutlinedButton, label);
        expect(action, findsOneWidget);
        expect(tester.widget<ButtonStyleButton>(action).onPressed, isNull);
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
    expect(find.text('Báo cáo bàn giao / sự cố'), findsNothing);
    expect(find.text('Đã phân công'), findsOneWidget);
    expect(find.text(_taskId), findsOneWidget);
    expect(find.text('Nguyễn Văn A'), findsOneWidget);
    expect(find.text('0900000000'), findsOneWidget);
    expect(find.text('550.000 đ'), findsOneWidget);
    expect(find.text('Lần dự kiến: 1 / 2'), findsOneWidget);
    expect(find.text('Ảnh chưa được cung cấp'), findsNothing);
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
        'Gọi điện chỉ mở trình quay số; bạn quyết định thực hiện cuộc gọi.',
      ),
      findsOneWidget,
    );
    expect(find.text('Dự kiến: 550.000 đ'), findsOneWidget);
    expect(find.text('Đã thu: 0 đ'), findsOneWidget);
    expect(find.text('Cửa hàng đã nhận: 0 đ'), findsOneWidget);
    expect(find.text('Nhiệm vụ chưa có ghi chú.'), findsOneWidget);
    expect(find.text('Ghi chú riêng tư không được phép'), findsNothing);
    expect(find.text('Chưa thu COD'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('task-detail-call')),
          )
          .onPressed,
      isNotNull,
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
    expect(find.text('Không thu tiền'), findsOneWidget);
    expect(find.text('Lần dự kiến: 1 / 2'), findsNothing);
    expect(find.text('Không áp dụng hạn mức 2 lần giao đi'), findsNothing);
    expect(find.text('Xác nhận lấy hàng'), findsNothing);
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

    expect(find.text('Giao lại miễn phí'), findsWidgets);
    expect(find.text('Danh sách hàng giao lại chưa khả dụng.'), findsOneWidget);
    expect(find.text('Không thu COD'), findsOneWidget);
    expect(find.text('Không áp dụng hạn mức 2 lần giao đi'), findsOneWidget);
    expect(find.textContaining('/ 2'), findsNothing);
    expect(find.text('Bắt đầu giao lại'), findsOneWidget);
  });

  testWidgets('history projection renders owned detail fields read-only', (
    tester,
  ) async {
    final vm = _FixtureDetailViewModel(_taskId, AsyncData(_historyDetails()));
    await tester.pumpWidget(_app(_taskId, vm));

    expect(find.text('Lịch sử'), findsOneWidget);
    expect(find.text('Nguyễn Văn A'), findsOneWidget);
    expect(find.text('0900000000'), findsOneWidget);
    expect(find.text('550.000 đ'), findsOneWidget);
    expect(find.text('Bóng đá'), findsOneWidget);
    expect(find.text('Nhiệm vụ chưa có ghi chú.'), findsOneWidget);
    expect(find.text('Cửa hàng đã nhận COD'), findsOneWidget);
    expect(find.text('Cửa hàng đã nhận: 550.000 đ'), findsOneWidget);
    expect(
      find.text(
        'Thông tin lần giao này được lưu để xem lại. Nếu đủ điều kiện, bạn có thể tạo lần giao tiếp theo ở mục Giao lại đơn hàng.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('task-detail-map')), findsNothing);
  });

  testWidgets('history COD uses ledger status instead of task status', (
    tester,
  ) async {
    final vm = _FixtureDetailViewModel(
      _taskId,
      AsyncData(
        _historyDetails(
          status: DeliveryCodStatus.collected,
          receivedAmountVnd: 0,
        ),
      ),
    );
    await tester.pumpWidget(_app(_taskId, vm));

    expect(find.text('Shipper đã thu COD'), findsOneWidget);
    expect(find.text('Đã thu: 550.000 đ'), findsOneWidget);
    expect(find.text('Cửa hàng đã nhận: 0 đ'), findsOneWidget);
    expect(find.text('Giao lại lần 2'), findsNothing);
  });

  testWidgets('failed history without server retry capability is read-only', (
    tester,
  ) async {
    final vm = _FixtureDetailViewModel(
      _taskId,
      AsyncData(_failedHistoryDetails(canRetry: false)),
    );
    await tester.pumpWidget(_app(_taskId, vm));

    expect(find.text('Lần 1 chưa giao được'), findsOneWidget);
    expect(find.text('Chưa thu COD'), findsOneWidget);
    expect(find.text('Giao lại lần 2'), findsNothing);
    expect(
      find.text(
        'Thông tin lần giao này được lưu để xem lại. Nếu đủ điều kiện, bạn có thể tạo lần giao tiếp theo ở mục Giao lại đơn hàng.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('failed history exposes retry only when server grants it', (
    tester,
  ) async {
    final vm = _FixtureDetailViewModel(
      _taskId,
      AsyncData(_failedHistoryDetails(canRetry: true)),
    );
    await tester.pumpWidget(_app(_taskId, vm));

    expect(find.byKey(const ValueKey('outbound-retry-open')), findsOneWidget);
    expect(find.text('Giao lại lần 2'), findsOneWidget);
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
          operationalSessionProvider.overrideWithValue(
            const AsyncData(_expiredOperationalSession),
          ),
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
      // The legacy page tests intentionally inject only the read-only detail
      // VM. Keep the newly lazy action VM from constructing Supabase when an
      // outbound projection is rendered by these read-only fixtures.
      operationalSessionProvider.overrideWithValue(
        const AsyncData(_expiredOperationalSession),
      ),
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
    cod: base.cod,
  );
}

DeliveryTaskDetails _outboundDetails([
  String taskId = _taskId,
  String? imageUrl,
]) {
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
        imageUrl: imageUrl,
        variantLabel: 'Size 5',
        attributes: const {'color': 'white'},
        quantity: 2,
      ),
    ],
    cod: const DeliveryCodSnapshot(
      status: DeliveryCodStatus.uncollected,
      expectedAmountVnd: 550000,
      collectedAmountVnd: 0,
      receivedAmountVnd: 0,
    ),
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

DeliveryTaskDetails _historyDetails({
  DeliveryCodStatus status = DeliveryCodStatus.received,
  int receivedAmountVnd = 550000,
}) {
  return DeliveryTaskDetails(
    task: const DeliveryTaskSnapshot(
      taskId: _taskId,
      kind: DeliveryTaskKind.outbound,
      status: DeliveryTaskStatus.delivered,
      attemptNumber: 1,
      scope: DeliverySnapshotScope.history,
      orderId: '22222222-2222-4222-8222-222222222222',
      amountToCollectVnd: 550000,
      destination: _destination,
      itemSource: DeliveryItemSource.orderSnapshot,
    ),
    items: [
      DeliveryTaskItem(
        itemId: '44444444-4444-4444-8444-444444444444',
        itemSource: DeliveryItemSource.orderSnapshot,
        productName: 'Bóng đá',
        quantity: 1,
      ),
    ],
    notes: 'Dữ liệu riêng tư bị lộ',
    cod: DeliveryCodSnapshot(
      status: status,
      expectedAmountVnd: 550000,
      collectedAmountVnd: 550000,
      receivedAmountVnd: receivedAmountVnd,
    ),
  );
}

DeliveryTaskDetails _failedHistoryDetails({required bool canRetry}) {
  return DeliveryTaskDetails(
    task: const DeliveryTaskSnapshot(
      taskId: _taskId,
      kind: DeliveryTaskKind.outbound,
      status: DeliveryTaskStatus.failed,
      attemptNumber: 1,
      scope: DeliverySnapshotScope.history,
      orderId: '22222222-2222-4222-8222-222222222222',
      amountToCollectVnd: 550000,
      destination: _destination,
      itemSource: DeliveryItemSource.orderSnapshot,
    ),
    items: const [],
    cod: const DeliveryCodSnapshot(
      status: DeliveryCodStatus.uncollected,
      expectedAmountVnd: 550000,
      collectedAmountVnd: 0,
      receivedAmountVnd: 0,
    ),
    canRetry: canRetry,
  );
}

const _destination = DeliveryDestination(
  name: 'Nguyễn Văn A',
  phone: '0900000000',
  address: 'Hà Nội',
  latitude: 21.028511,
  longitude: 105.804817,
);
