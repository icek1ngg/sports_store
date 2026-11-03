// DEMO UI data for the MH14 preview only. Never imported by lib/ or the
// production entrypoint. Names, phone and codes are fictional demo values.
import 'package:sports_store/features/returns/domain/models/return_reason.dart';
import 'package:sports_store/features/returns/domain/models/return_request_failure.dart';
import 'package:sports_store/features/returns/domain/models/return_request_submission.dart';
import 'package:sports_store/features/returns/domain/models/return_tracking.dart';
import 'package:sports_store/features/returns/domain/repositories/return_tracking_repository.dart';

const mh14DemoReturnId = '00000000-0000-4000-8000-000000000028';

enum Mh14Scenario {
  awaitingPickupAssigned('Chờ lấy hàng – đã phân công (ảnh mẫu)'),
  awaitingPickupUnassigned('Chờ lấy hàng – chưa phân công'),
  pendingReview('Chờ cửa hàng duyệt'),
  infoRequested('Cửa hàng yêu cầu bổ sung'),
  underInspection('Đang kiểm tra tại cửa hàng'),
  awaitingRefund('Chờ chuyển khoản hoàn tiền'),
  refunded('Đã hoàn tiền'),
  initiallyRejected('Không được duyệt ban đầu'),
  rejectedAwaitingRedelivery('Từ chối sau kiểm tra – chờ giao lại'),
  redeliveryFailed('Giao lại thất bại – cửa hàng xử lý'),
  staleAfterError('Mất kết nối – dữ liệu xác nhận gần nhất');

  const Mh14Scenario(this.label);

  final String label;
}

// 03/10/2026 10:15 Hà Nội = 03:15 UTC.
DateTime _hn(int day, int hour, int minute) =>
    DateTime.utc(2026, 10, day, hour - 7, minute);

const _shipper = ReturnPickupAssignment(
  shipperName: 'Lê Văn Minh',
  shipperPhone: '0900 000 014',
);

ReturnTracking mh14Tracking(
  Mh14Scenario scenario, {
  bool infoAnswered = false,
}) {
  ReturnTrackingEvent e(ReturnTrackingEventKind kind, DateTime at) =>
      ReturnTrackingEvent(kind: kind, occurredAt: at);
  final submitted = e(ReturnTrackingEventKind.submitted, _hn(3, 10, 15));
  final approved = e(ReturnTrackingEventKind.pickupApproved, _hn(3, 11, 30));
  final collected = e(ReturnTrackingEventKind.collected, _hn(5, 9, 40));
  final received = e(ReturnTrackingEventKind.receivedAtStore, _hn(5, 15, 10));
  final accepted = e(ReturnTrackingEventKind.inspectionAccepted, _hn(6, 10, 5));
  final rejected = e(ReturnTrackingEventKind.inspectionRejected, _hn(6, 10, 5));

  ReturnTracking build({
    required ReturnRequestStatus status,
    required List<ReturnTrackingEvent> events,
    ReturnPickupAssignment? pickup,
    String? decisionReason,
    ReturnInfoRequest? infoRequest,
    ReturnRefundRecord? refund,
    ReturnRedelivery? redelivery,
    DateTime? refreshedAt,
  }) => ReturnTracking(
    returnId: mh14DemoReturnId,
    returnCode: 'TH000028',
    orderId: '00000000-0000-4000-8000-000000000128',
    orderCode: 'DH000128',
    status: status,
    reason: ReturnReason.defective,
    submittedAt: submitted.occurredAt,
    refreshedAt: refreshedAt ?? _hn(5, 8, 56),
    events: events,
    items: const [
      ReturnTrackingItem(
        name: 'Áo Thể Thao Nam STRIDE DryFit',
        variantLabel: 'Màu Đen / Size M',
        quantity: 2,
      ),
    ],
    merchandiseVnd: 520000,
    deliveryFeeVnd: 30000,
    pickupAddress: '25 Nguyễn Chí Thanh, Đống Đa, Hà Nội',
    pickup: pickup,
    decisionReason: decisionReason,
    infoRequest: infoRequest,
    refund: refund,
    refundBankName: 'Vietcombank',
    refundAccountMasked: '••••6789',
    redelivery: redelivery,
  );

  return switch (scenario) {
    Mh14Scenario.awaitingPickupAssigned ||
    Mh14Scenario.staleAfterError => build(
      status: ReturnRequestStatus.awaitingReturnPickup,
      events: [submitted, approved],
      pickup: ReturnPickupAssignment(
        shipperName: _shipper.shipperName,
        shipperPhone: _shipper.shipperPhone,
        scheduledAt: _hn(5, 14, 0),
      ),
    ),
    Mh14Scenario.awaitingPickupUnassigned => build(
      status: ReturnRequestStatus.awaitingReturnPickup,
      events: [submitted, approved],
    ),
    Mh14Scenario.pendingReview => build(
      status: ReturnRequestStatus.pendingReview,
      events: [submitted],
      refreshedAt: _hn(3, 10, 40),
    ),
    Mh14Scenario.infoRequested => build(
      status: ReturnRequestStatus.pendingReview,
      events: [
        submitted,
        e(ReturnTrackingEventKind.infoRequested, _hn(3, 14, 20)),
      ],
      infoRequest: ReturnInfoRequest(
        message:
            'Video chưa thấy rõ vết bung chỉ ở vai áo. Bạn quay cận cảnh vị '
            'trí lỗi và mô tả thêm giúp cửa hàng nhé.',
        requestedAt: _hn(3, 14, 20),
        respondedAt: infoAnswered ? _hn(3, 15, 2) : null,
      ),
      refreshedAt: _hn(3, 15, 5),
    ),
    Mh14Scenario.underInspection => build(
      status: ReturnRequestStatus.underInspection,
      events: [submitted, approved, collected, received],
      refreshedAt: _hn(5, 16, 0),
    ),
    Mh14Scenario.awaitingRefund => build(
      status: ReturnRequestStatus.awaitingRefund,
      events: [submitted, approved, collected, received, accepted],
      refreshedAt: _hn(6, 10, 30),
    ),
    Mh14Scenario.refunded => build(
      status: ReturnRequestStatus.refunded,
      events: [
        submitted,
        approved,
        collected,
        received,
        accepted,
        e(ReturnTrackingEventKind.refunded, _hn(6, 16, 45)),
      ],
      refund: ReturnRefundRecord(
        amountVnd: 550000,
        refundedAt: _hn(6, 16, 45),
        hasTransferEvidence: true,
      ),
      refreshedAt: _hn(6, 17, 0),
    ),
    Mh14Scenario.initiallyRejected => build(
      status: ReturnRequestStatus.initiallyRejected,
      events: [
        submitted,
        e(ReturnTrackingEventKind.initiallyRejected, _hn(3, 16, 0)),
      ],
      decisionReason:
          'Video không cho thấy lỗi sản phẩm như mô tả và tem mác đã bị cắt.',
      refreshedAt: _hn(3, 16, 5),
    ),
    Mh14Scenario.rejectedAwaitingRedelivery => build(
      status: ReturnRequestStatus.awaitingRedelivery,
      events: [submitted, approved, collected, received, rejected],
      decisionReason:
          'Sản phẩm đã qua sử dụng và có vết bẩn không có trong video mở kiện.',
      redelivery: const ReturnRedelivery(
        state: ReturnRedeliveryState.pending,
        assignment: _shipper,
      ),
      refreshedAt: _hn(6, 11, 0),
    ),
    Mh14Scenario.redeliveryFailed => build(
      status: ReturnRequestStatus.managerActionRequired,
      events: [
        submitted,
        approved,
        collected,
        received,
        rejected,
        e(ReturnTrackingEventKind.redeliveryFailed, _hn(7, 15, 30)),
      ],
      decisionReason:
          'Sản phẩm đã qua sử dụng và có vết bẩn không có trong video mở kiện.',
      redelivery: const ReturnRedelivery(
        state: ReturnRedeliveryState.failed,
        assignment: _shipper,
      ),
      refreshedAt: _hn(7, 16, 0),
    ),
  };
}

/// DEMO repository: same contract as the future Supabase adapter, no network.
class Mh14DemoTrackingRepository implements ReturnTrackingRepository {
  Mh14DemoTrackingRepository(this.scenario);

  final Mh14Scenario scenario;
  int _loads = 0;
  bool _answered = false;

  @override
  Future<ReturnTracking> load(String returnId) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    _loads++;
    if (scenario == Mh14Scenario.staleAfterError && _loads > 1) {
      throw const ReturnRequestFailure(ReturnRequestFailureCode.network);
    }
    return mh14Tracking(scenario, infoAnswered: _answered);
  }

  @override
  Future<void> submitAdditionalInfo({
    required String returnId,
    required String requestId,
    required String description,
    ReturnVideoFile? video,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    _answered = true;
  }
}
