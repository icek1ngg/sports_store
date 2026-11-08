import '../../../../core/errors/app_failure.dart';
import '../../../../core/state/session_scope.dart';
import '../../domain/models/order_command.dart';
import '../../domain/models/order_mutation_receipt.dart';
import '../../domain/models/order_status.dart';
import '../../domain/models/operation_result.dart';
import '../../domain/repositories/order_repository.dart';

/// Saves before dispatch and reconciles restored intent before same-key retry.
/// This controller never treats a receipt snapshot as a current read aggregate.
class OrderCommandController {
  OrderCommandController({
    required this.repository,
    required this.store,
    required this.scope,
    required this.readSession,
  });
  final OrderRepository repository;
  final PendingOrderCommandStore store;
  final SessionScope scope;
  final SessionScope Function() readSession;
  final Set<String> _busyOrders = {};

  void _guard() {
    if (!scope.canReadPrivateData || readSession() != scope) {
      throw const AppFailure(code: AppFailure.unauthenticated);
    }
  }

  bool _same(StableOrderCommand a, StableOrderCommand b) =>
      a.orderId == b.orderId &&
      a.operation == b.operation &&
      a.reason == b.reason;

  /// Startup/account restoration is lookup-only. not_found never resubmits.
  Future<List<OperationResult>> recoverPending() async {
    _guard();
    final pending = await store.list();
    _guard();
    final results = <OperationResult>[];
    for (final command in pending) {
      if (!_busyOrders.add(command.orderId)) continue;
      try {
        final result = await repository.getOperationResult(
          requestId: command.requestId,
          orderId: command.orderId,
          operation: command.operation,
        );
        _guard();
        if (!result.isNotFound) {
          await store.remove(command.requestId);
          _guard();
        }
        results.add(result);
      } finally {
        _busyOrders.remove(command.orderId);
      }
    }
    return results;
  }

  Future<OrderMutationReceipt> execute(StableOrderCommand intent) async {
    _guard();
    if (!_busyOrders.add(intent.orderId)) {
      throw const AppFailure(
        code: AppFailure.outcomeUnknownCode,
        outcomeUnknown: true,
      );
    }
    try {
      final pending = await store.list();
      _guard();
      final forOrder = pending
          .where((value) => value.orderId == intent.orderId)
          .toList();
      if (forOrder.length > 1) {
        throw const AppFailure(code: AppFailure.dataIntegrity);
      }
      var command = intent;
      if (forOrder.isNotEmpty) {
        command = forOrder.single;
        // Resolve the old outcome even when a new dialog contains changed text.
        final result = await repository.getOperationResult(
          requestId: command.requestId,
          orderId: command.orderId,
          operation: command.operation,
        );
        _guard();
        if (result.isCommitted) {
          await store.remove(command.requestId);
          _guard();
          return result.receipt!;
        }
        if (result.isFailed) {
          await store.remove(command.requestId);
          _guard();
          throw result.failure!;
        }
        if (!_same(command, intent)) {
          throw const AppFailure(
            code: AppFailure.outcomeUnknownCode,
            outcomeUnknown: true,
            retryable: true,
          );
        }
      } else {
        await store.save(command);
        _guard();
      }
      // A thrown response is retained: lookup, not an assumed rollback, decides
      // when it is safe to discard a pending command.
      final receipt = await switch (command.operation) {
        OrderOperation.confirm => repository.confirm(command),
        OrderOperation.reject => repository.reject(command),
        OrderOperation.customerCancel => repository.cancelCustomer(command),
        OrderOperation.managerCancel => repository.cancelManager(command),
        _ => throw const AppFailure(code: AppFailure.invalidArgument),
      };
      _guard();
      await store.remove(command.requestId);
      _guard();
      return receipt;
    } finally {
      _busyOrders.remove(intent.orderId);
    }
  }
}
