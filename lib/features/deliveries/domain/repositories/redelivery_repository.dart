import '../models/redelivery_command.dart';

/// Executes shipper-owned redelivery writes against the production RPCs.
///
/// Implementations return only after a strict server receipt has been
/// validated.  Callers must refetch the authorized task detail before
/// presenting the new state, and must reuse the same command after an
/// uncertain response.
abstract interface class RedeliveryRepository {
  Future<RedeliveryAck> execute(RedeliveryCommand command);
}

typedef DeliveryRedeliveryRepository = RedeliveryRepository;
