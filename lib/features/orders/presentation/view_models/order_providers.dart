import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/state/foundation_providers.dart';
import '../../../../core/state/read_snapshot.dart';
import '../../../../core/state/session_scope.dart';
import '../../../../core/state/snapshot_read_view_model.dart';
import '../../domain/models/order_details.dart';
import '../../domain/models/order_command.dart';
import '../../domain/models/order_mutation_receipt.dart';
import '../../domain/models/order_page.dart';
import '../../domain/models/order_query.dart';
import '../../domain/repositories/order_repository.dart';

/// Phase 2 supplies the actual adapter using the shared Supabase client.
final orderRepositoryProvider = Provider<OrderRepository?>((ref) => null);

final orderDetailsFoundationProvider = AsyncNotifierProvider.autoDispose
    .family<
      OrderDetailsFoundationViewModel,
      ReadSnapshot<OrderDetails>,
      String
    >(OrderDetailsFoundationViewModel.new, retry: (count, error) => null);

final orderListFoundationProvider = AsyncNotifierProvider.autoDispose
    .family<OrderListFoundationViewModel, ReadSnapshot<OrderPage>, OrderQuery>(
      OrderListFoundationViewModel.new,
      retry: (count, error) => null,
    );

mixin _OrderReadFailure<T extends Object> on SnapshotReadViewModel<T> {
  @override
  AppFailure readFailure(Object error) => error is TimeoutException
      ? const AppFailure(
          code: AppFailure.network,
          messageKey: 'MSG-09',
          retryable: true,
        )
      : const AppFailure(code: AppFailure.unsupportedData);

  @override
  bool shouldClearPrivateData(AppFailure failure) =>
      failure.code == AppFailure.unauthenticated ||
      failure.code == AppFailure.forbiddenOrUnavailable;

  @override
  bool get scopeAllowed => const {
    'customer',
    'manager',
  }.contains(ref.read(featureSessionScopeProvider).role);
}

class OrderDetailsFoundationViewModel
    extends SnapshotReadViewModel<OrderDetails>
    with _OrderReadFailure<OrderDetails> {
  OrderDetailsFoundationViewModel(this.orderId);
  final String orderId;
  OrderMutationReceipt? _actionOutcome;
  OrderMutationReceipt? get actionOutcome => _actionOutcome;

  @override
  void onPrivateDataCleared() => _actionOutcome = null;

  @override
  String get resourceKey => 'orders/detail/$orderId';

  @override
  Future<OrderDetails> Function() configureLoader() {
    final repository = ref.watch(orderRepositoryProvider);
    final scope = ref.watch(featureSessionScopeProvider);
    _actionOutcome = null;
    return () async {
      if (repository == null) {
        throw const AppFailure(code: AppFailure.externalDependencyUnavailable);
      }
      final detail = await repository.getOrderDetails(orderId);
      if (detail.order.id != orderId ||
          (scope.role == 'customer' &&
              detail.order.customerId != scope.userId)) {
        throw const AppFailure(code: AppFailure.unsupportedData);
      }
      return detail;
    };
  }

  @override
  bool isEmpty(OrderDetails data) => false;

  @override
  void onAccepted(OrderDetails data) {
    ref.read(epochCacheProvider).invalidatePrefix('orders/list/');
  }

  /// Phase 1 outcome hook, not a command sender. Receipts never enter cache.
  /// The submitter must pass the session captured before the request.
  bool acceptHistoricalReceipt(
    OrderMutationReceipt receipt, {
    required SessionScope submittedScope,
    required StableOrderCommand expectedCommand,
  }) {
    final scope = ref.read(featureSessionScopeProvider);
    if (!ref.mounted ||
        scope != submittedScope ||
        !scope.canReadPrivateData ||
        !ref.read(epochCacheProvider).canRead ||
        receipt.order.id != orderId ||
        expectedCommand.orderId != orderId ||
        receipt.requestId != expectedCommand.requestId ||
        receipt.operation != expectedCommand.operation ||
        !scopeAllowed) {
      return false;
    }
    _actionOutcome = receipt;
    ref.read(epochCacheProvider).invalidatePrefix('orders/');
    return true;
  }
}

class OrderListFoundationViewModel extends SnapshotReadViewModel<OrderPage>
    with _OrderReadFailure<OrderPage> {
  OrderListFoundationViewModel(this.query);
  final OrderQuery query;

  @override
  String get resourceKey => 'orders/list/${jsonEncode(query.toRpcParams())}';

  @override
  Future<OrderPage> Function() configureLoader() {
    final repository = ref.watch(orderRepositoryProvider);
    final scope = ref.watch(featureSessionScopeProvider);
    return () async {
      if (repository == null) {
        throw const AppFailure(code: AppFailure.externalDependencyUnavailable);
      }
      final page = await (scope.role == 'manager'
          ? repository.getManagerOrders(query)
          : repository.getCustomerOrders(query));
      if (scope.role == 'customer' &&
          page.items.any((item) => item.order.customerId != scope.userId)) {
        throw const AppFailure(code: AppFailure.unsupportedData);
      }
      return page;
    };
  }

  @override
  bool isEmpty(OrderPage data) => data.items.isEmpty;
}
