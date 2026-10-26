/// Draft, transport-neutral input for reporting an outbound delivery failure.
///
/// P07.1 deliberately has no live RPC.  This model is a domain seam for the
/// test-only P07.3 harness and must not be treated as a Supabase payload by
/// runtime code until the server contract is approved.
enum OutboundFailureReason {
  unreachable('unreachable'),
  reschedule('reschedule'),
  badAddress('bad_address'),
  refusal('refusal'),
  other('other');

  const OutboundFailureReason(this.value);

  final String value;

  static OutboundFailureReason fromValue(String value) {
    for (final reason in values) {
      if (reason.value == value) return reason;
    }
    throw FormatException('Unknown outbound failure reason: $value');
  }
}

/// The disposition returned by a future failure transaction.
///
/// A first failed attempt remains with the manager for a retry/return
/// decision.  A second failed attempt remains pending store return.  The
/// server, rather than the client, chooses the disposition; the attempt
/// mapping below is only a defensive check at the transport boundary.
enum OutboundFailureDisposition {
  managerDecision('manager_decision'),
  storeReturnPending('store_return_pending');

  const OutboundFailureDisposition(this.value);

  final String value;

  static OutboundFailureDisposition fromValue(String value) {
    for (final disposition in values) {
      if (disposition.value == value) return disposition;
    }
    throw FormatException('Unknown outbound failure disposition: $value');
  }

  static OutboundFailureDisposition forAttempt(int attemptNumber) {
    return switch (attemptNumber) {
      1 => managerDecision,
      2 => storeReturnPending,
      _ => throw ArgumentError.value(
        attemptNumber,
        'attemptNumber',
        'must be 1 or 2',
      ),
    };
  }
}

/// Idempotent, client-controlled input for the future failure API.
///
/// The command intentionally contains no amount, shipper identity, schedule,
/// COD or stock fields.  The server derives actor, assignment, timestamps and
/// all aggregate changes from its locked state. [attemptNumber] is retained as
/// local snapshot evidence so an ACK/read can be checked against the task that
/// was confirmed; it is not a client-supplied server transition argument.
/// [requestId] is the stable idempotency key and must be reused after an
/// uncertain response.
class OutboundFailureCommand {
  const OutboundFailureCommand({
    required this.taskId,
    required this.requestId,
    required this.attemptNumber,
    required this.reason,
    this.description,
  });

  final String taskId;
  final String requestId;
  final int attemptNumber;
  final OutboundFailureReason reason;
  final String? description;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  bool get hasUuidShape => _uuid.hasMatch(taskId) && _uuid.hasMatch(requestId);

  bool get isUuidShaped => hasUuidShape;

  bool get hasValidAttempt => attemptNumber == 1 || attemptNumber == 2;

  /// A description is required for [OutboundFailureReason.other].  For the
  /// other reason codes, a supplied description is retained after trimming,
  /// but an empty value is represented as null.
  bool get hasValidDescription {
    final trimmed = description?.trim();
    return reason == OutboundFailureReason.other
        ? trimmed != null && trimmed.isNotEmpty
        : true;
  }

  /// The canonical text sent by a future adapter.  This getter makes the
  /// whitespace rule explicit without mutating the immutable command.
  String? get trimmedDescription {
    final trimmed = description?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  bool get isValid =>
      hasUuidShape &&
      hasValidAttempt &&
      hasValidDescription &&
      taskId.trim().isNotEmpty &&
      requestId.trim().isNotEmpty;

  @override
  bool operator ==(Object other) {
    return other is OutboundFailureCommand &&
        taskId == other.taskId &&
        requestId == other.requestId &&
        attemptNumber == other.attemptNumber &&
        reason == other.reason &&
        description == other.description;
  }

  @override
  int get hashCode =>
      Object.hash(taskId, requestId, attemptNumber, reason, description);

  @override
  String toString() =>
      'OutboundFailureCommand(taskId: $taskId, requestId: $requestId, '
      'attemptNumber: $attemptNumber, reason: ${reason.value}, '
      'hasDescription: ${trimmedDescription != null})';
}

/// Server acknowledgement draft for [OutboundFailureCommand].
///
/// This is not a task snapshot.  A harness must perform a separate
/// authoritative detail read and only then expose a failed result.
class OutboundFailureAck {
  const OutboundFailureAck({
    required this.taskId,
    required this.requestId,
    required this.attemptNumber,
    required this.disposition,
  });

  final String taskId;
  final String requestId;
  final int attemptNumber;
  final OutboundFailureDisposition disposition;

  bool get hasUuidShape =>
      OutboundFailureCommand._uuid.hasMatch(taskId) &&
      OutboundFailureCommand._uuid.hasMatch(requestId);

  bool matches(OutboundFailureCommand command) {
    return taskId == command.taskId &&
        requestId == command.requestId &&
        attemptNumber == command.attemptNumber &&
        disposition ==
            OutboundFailureDisposition.forAttempt(command.attemptNumber);
  }

  bool get isValid =>
      hasUuidShape &&
      (attemptNumber == 1 || attemptNumber == 2) &&
      disposition == OutboundFailureDisposition.forAttempt(attemptNumber);

  @override
  bool operator ==(Object other) {
    return other is OutboundFailureAck &&
        taskId == other.taskId &&
        requestId == other.requestId &&
        attemptNumber == other.attemptNumber &&
        disposition == other.disposition;
  }

  @override
  int get hashCode =>
      Object.hash(taskId, requestId, attemptNumber, disposition);

  @override
  String toString() =>
      'OutboundFailureAck(taskId: $taskId, requestId: $requestId, '
      'attemptNumber: $attemptNumber, disposition: ${disposition.value})';
}
