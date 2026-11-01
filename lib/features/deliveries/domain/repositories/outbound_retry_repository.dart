import '../models/outbound_retry_command.dart';

/// Creates the next outbound task after a first failed attempt.
abstract interface class OutboundRetryRepository {
  Future<OutboundRetryAck> execute(OutboundRetryCommand command);
}
