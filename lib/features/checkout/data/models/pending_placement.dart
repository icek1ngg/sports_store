import '../../domain/models/placement_request.dart';

/// A pending payload is scoped by user ID in the store implementation. It is
/// kept separate from [PlacementRequest] so a future schema version can be
/// rejected without ever sending unknown data to the RPC.
class PendingPlacement {
  const PendingPlacement({required this.request});

  final PlacementRequest request;

  String get fingerprint => request.fingerprint;
}
