/// Transport-agnostic input for the successful outbound completion
/// contract.
///
/// The amount attests full cash physically collected; the server independently
/// derives and validates the authoritative COD total.
class OutboundCompletionCommand {
  const OutboundCompletionCommand({
    required this.taskId,
    required this.requestId,
    required this.receivedAllItems,
    required this.reportedCollectedAmountVnd,
  });

  final String taskId;
  final String requestId;
  final bool receivedAllItems;
  final int reportedCollectedAmountVnd;

  /// UUID validation is deliberately version agnostic.  Version and variant
  /// policy belong to the server contract, not to a client fixture.
  bool get hasUuidShape {
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return uuid.hasMatch(taskId) && uuid.hasMatch(requestId);
  }

  /// Alias matching the existing P04.2 command seam.
  bool get isUuidShaped => hasUuidShape;

  bool get hasNonEmptyIds =>
      taskId.trim().isNotEmpty && requestId.trim().isNotEmpty;

  /// VND values are integer amounts.  The upper bound keeps the draft
  /// transport inside the JavaScript-safe integer range used by Supabase
  /// clients while allowing a future server to impose a smaller business cap.
  bool get hasSafePositiveAmount =>
      reportedCollectedAmountVnd > 0 &&
      reportedCollectedAmountVnd <= 9007199254740991;

  bool get isValid => hasUuidShape && receivedAllItems && hasSafePositiveAmount;

  @override
  bool operator ==(Object other) {
    return other is OutboundCompletionCommand &&
        taskId == other.taskId &&
        requestId == other.requestId &&
        receivedAllItems == other.receivedAllItems &&
        reportedCollectedAmountVnd == other.reportedCollectedAmountVnd;
  }

  @override
  int get hashCode => Object.hash(
    taskId,
    requestId,
    receivedAllItems,
    reportedCollectedAmountVnd,
  );

  @override
  String toString() =>
      'OutboundCompletionCommand(taskId: $taskId, requestId: $requestId, '
      'receivedAllItems: $receivedAllItems, '
      'reportedCollectedAmountVnd: $reportedCollectedAmountVnd)';
}
