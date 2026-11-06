import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../deliveries/data/repositories/operational_read_access.dart';
import '../../domain/models/return_request_failure.dart';
import '../../domain/models/return_request_submission.dart';
import '../../domain/models/return_tracking.dart';
import '../../domain/repositories/return_tracking_repository.dart';
import '../models/return_tracking_dto.dart';
import 'supabase_return_request_repository.dart';

/// Supabase adapter for MH14. `get_my_return_request` verifies ownership on
/// every read; another customer's id returns `RETURN_NOT_FOUND`.
/// Information requests come from `get_my_return_info_request` and are
/// answered with `respond_return_info` (return management migration).
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
      final info = await _loadInfoRequest(returnId);
      identity.ensureCurrent();
      final tracking = returnTrackingFromJson(
        Map<String, Object?>.from(raw),
        infoRequest: info,
      );
      if (tracking.returnId != returnId) {
        throw const FormatException('Tracking for another return');
      }
      return tracking;
    });
  }

  /// A server without the information-request RPC simply has no request;
  /// every other error is surfaced like the main read.
  Future<ReturnInfoRequest?> _loadInfoRequest(String returnId) async {
    try {
      final raw = await access.client
          .rpc('get_my_return_info_request', params: {'p_return_id': returnId})
          .retry(enabled: false);
      if (raw is! Map) throw const FormatException('Invalid info request');
      return returnInfoRequestFromJson(Map<String, Object?>.from(raw));
    } on PostgrestException catch (error) {
      if (mapReturnRequestError(error).code ==
          ReturnRequestFailureCode.backendUnavailable) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<void> submitAdditionalInfo({
    required String returnId,
    required String requestId,
    required String description,
    ReturnVideoFile? video,
  }) {
    return runCustomerReturnCall(access, (identity) async {
      String? path;
      if (video != null) {
        // Same naming as MH13: <owner>/<return>/<request>.<ext>; a retry with
        // the same request id finds the object already uploaded.
        path = '${identity.userId}/$returnId/$requestId.${video.extension}';
        try {
          await access.client.storage
              .from(SupabaseReturnRequestRepository.bucket)
              .uploadBinary(
                path,
                video.bytes,
                fileOptions: FileOptions(
                  contentType: video.mimeType,
                  upsert: false,
                ),
              );
        } on StorageException catch (error) {
          final duplicate =
              error.statusCode == '409' ||
              error.message.toLowerCase().contains('already exists');
          if (!duplicate) rethrow;
        }
        identity.ensureCurrent();
      }
      final raw = await access.client
          .rpc(
            'respond_return_info',
            params: {
              'p_return_id': returnId,
              'p_request_id': requestId,
              'p_description': description,
              'p_video_object_path': path,
            },
          )
          .retry(enabled: false);
      identity.ensureCurrent();
      if (raw is! Map ||
          raw['operation'] != 'respond_return_info' ||
          raw['return_request_id'] != returnId ||
          raw['request_id'] != requestId) {
        throw const FormatException('Unexpected respond_return_info ACK');
      }
    });
  }
}
