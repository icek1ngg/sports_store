import '../models/outbound_failure_command.dart';

/// Records failure using an atomic server transaction. Implementations must
/// validate the acknowledgement and never update a task optimistically.
abstract interface class OutboundFailureRepository {
  Future<OutboundFailureAck> execute(OutboundFailureCommand command);
}
