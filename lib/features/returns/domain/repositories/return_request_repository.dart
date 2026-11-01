import '../models/return_request_context.dart';
import '../models/return_request_submission.dart';

/// MH13 contract. Implementations throw `ReturnRequestFailure`.
abstract interface class ReturnRequestRepository {
  /// Customer-only read of one owned order (server time + eligibility).
  Future<ReturnRequestContext> loadContext(String orderId);

  /// Uploads the video to private Storage and returns its object path
  /// `<customerId>/<orderId>/<requestId>.<ext>`. Re-uploading the same
  /// request id is treated as already uploaded.
  Future<String> uploadVideo({
    required String orderId,
    required String requestId,
    required ReturnVideoFile video,
  });

  /// Calls `submit_return_request` exactly once per invocation.
  Future<ReturnRequestReceipt> submit(ReturnRequestCommand command);
}
