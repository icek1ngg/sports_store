import '../models/outbound_completion_command.dart';

/// Contract for the P05.1 successful outbound completion write.
///
/// An adapter must return only after the server transaction commits,
/// preserve [OutboundCompletionCommand.requestId] for an uncertain retry, and
/// never make a local optimistic task-state change.
abstract interface class OutboundCompletionRepository {
  Future<void> execute(OutboundCompletionCommand command);
}
