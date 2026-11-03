import '../models/manager_return.dart';

/// Return management for managers. Implementations check the manager role on
/// the server for every call and throw `ReturnRequestFailure`.
///
/// Every write takes [requestId] as the idempotency key: reuse the same key
/// when retrying an attempt whose outcome is unknown.
abstract interface class ManagerReturnRepository {
  Future<ManagerReturnList> list({ReturnRequestStatus? status, String? query});

  Future<ManagerReturnDetail> load(String returnId);

  /// Short-lived URL to play a private return video.
  Future<Uri> videoUrl(String objectPath);

  /// Short-lived URL to view private inspection/transfer evidence.
  Future<Uri> evidenceUrl(ManagerEvidenceKind kind, String objectPath);

  /// Uploads evidence under `<returnId>/` in the private bucket for [kind]
  /// and returns the object path. Re-uploading the same [objectName] is a
  /// no-op so a retried command can reuse the path.
  Future<String> uploadEvidence({
    required String returnId,
    required ManagerEvidenceKind kind,
    required String objectName,
    required ManagerEvidenceFile file,
  });

  /// Defines the goods to collect, approves pickup and assigns [shipperId]
  /// in one server transaction. This is not a refund approval.
  Future<void> approveCollection({
    required String returnId,
    required String requestId,
    required List<ManagerCollectionLine> lines,
    required String shipperId,
  });

  /// Rejects a pending request before pickup; goods stay with the customer.
  Future<void> reject({
    required String returnId,
    required String requestId,
    required String reason,
  });

  /// Asks the customer for more information; the request stays open.
  Future<void> requestInfo({
    required String returnId,
    required String requestId,
    required String message,
  });

  /// Records the store receipt of every collected line (existing pickup RPC).
  Future<void> receive({
    required String returnId,
    required String taskId,
    required String requestId,
    required List<ManagerReturnItem> items,
  });

  /// Inspection accepted: sellable goods restocked once, then awaiting refund.
  Future<void> acceptInspection({
    required String returnId,
    required String requestId,
    required List<ManagerInspectionLine> lines,
    required List<String> evidencePaths,
  });

  /// Inspection rejected with evidence; goods go back by free redelivery.
  Future<void> rejectInspection({
    required String returnId,
    required String requestId,
    required String reason,
    required List<String> evidencePaths,
  });

  /// Records the full refund the manager transferred outside the app.
  Future<void> recordRefund({
    required String returnId,
    required String requestId,
    required int amountVnd,
    required DateTime transferredAt,
    required String evidencePath,
  });

  /// Assigns the free redelivery (existing RPC; no COD).
  Future<void> assignRedelivery({
    required String returnId,
    required String requestId,
    required String shipperId,
  });
}
