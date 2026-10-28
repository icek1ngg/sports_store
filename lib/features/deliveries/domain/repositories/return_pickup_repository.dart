import '../models/return_pickup_command.dart';
import '../models/operational_failure.dart';

/// Executes the two shipper-owned P08.1 pickup writes.
///
/// Implementations must return only after the server transaction commits,
/// preserve [ReturnPickupCommand.requestId] for an uncertain retry, and never
/// optimistically change a task, return request or custody state.
abstract interface class ReturnPickupRepository {
  Future<ReturnPickupAck> execute(ReturnPickupCommand command);
}

/// Optional read capability for the narrow, server-authoritative handover
/// marker. Keeping it separate preserves the P08.1 command seam for callers
/// that only implement collect/fail in fixtures.
abstract interface class ReturnPickupHandoverReader {
  Future<ReturnPickupHandoverStatus> getHandoverStatus(String taskId);
}

/// Alias used by repository wiring that names the capability explicitly.
typedef ReturnPickupHandoverRepository = ReturnPickupHandoverReader;

/// Read the marker when the repository supports the production capability.
/// An implementation without that capability is unavailable, never treated as
/// an unreported marker or a successful handover.
extension ReturnPickupHandoverAccess on ReturnPickupRepository {
  Future<ReturnPickupHandoverStatus> getHandoverStatus(String taskId) {
    final repository = this;
    if (repository is ReturnPickupHandoverReader) {
      return (repository as ReturnPickupHandoverReader).getHandoverStatus(
        taskId,
      );
    }
    return Future<ReturnPickupHandoverStatus>.error(
      const OperationalFailure(OperationalFailureCode.backendUnavailable),
    );
  }
}

/// Short alias for feature-level dependency wiring.
typedef PickupRepository = ReturnPickupRepository;
