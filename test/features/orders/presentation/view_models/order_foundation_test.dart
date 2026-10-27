import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/core/errors/unsupported_data_exception.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/core/state/read_retry_policy.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/orders/data/models/order_dto.dart';
import 'package:sports_store/features/orders/domain/models/order_command.dart';
import 'package:sports_store/features/orders/domain/models/order_details.dart';
import 'package:sports_store/features/orders/domain/models/order_page.dart';
import 'package:sports_store/features/orders/domain/models/order_query.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/domain/repositories/order_repository.dart';
import 'package:sports_store/features/orders/presentation/view_models/order_providers.dart';

import '../../../../fixtures/order_notification_fixtures.dart';

const scopeA = SessionScope(
  userId: fixtureCustomerId,
  role: 'customer',
  generation: 1,
);
const scopeB = SessionScope(
  userId: '20000000-0000-4000-8000-000000000002',
  role: 'customer',
  generation: 2,
);
final testSessionProvider = NotifierProvider<TestSession, SessionScope>(
  TestSession.new,
);

class TestSession extends Notifier<SessionScope> {
  @override
  SessionScope build() => scopeA;
  void setScope(SessionScope value) => state = value;
}

class FakeOrders implements OrderRepository {
  final requests = <Completer<OrderDetails>>[];
  final lists = <Completer<OrderPage>>[];
  final listRoles = <String>[];
  Future<OrderPage> _list(String role) {
    listRoles.add(role);
    final result = Completer<OrderPage>();
    lists.add(result);
    return result.future;
  }

  @override
  Future<OrderPage> getCustomerOrders(OrderQuery query) => _list('customer');
  @override
  Future<OrderPage> getManagerOrders(OrderQuery query) => _list('manager');
  @override
  Future<OrderDetails> getOrderDetails(String orderId) {
    final result = Completer<OrderDetails>();
    requests.add(result);
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Test-only unsupported operation');
}

OrderDetails detail(String status, {String customerId = fixtureCustomerId}) =>
    OrderDetailsDto.fromJson({
      'order': {...fixtureOrderJson(status: status), 'customer_id': customerId},
      'items': [fixtureOrderItemJson()],
      'buyer': null,
      'delivery_summary': null,
      'cod_summary': null,
      'return_summaries': <Object?>[],
      'timeline': <Object?>[],
      'history_complete': false,
      'capabilities': fixtureCapabilitiesJson(canCancelCustomer: false),
      'as_of': '2026-10-08T03:33:00Z',
    }).domain;

Future<void> settle(ProviderContainer container) async {
  await Future<void>.delayed(Duration.zero);
  await container.pump();
  await Future<void>.delayed(Duration.zero);
}

void main() {
  late ProviderContainer container;
  late FakeOrders repository;
  final provider = orderDetailsFoundationProvider(fixtureOrderId);
  setUp(() {
    repository = FakeOrders();
    container = ProviderContainer(
      overrides: [
        featureSessionScopeProvider.overrideWith(
          (ref) => ref.watch(testSessionProvider),
        ),
        orderRepositoryProvider.overrideWithValue(repository),
        readRetryPolicyProvider.overrideWithValue(
          const ReadRetryPolicy(backoffs: []),
        ),
      ],
    );
    container.listen(provider, (_, _) {});
  });
  tearDown(() => container.dispose());

  OrderPage page() => OrderPage(
    items: [],
    nextCursor: null,
    totalCount: 0,
    statusCounts: {for (final status in OrderStatus.values) status: 0},
    asOf: DateTime.utc(2026, 10, 8),
  );

  test('accepted detail invalidates related list and retains stale list on failure', () async {
    final listProvider = orderListFoundationProvider(OrderQuery());
    container.listen(listProvider, (_, _) {});
    await settle(container);
    repository.lists.single.complete(page());
    await settle(container);
    expect(container.read(listProvider).requireValue.isFresh, isTrue);
    repository.requests.single.complete(detail('delivering'));
    await settle(container);
    expect(repository.lists.length, 2);
    expect(container.read(listProvider).requireValue.stale, isTrue);
    repository.lists.last.completeError(
      const AppFailure(code: AppFailure.network),
    );
    await settle(container);
    expect(container.read(listProvider).requireValue.data, isNotNull);
    expect(
      container.read(listProvider).requireValue.failure!.code,
      AppFailure.network,
    );
  });

  test('manager list uses the manager boundary and shipper role cannot read orders', () async {
    container
        .read(testSessionProvider.notifier)
        .setScope(
          const SessionScope(
            userId: fixtureCustomerId,
            role: 'manager',
            generation: 2,
          ),
        );
    final listProvider = orderListFoundationProvider(OrderQuery());
    container.listen(listProvider, (_, _) {});
    await settle(container);
    expect(repository.listRoles, ['manager']);
    container
        .read(testSessionProvider.notifier)
        .setScope(
          const SessionScope(
            userId: fixtureCustomerId,
            role: 'shipper',
            generation: 3,
          ),
        );
    await settle(container);
    repository.lists.single.complete(page());
    await settle(container);
    final state = container.read(listProvider).requireValue;
    expect(state.data, isNull);
    expect(state.failure!.code, AppFailure.forbiddenOrUnavailable);
    expect(repository.listRoles, ['manager']);
  });

  test(
    'a misrouted customer aggregate is unsupported and never displayed',
    () async {
      await settle(container);
      repository.requests.single.complete(
        detail('delivering', customerId: scopeB.userId!),
      );
      await settle(container);
      final state = container.read(provider).requireValue;
      expect(state.data, isNull);
      expect(state.failure!.code, AppFailure.unsupportedData);
    },
  );

  test('loading and coherent data; unsupported reply is not network', () async {
    await settle(container);
    expect(container.read(provider).requireValue.isInitialLoading, isTrue);
    repository.requests.single.complete(detail('delivering'));
    await settle(container);
    expect(container.read(provider).requireValue.isFresh, isTrue);
    final refresh = container.read(provider.notifier).refresh();
    await settle(container);
    repository.requests.last.completeError(
      UnsupportedDataException.missing('status'),
    );
    await refresh;
    final state = container.read(provider).requireValue;
    expect(state.failure!.code, AppFailure.unsupportedData);
    expect(state.data!.order.status, OrderStatus.delivering);
    expect(state.stale, isTrue);
    expect(state.isFresh, isFalse);
  });

  test(
    'TX-05/25: historical receipt resolves outcome without cache regression',
    () async {
      await settle(container);
      repository.requests.single.complete(detail('delivering'));
      await settle(container);
      final vm = container.read(provider.notifier);
      final receipt = OrderMutationReceiptDto.fromJson({
        'operation': 'confirm',
        'request_id': fixtureMutationRequestId,
        'event_id': fixtureEventId,
        'order': fixtureOrderJson(status: 'preparing'),
        'committed_at': '2026-10-08T03:40:00Z',
        'replayed': true,
        'current_order': null,
      }).domain;
      final expected = StableOrderCommand(
        orderId: fixtureOrderId,
        requestId: fixtureMutationRequestId,
        operation: OrderOperation.confirm,
      );
      expect(
        vm.acceptHistoricalReceipt(
          receipt,
          submittedScope: scopeA,
          expectedCommand: expected,
        ),
        isTrue,
      );
      await settle(container);
      expect(
        container.read(provider).requireValue.data!.order.status,
        OrderStatus.delivering,
      );
      repository.requests.last.completeError(
        const AppFailure(code: AppFailure.network),
      );
      await settle(container);
      final state = container.read(provider).requireValue;
      expect(vm.actionOutcome, same(receipt));
      expect(state.data!.order.status, OrderStatus.delivering);
      expect(state.stale, isTrue);
      expect(state.isFresh, isFalse);
      expect(
        vm.acceptHistoricalReceipt(
          receipt,
          submittedScope: scopeB,
          expectedCommand: expected,
        ),
        isFalse,
      );
      final wrong = StableOrderCommand(
        orderId: fixtureOrderId,
        requestId: fixturePlacementRequestId,
        operation: OrderOperation.confirm,
      );
      expect(
        vm.acceptHistoricalReceipt(
          receipt,
          submittedScope: scopeA,
          expectedCommand: wrong,
        ),
        isFalse,
      );
      // Another private resource can detect expiry before Auth updates scope.
      container.read(epochCacheProvider).blockSession();
      expect(vm.actionOutcome, isNull);
      expect(container.read(provider).requireValue.data, isNull);
    },
  );

  test(
    'TX-26: invalidated inflight read discarded, latest refresh serialized',
    () async {
      await settle(container);
      final refresh = container.read(provider.notifier).refresh();
      expect(repository.requests.length, 1);
      repository.requests.first.complete(detail('preparing'));
      await settle(container);
      expect(repository.requests.length, 2);
      expect(container.read(provider).requireValue.data, isNull);
      repository.requests.last.complete(detail('delivering'));
      await refresh;
      expect(
        container.read(provider).requireValue.data!.order.status,
        OrderStatus.delivering,
      );
    },
  );

  test('TX-08: account switch clears A and drops its late callback', () async {
    await settle(container);
    container.read(testSessionProvider.notifier).setScope(scopeB);
    await settle(container);
    expect(container.read(provider).requireValue.data, isNull);
    expect(
      repository.requests.length,
      2,
      reason: 'B must load while A is still pending',
    );
    repository.requests.first.complete(detail('preparing'));
    await settle(container);
    expect(container.read(provider).requireValue.data, isNull);
    repository.requests.last.complete(
      detail('delivered', customerId: scopeB.userId!),
    );
    await settle(container);
    expect(
      container.read(provider).requireValue.data!.order.status,
      OrderStatus.delivered,
    );
    expect(
      container.read(provider).requireValue.data!.order.customerId,
      scopeB.userId,
    );
  });

  test(
    'receipt callback after session expiry cannot resolve an action',
    () async {
      await settle(container);
      repository.requests.single.complete(detail('delivering'));
      await settle(container);
      final vm = container.read(provider.notifier);
      final refresh = vm.refresh();
      await settle(container);
      repository.requests.last.completeError(
        const AppFailure(code: AppFailure.unauthenticated),
      );
      await refresh;
      final receipt = OrderMutationReceiptDto.fromJson({
        'operation': 'confirm',
        'request_id': fixtureMutationRequestId,
        'event_id': fixtureEventId,
        'order': fixtureOrderJson(status: 'preparing'),
        'committed_at': '2026-10-08T03:40:00Z',
        'replayed': true,
        'current_order': null,
      }).domain;
      expect(
        vm.acceptHistoricalReceipt(
          receipt,
          submittedScope: scopeA,
          expectedCommand: StableOrderCommand(
            orderId: fixtureOrderId,
            requestId: fixtureMutationRequestId,
            operation: OrderOperation.confirm,
          ),
        ),
        isFalse,
      );
      expect(vm.actionOutcome, isNull);
      expect(container.read(provider).requireValue.data, isNull);
    },
  );

  test('missing production adapter is explicit external dependency', () async {
    container.updateOverrides([
      featureSessionScopeProvider.overrideWith(
        (ref) => ref.watch(testSessionProvider),
      ),
      orderRepositoryProvider.overrideWithValue(null),
      readRetryPolicyProvider.overrideWithValue(
        const ReadRetryPolicy(backoffs: []),
      ),
    ]);
    await settle(container);
    expect(
      container.read(provider).requireValue.failure!.code,
      AppFailure.externalDependencyUnavailable,
    );
    expect(container.read(provider).requireValue.data, isNull);
  });
}
