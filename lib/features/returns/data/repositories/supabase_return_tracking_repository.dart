import '../../../deliveries/data/repositories/operational_read_access.dart';
import '../../domain/models/return_request_failure.dart';
import '../../domain/models/return_request_submission.dart';
import '../../domain/models/return_tracking.dart';
import '../../domain/repositories/return_tracking_repository.dart';
import '../models/return_tracking_dto.dart';
import 'supabase_return_request_repository.dart';

/// Supabase adapter for MH14. `get_my_return_request` verifies ownership on
/// every read; another customer's id returns `RETURN_NOT_FOUND`.
final class SupabaseReturnTrackingRepository
    implements ReturnTrackingRepository {
  const SupabaseReturnTrackingRepository({required this.access});

  final OperationalReadAccess access;

  @override
  Future<ReturnTracking> load(String returnId) {
    return runCustomerReturnCall(access, (identity) async {
      final raw = await access.client
          .rpc('get_my_return_request', params: {'p_return_id': returnId})
          .retry(enabled: false);
      identity.ensureCurrent();
      if (raw is! Map) throw const FormatException('Invalid return tracking');
      final tracking = returnTrackingFromJson(Map<String, Object?>.from(raw));
      if (tracking.returnId != returnId) {
        throw const FormatException('Tracking for another return');
      }
      return tracking;
    });
  }

  /// The schema has no "more information" request yet (MH15 dependency), so
  /// the server never reports an open request and nothing can be answered.
  @override
  Future<void> submitAdditionalInfo({
    required String returnId,
    required String requestId,
    required String description,
    ReturnVideoFile? video,
  }) async {
    throw const ReturnRequestFailure(
      ReturnRequestFailureCode.backendUnavailable,
    );
  }
}
