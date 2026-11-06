import '../models/placement_request.dart';
import '../models/placement_result.dart';

abstract interface class CheckoutRepository {
  Future<PlacementResult> placeOrder(PlacementRequest request);

  Future<PlacementLookupResult> lookupPlacementResult(String requestId);
}
