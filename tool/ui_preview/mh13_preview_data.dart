// DEMO UI data for the MH13 preview only. Mirrors the approved mock-up and is
// never imported by lib/ or the production entrypoint.
import 'package:sports_store/features/returns/domain/models/return_request_context.dart';
import 'package:sports_store/features/returns/domain/models/return_request_submission.dart';
import 'package:sports_store/features/returns/domain/repositories/return_request_repository.dart';
import 'package:sports_store/features/returns/presentation/view_models/create_return_state.dart';

/// DEMO repository: same contract as Supabase, no network. Clearly fake —
/// the receipt id is a fixed demo UUID.
class Mh13DemoReturnRepository implements ReturnRequestRepository {
  @override
  Future<ReturnRequestContext> loadContext(String orderId) =>
      throw UnsupportedError('DEMO preview renders step 1 from mh13DemoOrder');

  @override
  Future<String> uploadVideo({
    required String orderId,
    required String requestId,
    required ReturnVideoFile video,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return 'demo-customer/$orderId/$requestId.${video.extension}';
  }

  @override
  Future<ReturnRequestReceipt> submit(ReturnRequestCommand command) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    return ReturnRequestReceipt(
      returnRequestId: '00000000-0000-4000-8000-0000000d3e00',
      orderId: command.orderId,
      status: 'pending_review',
      submittedAt: DateTime.now().toUtc(),
      replayed: false,
    );
  }
}

final mh13DemoOrder = ReturnOrderOverview(
  orderId: '00000000-0000-4000-8000-000000000128',
  orderCode: 'DH000128',
  // 01/10/2026 14:30 (Hà Nội) = 07:30 UTC.
  deliveredAt: DateTime.utc(2026, 10, 1, 7, 30),
  returnDeadline: DateTime.utc(2026, 10, 8, 7, 30),
  referenceTime: DateTime.utc(2026, 10, 3, 7, 30),
  deliveryFeeVnd: 30000,
  canSubmitReturn: true,
  lines: const [
    ReturnOrderLine(
      productName: 'Áo Thể Thao Nam STRIDE DryFit',
      variantLabel: 'Màu Đen / Size M',
      quantity: 2,
      unitPriceVnd: 260000,
    ),
  ],
);
