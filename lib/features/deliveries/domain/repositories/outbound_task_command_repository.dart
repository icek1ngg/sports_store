import '../models/outbound_task_command.dart';

/// P04.2 accept/start writes using the production P04.1 contract.
/// An adapter returns only after the server has
/// committed, retain [OutboundTaskCommand.requestId] on timeout retries, and
/// let the ViewModel refetch authoritative task state after acknowledgement.
abstract interface class OutboundTaskCommandRepository {
  Future<void> execute(OutboundTaskCommand command);
}
