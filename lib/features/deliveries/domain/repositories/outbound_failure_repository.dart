import '../models/outbound_failure_command.dart';

/// Draft, transport-neutral seam for reporting an outbound delivery failure.
///
/// P07.1 intentionally exposes no live Supabase RPC.  This contract exists
/// for the P07.3 test harness and for a future adapter once the transaction,
/// custody and event contracts are approved.  Implementations must return a
/// server acknowledgement only after its transaction commits, preserve the
/// command request ID for uncertain retries, and never mutate a local task
/// snapshot optimistically.
abstract interface class OutboundFailureRepository {
  Future<OutboundFailureAck> execute(OutboundFailureCommand command);
}
