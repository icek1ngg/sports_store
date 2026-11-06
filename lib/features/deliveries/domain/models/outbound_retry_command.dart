/// Idempotent request to create the second outbound task for the same holder.
///
/// The server derives order, shipper, custody and attempt state from the
/// failed task. The client supplies only the failed task identity and a stable
/// request key so an uncertain response can be retried safely.
final class OutboundRetryCommand {
  const OutboundRetryCommand({required this.taskId, required this.requestId});

  final String taskId;
  final String requestId;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  bool get isValid => _uuid.hasMatch(taskId) && _uuid.hasMatch(requestId);

  @override
  bool operator ==(Object other) =>
      other is OutboundRetryCommand &&
      taskId == other.taskId &&
      requestId == other.requestId;

  @override
  int get hashCode => Object.hash(taskId, requestId);

  @override
  String toString() =>
      'OutboundRetryCommand(taskId: $taskId, requestId: $requestId)';
}

/// Validated receipt for the explicit shipper-owned second-attempt transition.
///
/// This receipt is not a task projection. Callers must read the newly created
/// task before presenting it as available for acceptance/start.
final class OutboundRetryAck {
  const OutboundRetryAck({
    required this.failedTaskId,
    required this.retryTaskId,
    required this.requestId,
  });

  final String failedTaskId;
  final String retryTaskId;
  final String requestId;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  bool get isValid =>
      _uuid.hasMatch(failedTaskId) &&
      _uuid.hasMatch(retryTaskId) &&
      _uuid.hasMatch(requestId);

  bool matches(OutboundRetryCommand command) =>
      _sameUuid(failedTaskId, command.taskId) &&
      _sameUuid(requestId, command.requestId);

  @override
  bool operator ==(Object other) =>
      other is OutboundRetryAck &&
      failedTaskId == other.failedTaskId &&
      retryTaskId == other.retryTaskId &&
      requestId == other.requestId;

  @override
  int get hashCode => Object.hash(failedTaskId, retryTaskId, requestId);

  @override
  String toString() =>
      'OutboundRetryAck(failedTaskId: $failedTaskId, '
      'retryTaskId: $retryTaskId, requestId: $requestId)';

  static bool _sameUuid(String left, String right) =>
      left.toLowerCase() == right.toLowerCase();
}
