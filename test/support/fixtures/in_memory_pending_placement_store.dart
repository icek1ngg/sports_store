import 'package:sports_store/features/checkout/data/repositories/pending_placement_store.dart';
import 'package:sports_store/features/checkout/data/models/pending_placement.dart';
import 'package:sports_store/features/checkout/domain/models/placement_request.dart';

/// Test-only storage double for the user-scoped pending Checkout intent.
class InMemoryPendingPlacementStore implements PendingPlacementStore {
  final Map<String, PendingPlacement> _values = {};

  @override
  Future<PendingPlacement?> read(String userId) async =>
      _values[userId.trim().toLowerCase()];

  @override
  Future<void> write(String userId, PlacementRequest request) async {
    _values[userId.trim().toLowerCase()] = PendingPlacement(request: request);
  }

  @override
  Future<void> clear(String userId) async {
    _values.remove(userId.trim().toLowerCase());
  }
}
