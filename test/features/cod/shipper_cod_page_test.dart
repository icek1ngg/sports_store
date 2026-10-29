import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/features/cod/domain/models/cod_collection.dart';
import 'package:sports_store/features/cod/domain/models/cod_collection_page.dart';
import 'package:sports_store/features/cod/domain/models/cod_collection_query.dart';
import 'package:sports_store/features/cod/domain/repositories/cod_repository.dart';
import 'package:sports_store/features/cod/presentation/pages/cod_route_page.dart';
import 'package:sports_store/features/cod/presentation/pages/shipper_cod_page.dart';
import 'package:sports_store/features/cod/presentation/view_models/cod_providers.dart';
import 'package:sports_store/features/cod/presentation/view_models/manager_cod_view_model.dart';
import 'package:sports_store/features/cod/presentation/view_models/shipper_cod_view_model.dart';
import 'package:sports_store/features/cod/presentation/widgets/manager_cod_panel.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';

const _shipperId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _orderCollected = '11111111-1111-4111-8111-111111111111';
const _orderReceived = '22222222-2222-4222-8222-222222222222';

class _RepositoryFixture implements CodRepository {
  final queries = <CodCollectionQuery>[];

  @override
  Future<CodCollectionPage> queryCollections(CodCollectionQuery query) async {
    queries.add(query);
    final item = query.statuses.single == CodStatus.received
        ? _received
        : _collected;
    return CodCollectionPage(
      items: [item],
      nextCursor: null,
      filteredTotal: 1,
      counts: const CodCollectionCounts(
        all: 3,
        uncollected: 1,
        collected: 1,
        received: 1,
      ),
      outstandingVnd: 550000,
      asOf: DateTime.utc(2026, 10, 25),
    );
  }

  @override
  Future<List<CodCollection>> listCollections({
    String? shipperId,
    String? orderId,
  }) async => const [];
}

class _FixtureShipperCodViewModel extends ShipperCodViewModel {
  _FixtureShipperCodViewModel(this.initial) : super(null);

  final ShipperCodState initial;
  final groups = <ShipperCodGroup>[];
  var refreshes = 0;
  var loadMores = 0;

  @override
  ShipperCodState build() => initial;

  @override
  Future<void> setGroup(ShipperCodGroup group) async {
    groups.add(group);
    state = state.copyWith(
      group: group,
      items: group == ShipperCodGroup.reconciled ? [_received] : [_collected],
      filteredTotal: 1,
      isLoading: false,
      error: null,
    );
  }

  @override
  Future<void> refresh() async {
    refreshes++;
    state = state.copyWith(isLoading: false, error: null);
  }

  @override
  Future<void> loadMore() async {
    loadMores++;
    state = state.copyWith(isLoadingMore: false, nextCursor: null);
  }
}

/// Keeps this route test isolated from Supabase while asserting the real
/// manager branch is selected.  Manager API behavior is covered by the
/// dedicated manager-panel fixture tests.
class _FixtureManagerCodViewModel extends ManagerCodViewModel {
  _FixtureManagerCodViewModel() : super(null);

  @override
  ManagerCodState build() => ManagerCodState.initial(isLoading: false);
}

void main() {
  testWidgets('renders own COD, held total and no receipt action', (
    tester,
  ) async {
    final vm = _FixtureShipperCodViewModel(_state());
    await tester.pumpWidget(_app(vm));

    expect(find.byKey(const ValueKey('cod-held-total')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('cod-held-total'))).data,
      '550.000 đ',
    );
    expect(find.text('120.000 đ'), findsNothing);
    expect(find.textContaining(_orderCollected), findsOneWidget);
    expect(find.textContaining('23/10/2026'), findsOneWidget);
    expect(find.text('Xác nhận đã nhận tiền'), findsNothing);
    expect(find.text('Đã nhận đủ'), findsNothing);
    expect(find.byKey(const ValueKey('cod-confirm-receipt')), findsNothing);
    expect(find.textContaining(_orderReceived), findsNothing);
  });

  testWidgets('tabs request explicit collected and received groups', (
    tester,
  ) async {
    final vm = _FixtureShipperCodViewModel(_state());
    await tester.pumpWidget(_app(vm));

    await tester.tap(find.byKey(const ValueKey('cod-reconciled')));
    await tester.pumpAndSettle();
    expect(vm.groups, [ShipperCodGroup.reconciled]);
    expect(find.textContaining(_orderCollected), findsNothing);
    expect(find.textContaining(_orderReceived), findsOneWidget);
    expect(find.textContaining('24/10/2026'), findsOneWidget);
    expect(find.text('Đã đối soát'), findsWidgets);
    expect(find.text('Đã nhận đủ'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('cod-unreconciled')));
    await tester.pumpAndSettle();
    expect(vm.groups, [
      ShipperCodGroup.reconciled,
      ShipperCodGroup.unreconciled,
    ]);
    expect(find.textContaining(_orderCollected), findsOneWidget);
  });

  testWidgets('manager role uses the shared MH12 manager panel', (
    tester,
  ) async {
    final managerVm = _FixtureManagerCodViewModel();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          codScreenRoleProvider.overrideWithValue(const AsyncData('manager')),
          managerCodViewModelProvider(null).overrideWith(() => managerVm),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: CodRoutePage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ShipperCodPage), findsNothing);
    expect(find.byType(ManagerCodPanel), findsOneWidget);
    expect(find.byKey(const ValueKey('manager-cod-confirm')), findsNothing);
    expect(find.byKey(const ValueKey('cod-confirm-receipt')), findsNothing);
  });

  testWidgets('real ViewModel binds auth shipper and server status filters', (
    tester,
  ) async {
    final repository = _RepositoryFixture();
    const session = OperationalSession(userId: _shipperId, generation: 1);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          codRepositoryProvider.overrideWithValue(repository),
          operationalSessionProvider.overrideWithValue(
            const AsyncData(session),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: ShipperCodPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.queries, hasLength(1));
    expect(repository.queries.single.shipperId, _shipperId);
    expect(repository.queries.single.statuses, [CodStatus.collected]);
    expect(find.textContaining(_orderCollected), findsOneWidget);
    expect(find.textContaining(_orderReceived), findsNothing);

    await tester.tap(find.byKey(const ValueKey('cod-reconciled')));
    await tester.pumpAndSettle();
    expect(repository.queries.last.shipperId, _shipperId);
    expect(repository.queries.last.statuses, [CodStatus.received]);
    expect(find.textContaining(_orderCollected), findsNothing);
    expect(find.textContaining(_orderReceived), findsOneWidget);
  });

  testWidgets('polling pauses with app lifecycle and refreshes on resume', (
    tester,
  ) async {
    final repository = _RepositoryFixture();
    const session = OperationalSession(userId: _shipperId, generation: 1);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          codRepositoryProvider.overrideWithValue(repository),
          operationalSessionProvider.overrideWithValue(
            const AsyncData(session),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: ShipperCodPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.queries, hasLength(1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 31));
    expect(repository.queries, hasLength(1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(repository.queries, hasLength(2));
  });

  testWidgets('loading, empty and error states expose safe controls', (
    tester,
  ) async {
    final loading = _FixtureShipperCodViewModel(_state(isLoading: true));
    await tester.pumpWidget(_app(loading));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const ValueKey('cod-held-total')), findsNothing);

    final empty = _FixtureShipperCodViewModel(
      _state(items: const [], filteredTotal: 0),
    );
    await tester.pumpWidget(_app(empty));
    expect(find.byKey(const ValueKey('cod-empty')), findsOneWidget);
    expect(find.textContaining('chưa có khoản COD'), findsOneWidget);

    final error = _FixtureShipperCodViewModel(
      _state(error: const OperationalFailure(OperationalFailureCode.network)),
    );
    await tester.pumpWidget(_app(error));
    expect(find.byKey(const ValueKey('cod-error')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cod-retry')));
    await tester.pumpAndSettle();
    expect(error.refreshes, 1);
  });

  testWidgets(
    'refresh and load more are manual and no manager controls appear',
    (tester) async {
      final vm = _FixtureShipperCodViewModel(_state(nextCursor: 'opaque-next'));
      await tester.pumpWidget(_app(vm));
      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cod-load-more')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cod-load-more')));
      await tester.pumpAndSettle();
      expect(vm.loadMores, 1);
      await tester.tap(find.byKey(const ValueKey('cod-refresh')));
      await tester.pumpAndSettle();
      expect(vm.refreshes, 1);
      expect(find.byKey(const ValueKey('cod-confirm-receipt')), findsNothing);
    },
  );

  testWidgets('narrow viewport remains usable with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(_FixtureShipperCodViewModel(_state()), textScale: 1.8),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('cod-held-total')), findsOneWidget);
  });
}

Widget _app(_FixtureShipperCodViewModel vm, {double textScale = 1}) =>
    ProviderScope(
      key: ObjectKey(vm),
      overrides: [shipperCodViewModelProvider(null).overrideWith(() => vm)],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const Scaffold(body: ShipperCodPage()),
      ),
    );

ShipperCodState _state({
  List<CodCollection>? items,
  int? filteredTotal,
  String? nextCursor,
  bool isLoading = false,
  OperationalFailure? error,
}) => ShipperCodState(
  group: ShipperCodGroup.unreconciled,
  items: items ?? [_collected],
  counts: const CodCollectionCounts(
    all: 3,
    uncollected: 1,
    collected: 1,
    received: 1,
  ),
  heldTotalVnd: 550000,
  filteredTotal: filteredTotal ?? 1,
  nextCursor: nextCursor,
  asOf: DateTime.utc(2026, 10, 25),
  isLoading: isLoading,
  isLoadingMore: false,
  error: error,
  loadMoreError: null,
);

final _collected = _collection(
  orderId: _orderCollected,
  status: CodStatus.collected,
  collectedAt: '2026-10-23T10:00:00Z',
);

final _received = _collection(
  orderId: _orderReceived,
  status: CodStatus.received,
  collectedAt: '2026-10-22T10:00:00Z',
  receivedAt: '2026-10-24T10:00:00Z',
);

CodCollection _collection({
  required String orderId,
  required CodStatus status,
  required String collectedAt,
  String? receivedAt,
}) => CodCollection(
  orderId: orderId,
  orderCode: orderId,
  orderCodeSource: 'order_uuid',
  shipperId: _shipperId,
  status: status,
  expectedAmountVnd: 550000,
  collectedAmountVnd: 550000,
  receivedAmountVnd: status == CodStatus.received ? 550000 : 0,
  collectedBy: _shipperId,
  receivedBy: status == CodStatus.received ? 'manager-id' : null,
  collectedAt: DateTime.parse(collectedAt),
  handedOverAt: status == CodStatus.received
      ? DateTime.parse(receivedAt!)
      : null,
  receivedAt: receivedAt == null ? null : DateTime.parse(receivedAt),
  createdAt: DateTime.utc(2026, 10, 23),
  updatedAt: DateTime.utc(2026, 10, 25),
);
