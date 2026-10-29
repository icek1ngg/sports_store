import '../models/order_command.dart';
import '../models/order_details.dart';
import '../models/order_mutation_receipt.dart';
import '../models/order_page.dart';
import '../models/order_query.dart';
import '../models/operation_result.dart';
import '../models/order_status.dart';

/// Feature boundary for OP-O01..OP-O08.  Implementations must surface a typed
/// failure when the backend cannot confirm a mutation; they must not return a
/// synthetic receipt or an empty successful page.
abstract interface class OrderRepository {
  Future<OrderPage> getCustomerOrders(OrderQuery query);

  Future<OrderPage> getManagerOrders(OrderQuery query);

  Future<OrderDetails> getOrderDetails(String orderId);

  Future<OrderMutationReceipt> confirm(StableOrderCommand command);

  Future<OrderMutationReceipt> reject(StableOrderCommand command);

  Future<OrderMutationReceipt> cancelCustomer(StableOrderCommand command);

  Future<OrderMutationReceipt> cancelManager(StableOrderCommand command);

  Future<OperationResult> getOperationResult({
    required String requestId,
    required String orderId,
    required OrderOperation operation,
  });
}

/// Durable, account-scoped pending command storage required by the restart
/// protocol.  The implementation belongs to shared/auth infrastructure; this
/// contract intentionally has no storage package dependency.
abstract interface class PendingOrderCommandStore {
  Future<void> save(StableOrderCommand command);

  Future<List<StableOrderCommand>> list();

  Future<void> remove(String requestId);
}

extension OrderRepositoryAliases on OrderRepository {
  Future<OrderMutationReceipt> confirmOrder(StableOrderCommand command) =>
      confirm(command);

  Future<OrderMutationReceipt> rejectOrder(StableOrderCommand command) =>
      reject(command);

  Future<OrderMutationReceipt> cancelCustomerOrder(
    StableOrderCommand command,
  ) => cancelCustomer(command);

  Future<OrderMutationReceipt> cancelManagerOrder(StableOrderCommand command) =>
      cancelManager(command);

  Future<OperationResult> lookupOperation({
    required String requestId,
    required String orderId,
    required String operation,
  }) => getOperationResult(
    requestId: requestId,
    orderId: orderId,
    operation: OrderOperation.parse(operation),
  );
}
