import '../models/return_request_submission.dart';
import '../models/return_tracking.dart';

/// MH14 contract. Implementations verify ownership on every call and throw
/// `ReturnRequestFailure`. Customers can only read and answer an open
/// information request; they never change operational state.
abstract interface class ReturnTrackingRepository {
  Future<ReturnTracking> load(String returnId);

  /// Answers the manager's open information request. [requestId] is the
  /// idempotency key and is reused when retrying an ambiguous attempt.
  Future<void> submitAdditionalInfo({
    required String returnId,
    required String requestId,
    required String description,
    ReturnVideoFile? video,
  });
}
