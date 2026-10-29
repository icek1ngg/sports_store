import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_query.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';
import 'package:sports_store/features/deliveries/presentation/pages/delivery_task_list_page.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_task_list_view_model.dart';

class _FixtureTaskListViewModel extends DeliveryTaskListViewModel {
  _FixtureTaskListViewModel(this.initial);

  final DeliveryTaskListState initial;
  final searches = <String>[];
  final kinds = <DeliveryTaskKind?>[];
  final groups = <DeliveryTaskStateGroup?>[];
  var refreshes = 0;
  var loadMores = 0;
  var resetFiltersCalls = 0;

  void emit(DeliveryTaskListState next) => state = next;

  @override
  DeliveryTaskListState build() => initial;

  @override
  Future<void> setSearch(String value) async {
    searches.add(value);
    state = state.copyWith(
      query: DeliveryTaskQuery(
        query: value,
        kind: state.query.kind,
        stateGroup: state.query.stateGroup,
        limit: state.query.limit,
      ),
    );
  }

  @override
  Future<void> setKind(DeliveryTaskKind? kind) async {
    kinds.add(kind);
    state = state.copyWith(
      query: DeliveryTaskQuery(
        query: state.query.query,
        kind: kind,
        stateGroup: state.query.stateGroup,
        limit: state.query.limit,
      ),
    );
  }

  @override
  Future<void> setStateGroup(DeliveryTaskStateGroup? group) async {
    groups.add(group);
    state = state.copyWith(
      query: DeliveryTaskQuery(
        query: state.query.query,
        kind: state.query.kind,
        stateGroup: group,
        limit: state.query.limit,
      ),
    );
  }

  @override
  Future<void> refresh() async {
    refreshes++;
  }

  @override
  Future<void> loadMore() async {
    loadMores++;
    state = state.copyWith(nextCursor: null, isLoadingMore: false);
  }

  @override
  Future<void> resetFilters() async {
    resetFiltersCalls++;
    state = state.copyWith(
      query: DeliveryTaskQuery(),
      items: const <DeliveryTaskSnapshot>[],
      counts: const DeliveryTaskCounts(
        waiting: 0,
        inTransit: 0,
        completed: 0,
        ungrouped: 0,
      ),
      filteredTotal: 0,
      nextCursor: null,
      asOf: DateTime.utc(2026, 10, 23),
      isLoading: false,
      isLoadingMore: false,
      error: null,
      loadMoreError: null,
    );
  }
}

void main() {
  final session = const OperationalSession(userId: 'shipper-a', generation: 1);

  testWidgets('shows initial loading without stale cards or counts', (
    tester,
  ) async {
    final viewModel = _FixtureTaskListViewModel(
      DeliveryTaskListState.initial(isLoading: true),
    );
    await tester.pumpWidget(_app(viewModel, session));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('delivery-task-11111111-1111-4111-8111-111111111111'),
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('mh10-empty')), findsNothing);
    expect(find.textContaining('nhiệm vụ theo bộ lọc hiện tại'), findsNothing);
    expect(find.byKey(const ValueKey('mh10-count-Tất cả')), findsNothing);
  });

  testWidgets('renders an empty state and resets server filters', (
    tester,
  ) async {
    final viewModel = _FixtureTaskListViewModel(
      _state(items: const []).copyWith(
        query: DeliveryTaskQuery(query: 'missing-recipient'),
        counts: const DeliveryTaskCounts(
          waiting: 0,
          inTransit: 0,
          completed: 0,
          ungrouped: 0,
        ),
        filteredTotal: 0,
      ),
    );
    await tester.pumpWidget(_app(viewModel, session));

    expect(find.byKey(const ValueKey('mh10-empty')), findsOneWidget);
    expect(find.text('Không tìm thấy nhiệm vụ'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('delivery-task-11111111-1111-4111-8111-111111111111'),
      ),
      findsNothing,
    );
    expect(find.text('0 nhiệm vụ theo bộ lọc hiện tại'), findsOneWidget);

    await tester.tap(find.text('Đặt lại bộ lọc'));
    await tester.pump();
    expect(viewModel.resetFiltersCalls, 1);
    expect(viewModel.state.query.query, isNull);
  });

  testWidgets('permission denial is bounded and offers retry', (tester) async {
    final viewModel = _FixtureTaskListViewModel(
      DeliveryTaskListState.initial(
        isLoading: false,
        error: const OperationalFailure(
          OperationalFailureCode.permissionDenied,
        ),
      ),
    );
    await tester.pumpWidget(_app(viewModel, session));

    expect(find.byKey(const ValueKey('mh10-error')), findsOneWidget);
    expect(find.text('Bạn không có quyền truy cập.'), findsOneWidget);
    expect(find.byKey(const ValueKey('mh10-count-Tất cả')), findsNothing);
    expect(
      find.byKey(
        const ValueKey('delivery-task-11111111-1111-4111-8111-111111111111'),
      ),
      findsNothing,
    );

    final beforeRetry = viewModel.refreshes;
    await tester.tap(find.text('Thử lại'));
    await tester.pump();
    expect(viewModel.refreshes, beforeRetry + 1);
  });

  testWidgets('network failure exposes an explicit retry action', (
    tester,
  ) async {
    final viewModel = _FixtureTaskListViewModel(
      DeliveryTaskListState.initial(
        isLoading: false,
        error: const OperationalFailure(OperationalFailureCode.network),
      ),
    );
    await tester.pumpWidget(_app(viewModel, session));

    expect(find.byKey(const ValueKey('mh10-error')), findsOneWidget);
    expect(find.text('Không thể kết nối. Vui lòng thử lại.'), findsOneWidget);
    final beforeRetry = viewModel.refreshes;
    await tester.tap(find.text('Thử lại'));
    await tester.pump();
    expect(viewModel.refreshes, beforeRetry + 1);
  });

  testWidgets('renders counts, server filter controls and masked history', (
    tester,
  ) async {
    final viewModel = _FixtureTaskListViewModel(_state());
    await tester.pumpWidget(_app(viewModel, session));

    expect(find.text('Nhiệm vụ giao nhận'), findsOneWidget);
    expect(find.byKey(const ValueKey('task-search-input')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-group-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-group-waiting')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-kind-outbound')), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('delivery-task-11111111-1111-4111-8111-111111111111'),
      ),
      findsOneWidget,
    );
    expect(
      find.text('Thông tin đã được giới hạn cho nhiệm vụ này.'),
      findsOneWidget,
    );
    expect(find.text('Thông tin COD được giới hạn'), findsOneWidget);
    expect(find.text('Giao thất bại'), findsOneWidget);
    expect(find.text('0 đ'), findsNothing);
  });

  testWidgets('renders all task kinds, status labels and server counts', (
    tester,
  ) async {
    const destination = DeliveryDestination(
      name: 'Nguyễn Văn A',
      phone: '0900000000',
      address: 'Hà Nội',
      latitude: 21.028511,
      longitude: 105.804817,
    );
    final tasks = <DeliveryTaskSnapshot>[
      const DeliveryTaskSnapshot(
        taskId: '44444444-4444-4444-8444-444444444444',
        kind: DeliveryTaskKind.outbound,
        status: DeliveryTaskStatus.assigned,
        attemptNumber: 1,
        scope: DeliverySnapshotScope.current,
        orderId: '55555555-5555-4555-8555-555555555555',
        amountToCollectVnd: 550000,
        destination: destination,
        itemSource: DeliveryItemSource.orderSnapshot,
      ),
      const DeliveryTaskSnapshot(
        taskId: '66666666-6666-4666-8666-666666666666',
        kind: DeliveryTaskKind.returnPickup,
        status: DeliveryTaskStatus.accepted,
        attemptNumber: 1,
        scope: DeliverySnapshotScope.current,
        returnRequestId: '77777777-7777-4777-8777-777777777777',
        destination: destination,
        itemSource: DeliveryItemSource.returnPlan,
      ),
      const DeliveryTaskSnapshot(
        taskId: '88888888-8888-4888-8888-888888888888',
        kind: DeliveryTaskKind.redelivery,
        status: DeliveryTaskStatus.inTransit,
        attemptNumber: 1,
        scope: DeliverySnapshotScope.current,
        returnRequestId: '99999999-9999-4999-8999-999999999999',
        destination: destination,
        itemSource: DeliveryItemSource.returnPlan,
      ),
    ];
    final viewModel = _FixtureTaskListViewModel(
      _state(items: tasks).copyWith(
        counts: const DeliveryTaskCounts(
          waiting: 7,
          inTransit: 4,
          completed: 9,
          ungrouped: 22,
        ),
        filteredTotal: 42,
      ),
    );
    await tester.pumpWidget(_app(viewModel, session));

    expect(find.text('GIAO HÀNG'), findsOneWidget);
    expect(find.text('THU HỒI HÀNG'), findsOneWidget);
    expect(find.text('GIAO LẠI MIỄN PHÍ'), findsWidgets);
    expect(find.text('Đã phân công'), findsOneWidget);
    expect(find.text('Đã nhận hàng'), findsOneWidget);
    expect(find.text('Đang vận chuyển'), findsOneWidget);
    expect(find.text('550.000 đ'), findsOneWidget);
    expect(find.text('Không thu COD'), findsOneWidget);
    expect(find.text('Không thu tiền'), findsOneWidget);
    expect(find.text('42 nhiệm vụ theo bộ lọc hiện tại'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mh10-count-Tất cả')),
        matching: find.text('42'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mh10-count-Chờ')),
        matching: find.text('7'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mh10-count-Đang giao')),
        matching: find.text('4'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mh10-count-Hoàn tất')),
        matching: find.text('9'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('submits combined search and filters to the ViewModel', (
    tester,
  ) async {
    final viewModel = _FixtureTaskListViewModel(_state(items: const []));
    await tester.pumpWidget(_app(viewModel, session));

    await tester.enterText(
      find.byKey(const ValueKey('task-search-input')),
      'Nguyễn',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.tap(find.byKey(const ValueKey('task-kind-return_pickup')));
    await tester.tap(find.byKey(const ValueKey('task-group-in_transit')));
    await tester.pump();

    expect(viewModel.searches, ['Nguyễn']);
    expect(viewModel.kinds, [DeliveryTaskKind.returnPickup]);
    expect(viewModel.groups, [DeliveryTaskStateGroup.inTransit]);
    expect(viewModel.state.query.query, 'Nguyễn');
  });

  testWidgets('refresh, load more and load-more retry stay explicit', (
    tester,
  ) async {
    final viewModel = _FixtureTaskListViewModel(_state(nextCursor: 'cursor'));
    await tester.pumpWidget(_app(viewModel, session));

    final beforeRefresh = viewModel.refreshes;
    await tester.tap(find.byKey(const ValueKey('task-refresh')));
    final loadMore = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('task-load-more')),
    );
    loadMore.onPressed!.call();
    await tester.pump();

    expect(viewModel.refreshes, beforeRefresh + 1);
    expect(viewModel.loadMores, 1);
  });

  testWidgets('pull refresh works for empty and error results', (tester) async {
    final viewModel = _FixtureTaskListViewModel(_state(items: const []));
    await tester.pumpWidget(_app(viewModel, session));
    final before = viewModel.refreshes;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(viewModel.refreshes, before + 1);
    viewModel.emit(
      DeliveryTaskListState.initial(
        isLoading: false,
        error: const OperationalFailure(OperationalFailureCode.network),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('mh10-error')), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(viewModel.refreshes, before + 2);
  });

  testWidgets('backend session expiry clears search without an auth event', (
    tester,
  ) async {
    final viewModel = _FixtureTaskListViewModel(_state(items: const []));
    await tester.pumpWidget(_app(viewModel, session));
    final search = find.byKey(const ValueKey('task-search-input'));
    await tester.enterText(search, 'người nhận riêng');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    viewModel.emit(
      DeliveryTaskListState.initial(
        isLoading: false,
        error: const OperationalFailure(OperationalFailureCode.sessionExpired),
      ),
    );
    await tester.pump();
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(find.byKey(const ValueKey('mh10-error')), findsOneWidget);
  });

  testWidgets('clears an unsubmitted draft across account and auth errors', (
    tester,
  ) async {
    final sessions = StreamController<OperationalSession>();
    addTearDown(sessions.close);
    final viewModel = _FixtureTaskListViewModel(_state(items: const []));
    await tester.pumpWidget(
      _app(viewModel, session, sessionStream: sessions.stream),
    );
    sessions.add(session);
    await tester.pump();

    final search = find.byKey(const ValueKey('task-search-input'));
    await tester.enterText(search, 'bản nháp riêng');
    sessions.add(const OperationalSession(userId: 'shipper-b', generation: 2));
    await tester.pump();
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);

    await tester.enterText(search, 'bản nháp khác');
    sessions.addError(StateError('auth stream ended'));
    await tester.pump();
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
  });

  testWidgets('stays readable at a narrow viewport and large text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final viewModel = _FixtureTaskListViewModel(_state());
    await tester.pumpWidget(_app(viewModel, session, textScale: 2));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

Widget _app(
  _FixtureTaskListViewModel viewModel,
  OperationalSession session, {
  Stream<OperationalSession>? sessionStream,
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: [
      deliveryTaskListViewModelProvider.overrideWith(() => viewModel),
      if (sessionStream == null)
        operationalSessionProvider.overrideWithValue(AsyncData(session))
      else
        operationalSessionProvider.overrideWith((ref) => sessionStream),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: const Scaffold(body: DeliveryTaskListPage()),
      ),
    ),
  );
}

DeliveryTaskListState _state({
  List<DeliveryTaskSnapshot>? items,
  String? nextCursor,
}) {
  final outbound = DeliveryTaskSnapshot(
    taskId: '11111111-1111-4111-8111-111111111111',
    kind: DeliveryTaskKind.outbound,
    status: DeliveryTaskStatus.assigned,
    attemptNumber: 1,
    scope: DeliverySnapshotScope.current,
    orderId: '22222222-2222-4222-8222-222222222222',
    amountToCollectVnd: 550000,
    destination: const DeliveryDestination(
      name: 'Nguyễn Văn A',
      phone: '0900000000',
      address: 'Hà Nội',
      latitude: 21.028511,
      longitude: 105.804817,
    ),
    itemSource: DeliveryItemSource.orderSnapshot,
  );
  final masked = DeliveryTaskSnapshot(
    taskId: '33333333-3333-4333-8333-333333333333',
    kind: DeliveryTaskKind.outbound,
    status: DeliveryTaskStatus.failed,
    attemptNumber: 1,
    scope: DeliverySnapshotScope.restricted,
    completedAt: DateTime.utc(2026, 10, 23),
    itemSource: DeliveryItemSource.unavailable,
  );
  final values = items ?? [outbound, masked];
  return DeliveryTaskListState(
    query: DeliveryTaskQuery(),
    items: values,
    counts: const DeliveryTaskCounts(
      waiting: 1,
      inTransit: 0,
      completed: 0,
      ungrouped: 1,
    ),
    filteredTotal: values.length,
    nextCursor: nextCursor,
    asOf: DateTime.utc(2026, 10, 23),
    isLoading: false,
    isLoadingMore: false,
    error: null,
    loadMoreError: null,
  );
}
