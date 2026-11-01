import '../../../../core/utils/display_formatters.dart';
import '../../domain/models/return_tracking.dart';

enum ReturnStepState { done, current, upcoming, stopped }

/// Extra panel rendered under a timeline step.
enum ReturnStepDetail { none, pickup, redelivery, refundPending, refundDone }

class ReturnTimelineStep {
  const ReturnTimelineStep({
    required this.key,
    required this.title,
    required this.shortLabel,
    required this.state,
    this.description,
    this.occurredAt,
    this.detail = ReturnStepDetail.none,
    this.attention = false,
  });

  final String key;
  final String title;
  final String shortLabel;
  final ReturnStepState state;
  final String? description;

  /// Only completed steps carry a (recorded server) time.
  final DateTime? occurredAt;
  final ReturnStepDetail detail;

  /// Current step that needs the store to resolve an issue.
  final bool attention;
}

/// Builds the customer timeline from confirmed state + recorded events.
/// Planned steps never get a timestamp; nothing is invented.
List<ReturnTimelineStep> buildReturnTimeline(ReturnTracking t) {
  DateTime? at(ReturnTrackingEventKind kind) => t.eventOf(kind)?.occurredAt;
  final amount = formatVnd(t.refundAmountVnd);
  final status = t.status;

  final submitted = ReturnTimelineStep(
    key: 'submitted',
    title: 'Đã gửi yêu cầu',
    shortLabel: 'Gửi',
    state: ReturnStepState.done,
    description: 'Cửa hàng đã nhận mô tả và video của bạn.',
    occurredAt: at(ReturnTrackingEventKind.submitted) ?? t.submittedAt,
  );

  if (status == ReturnRequestStatus.initiallyRejected) {
    return [
      submitted,
      ReturnTimelineStep(
        key: 'review',
        title: 'Không duyệt lấy hàng',
        shortLabel: 'Duyệt',
        state: ReturnStepState.stopped,
        description: _join(
          t.decisionReason,
          'Hàng vẫn ở bạn, không có chuyến lấy hàng. Yêu cầu đã kết thúc.',
        ),
        occurredAt: at(ReturnTrackingEventKind.initiallyRejected),
      ),
    ];
  }

  // Index of the current stage on the main path:
  // 1 review, 2 pickup, 3 transit/inspection, 4 result.
  final rejected = _isRejectedBranch(t);
  final stage = switch (status) {
    ReturnRequestStatus.pendingReview => 1,
    ReturnRequestStatus.awaitingReturnPickup => 2,
    ReturnRequestStatus.returningToStore ||
    ReturnRequestStatus.underInspection => 3,
    ReturnRequestStatus.awaitingRefund ||
    ReturnRequestStatus.refunded ||
    ReturnRequestStatus.awaitingRedelivery ||
    ReturnRequestStatus.rejectedAfterInspection ||
    ReturnRequestStatus.redeliveryFailed => 4,
    ReturnRequestStatus.managerActionRequired => _attentionStage(t),
    ReturnRequestStatus.initiallyRejected => 1,
  };
  final attention =
      status == ReturnRequestStatus.managerActionRequired ||
      status == ReturnRequestStatus.redeliveryFailed;

  ReturnStepState stateOf(int index) => index < stage
      ? ReturnStepState.done
      : index == stage
      ? ReturnStepState.current
      : ReturnStepState.upcoming;

  final review = ReturnTimelineStep(
    key: 'review',
    title: stage > 1 ? 'Đã duyệt lấy hàng' : 'Chờ cửa hàng duyệt',
    shortLabel: 'Duyệt',
    state: stateOf(1),
    description: stage > 1
        ? 'Cửa hàng đồng ý lấy hàng để kiểm tra. Đây chưa phải xác nhận '
              'hoàn tiền.'
        : 'Cửa hàng đang xem video và mô tả của bạn.',
    occurredAt: stage > 1 ? at(ReturnTrackingEventKind.pickupApproved) : null,
    attention: attention && stage == 1,
  );

  final pickup = ReturnTimelineStep(
    key: 'pickup',
    title: stage > 2 ? 'Đã lấy hàng' : 'Lấy hàng tại nhà bạn',
    shortLabel: 'Lấy hàng',
    state: stateOf(2),
    description: stage > 2
        ? 'Người lấy hàng đã nhận hàng từ bạn.'
        : stage == 2
        ? (at(ReturnTrackingEventKind.pickupFailed) != null
              ? 'Lần lấy hàng trước chưa thành công. Cửa hàng sẽ hẹn lại.'
              : null)
        : 'Cửa hàng sẽ phân công người đến lấy hàng.',
    occurredAt: stage > 2 ? at(ReturnTrackingEventKind.collected) : null,
    detail: stage == 2 ? ReturnStepDetail.pickup : ReturnStepDetail.none,
    attention: attention && stage == 2,
  );

  final received = at(ReturnTrackingEventKind.receivedAtStore);
  final inspection = ReturnTimelineStep(
    key: 'inspection',
    title: switch (stage) {
      > 3 when rejected => 'Không chấp nhận hoàn tiền',
      > 3 => 'Kiểm tra đạt',
      3 when status == ReturnRequestStatus.returningToStore =>
        'Đang chuyển hàng về cửa hàng',
      3 => 'Cửa hàng đang kiểm tra',
      _ => 'Cửa hàng nhận và kiểm tra',
    },
    shortLabel: 'Kiểm tra',
    state: stage > 3 && rejected ? ReturnStepState.stopped : stateOf(3),
    description: switch (stage) {
      > 3 when rejected => _join(
        t.decisionReason,
        'Hàng không phù hợp điều kiện trả nên không được hoàn tiền.',
      ),
      > 3 => 'Hàng nhận lại phù hợp với yêu cầu.',
      3 when received != null =>
        'Cửa hàng đã nhận hàng lúc ${formatHanoiDateTime(received)} và đang '
            'đối chiếu số lượng, tình trạng với video.',
      _ => 'Nhận hàng không đồng nghĩa được hoàn tiền; kết quả có sau khi kiểm tra.',
    },
    occurredAt: stage > 3
        ? at(
            rejected
                ? ReturnTrackingEventKind.inspectionRejected
                : ReturnTrackingEventKind.inspectionAccepted,
          )
        : null,
    attention: attention && stage == 3,
  );

  final ReturnTimelineStep result;
  if (rejected) {
    final redelivery = t.redelivery;
    final completed =
        status == ReturnRequestStatus.rejectedAfterInspection ||
        redelivery?.state == ReturnRedeliveryState.completed;
    final failed =
        redelivery?.state == ReturnRedeliveryState.failed ||
        status == ReturnRequestStatus.redeliveryFailed;
    result = ReturnTimelineStep(
      key: 'result',
      title: completed ? 'Đã giao lại hàng cho bạn' : 'Giao lại hàng miễn phí',
      shortLabel: 'Giao lại',
      state: completed ? ReturnStepState.done : ReturnStepState.current,
      description: completed
          ? 'Yêu cầu đã kết thúc với kết quả không hoàn tiền.'
          : failed
          ? 'Lần giao lại chưa thành công. Cửa hàng sẽ liên hệ bạn để sắp '
                'xếp lại; yêu cầu chưa đóng.'
          : 'Cửa hàng chịu phí giao lại và không thu thêm tiền COD.',
      occurredAt: completed
          ? (redelivery?.completedAt ??
                at(ReturnTrackingEventKind.redeliveryCompleted))
          : null,
      detail: completed ? ReturnStepDetail.none : ReturnStepDetail.redelivery,
      attention: failed,
    );
  } else {
    final refund = t.refund;
    result = ReturnTimelineStep(
      key: 'result',
      title: refund != null
          ? 'Đã hoàn tiền'
          : stage == 4
          ? 'Chờ cửa hàng chuyển khoản'
          : 'Hoàn tiền',
      shortLabel: 'Hoàn tiền',
      state: refund != null ? ReturnStepState.done : stateOf(4),
      description: refund != null
          ? 'Cửa hàng đã chuyển ${formatVnd(refund.amountVnd)} và lưu bằng '
                'chứng chuyển khoản.'
          : stage == 4
          ? 'Cửa hàng sẽ chuyển $amount (tiền hàng và phí giao ban đầu) '
                'ngoài ứng dụng.'
          : 'Nếu kiểm tra đạt, cửa hàng hoàn $amount (tiền hàng và phí '
                'giao ban đầu).',
      occurredAt: refund?.refundedAt,
      detail: refund != null
          ? ReturnStepDetail.refundDone
          : stage == 4
          ? ReturnStepDetail.refundPending
          : ReturnStepDetail.none,
      attention: attention && stage == 4,
    );
  }

  return [submitted, review, pickup, inspection, result];
}

/// Short, customer-facing status label for the summary chip.
String returnTrackingStatusLabel(ReturnTracking t) => switch (t.status) {
  ReturnRequestStatus.pendingReview =>
    t.infoRequest?.isOpen == true ? 'Cần bổ sung' : 'Chờ duyệt',
  ReturnRequestStatus.initiallyRejected => 'Không được duyệt',
  ReturnRequestStatus.awaitingReturnPickup => 'Chờ lấy hàng',
  ReturnRequestStatus.returningToStore => 'Đang chuyển về',
  ReturnRequestStatus.underInspection =>
    t.infoRequest?.isOpen == true ? 'Cần bổ sung' : 'Đang kiểm tra',
  ReturnRequestStatus.awaitingRefund => 'Chờ hoàn tiền',
  ReturnRequestStatus.refunded => 'Đã hoàn tiền',
  ReturnRequestStatus.rejectedAfterInspection => 'Đã giao lại hàng',
  ReturnRequestStatus.awaitingRedelivery => 'Chờ giao lại',
  ReturnRequestStatus.redeliveryFailed ||
  ReturnRequestStatus.managerActionRequired => 'Cửa hàng đang xử lý',
};

bool _isRejectedBranch(ReturnTracking t) =>
    t.status == ReturnRequestStatus.awaitingRedelivery ||
    t.status == ReturnRequestStatus.rejectedAfterInspection ||
    t.status == ReturnRequestStatus.redeliveryFailed ||
    t.redelivery != null ||
    t.eventOf(ReturnTrackingEventKind.inspectionRejected) != null;

/// manager_action_required keeps the request open at whichever stage the
/// recorded events reached.
int _attentionStage(ReturnTracking t) {
  if (t.redelivery != null ||
      t.eventOf(ReturnTrackingEventKind.inspectionRejected) != null ||
      t.eventOf(ReturnTrackingEventKind.inspectionAccepted) != null) {
    return 4;
  }
  if (t.eventOf(ReturnTrackingEventKind.collected) != null) return 3;
  if (t.eventOf(ReturnTrackingEventKind.pickupApproved) != null) return 2;
  return 1;
}

String _join(String? first, String second) =>
    first == null || first.trim().isEmpty ? second : '${first.trim()} $second';
