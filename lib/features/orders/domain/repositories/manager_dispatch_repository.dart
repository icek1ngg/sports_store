class DispatchShipper {
  const DispatchShipper({required this.id, required this.name});
  final String id;
  final String name;
}

class DispatchFailure implements Exception {
  const DispatchFailure(this.message, {this.ambiguous = false});
  final String message;
  final bool ambiguous;
}

abstract interface class ManagerDispatchRepository {
  Future<List<DispatchShipper>> loadShippers();
  Future<void> prepareAndAssign({
    required String orderId,
    required String shipperId,
    required String requestId,
  });
}
