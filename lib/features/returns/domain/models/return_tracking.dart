import '../../../orders/domain/models/return_request_status.dart';
import 'return_reason.dart';

export '../../../orders/domain/models/return_request_status.dart'
    show ReturnRequestStatus;

/// Customer-visible snapshot of one owned return request (MH14).
///
/// Every timestamp is a server instant. Nothing here is computed on the
/// device: planned/future stages simply have no timestamp.
class ReturnTracking {
  const ReturnTracking({
    required this.returnId,
    required this.returnCode,
    required this.orderId,
    required this.orderCode,
    required this.status,
    required this.reason,
    required this.submittedAt,
    required this.refreshedAt,
    required this.events,
    required this.items,
    required this.merchandiseVnd,
    required this.deliveryFeeVnd,
    required this.pickupAddress,
    this.pickup,
    this.decisionReason,
    this.infoRequest,
    this.refund,
    this.refundBankName,
    this.refundAccountMasked,
    this.redelivery,
  });

  final String returnId;

  /// Customer-facing codes. Real data has none, so the full UUIDs are used.
  final String returnCode;
  final String orderId;
  final String orderCode;

  final ReturnRequestStatus status;
  final ReturnReason reason;
  final DateTime submittedAt;

  /// Server time of this snapshot ("Cập nhật …").
  final DateTime refreshedAt;

  /// Recorded server events, oldest first.
  final List<ReturnTrackingEvent> events;

  /// Approved goods to collect (actually received items only).
  final List<ReturnTrackingItem> items;

  final int merchandiseVnd;
  final int deliveryFeeVnd;

  /// Saved collection address (the order's delivery address snapshot).
  final String pickupAddress;

  /// Null until the manager assigns someone to collect the goods.
  final ReturnPickupAssignment? pickup;

  /// Manager's reason for an initial rejection or inspection decision.
  final String? decisionReason;

  /// Open or answered "more information" request from the manager.
  final ReturnInfoRequest? infoRequest;

  /// Present only after the manager recorded the external transfer.
  final ReturnRefundRecord? refund;

  final String? refundBankName;
  final String? refundAccountMasked;

  /// Free redelivery after rejection at inspection.
  final ReturnRedelivery? redelivery;

  int get refundAmountVnd => merchandiseVnd + deliveryFeeVnd;

  ReturnTrackingEvent? eventOf(ReturnTrackingEventKind kind) {
    for (final event in events.reversed) {
      if (event.kind == kind) return event;
    }
    return null;
  }
}

enum ReturnTrackingEventKind {
  submitted,
  initiallyRejected,
  pickupApproved,
  pickupAssigned,
  pickupFailed,
  collected,
  receivedAtStore,
  inspectionAccepted,
  inspectionRejected,
  infoRequested,
  infoProvided,
  refunded,
  redeliveryCompleted,
  redeliveryFailed,
}

class ReturnTrackingEvent {
  const ReturnTrackingEvent({
    required this.kind,
    required this.occurredAt,
    this.note,
  });

  final ReturnTrackingEventKind kind;
  final DateTime occurredAt;
  final String? note;
}

class ReturnTrackingItem {
  const ReturnTrackingItem({
    required this.name,
    required this.variantLabel,
    required this.quantity,
  });

  final String name;
  final String? variantLabel;
  final int quantity;
}

/// Only the person assigned to this customer's own pickup. Schedule is shown
/// only when the manager recorded one; nothing is inferred.
class ReturnPickupAssignment {
  const ReturnPickupAssignment({
    required this.shipperName,
    this.shipperPhone,
    this.scheduledAt,
  });

  final String shipperName;
  final String? shipperPhone;
  final DateTime? scheduledAt;
}

class ReturnInfoRequest {
  const ReturnInfoRequest({
    required this.message,
    required this.requestedAt,
    this.respondedAt,
  });

  final String message;
  final DateTime requestedAt;
  final DateTime? respondedAt;

  bool get isOpen => respondedAt == null;
}

class ReturnRefundRecord {
  const ReturnRefundRecord({
    required this.amountVnd,
    required this.refundedAt,
    required this.hasTransferEvidence,
  });

  final int amountVnd;
  final DateTime refundedAt;
  final bool hasTransferEvidence;
}

enum ReturnRedeliveryState { pending, failed, completed }

class ReturnRedelivery {
  const ReturnRedelivery({
    required this.state,
    this.assignment,
    this.completedAt,
  });

  final ReturnRedeliveryState state;
  final ReturnPickupAssignment? assignment;
  final DateTime? completedAt;
}
