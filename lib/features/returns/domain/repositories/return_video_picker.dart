import '../models/return_request_submission.dart';

/// Picks one local unboxing video. Returns null when the customer cancels.
/// Throws [ReturnVideoPickFailure] for unsupported or oversized files.
abstract interface class ReturnVideoPicker {
  Future<ReturnVideoFile?> pickVideo();
}

class ReturnVideoPickFailure implements Exception {
  const ReturnVideoPickFailure(this.message);

  final String message;
}
