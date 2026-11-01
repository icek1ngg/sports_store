import '../../../../core/errors/wire_parsing.dart';
import '../../domain/models/return_reason.dart';
import '../../domain/models/return_tracking.dart';

const _rejectedBranch = {
  ReturnRequestStatus.awaitingRedelivery,
  ReturnRequestStatus.rejectedAfterInspection,
  ReturnRequestStatus.redeliveryFailed,
};

/// Strict mapping of `get_my_return_request`. Timeline events are derived
/// only from server timestamps present in the response.
ReturnTracking returnTrackingFromJson(Map<String, Object?> json) {
  final returnId = requiredUuid(json, 'return_id');
  final orderId = requiredUuid(json, 'order_id');
  final status = ReturnRequestStatus.parse(requiredField(json, 'status'));
  final submittedAt = requiredUtcTimestamp(json, 'submitted_at');
  final decisionAt = nullableUtcTimestamp(json, 'decision_at');
  final receivedAt = nullableUtcTimestamp(json, 'received_at_store');
  final inspectedAt = nullableUtcTimestamp(json, 'inspected_at');

  final pickupJson = nullableObject(json, 'pickup');
  final redeliveryJson = nullableObject(json, 'redelivery');
  final refundJson = nullableObject(json, 'refund');

  final pickupStatus = pickupJson == null
      ? null
      : requiredString(pickupJson, 'status', nonBlank: true);
  final redeliveryStatus = redeliveryJson == null
      ? null
      : requiredString(redeliveryJson, 'status', nonBlank: true);

  final rejected = _rejectedBranch.contains(status) || redeliveryJson != null;

  final events = <ReturnTrackingEvent>[
    ReturnTrackingEvent(
      kind: ReturnTrackingEventKind.submitted,
      occurredAt: submittedAt,
    ),
  ];
  void add(ReturnTrackingEventKind kind, DateTime? at) {
    if (at != null) events.add(ReturnTrackingEvent(kind: kind, occurredAt: at));
  }

  if (status == ReturnRequestStatus.initiallyRejected) {
    add(ReturnTrackingEventKind.initiallyRejected, decisionAt);
  } else if (status != ReturnRequestStatus.pendingReview) {
    add(ReturnTrackingEventKind.pickupApproved, decisionAt);
  }
  if (pickupJson != null) {
    add(
      ReturnTrackingEventKind.pickupAssigned,
      nullableUtcTimestamp(pickupJson, 'assigned_at'),
    );
    add(
      ReturnTrackingEventKind.collected,
      nullableUtcTimestamp(pickupJson, 'collected_at'),
    );
    if (pickupStatus == 'failed') {
      add(
        ReturnTrackingEventKind.pickupFailed,
        nullableUtcTimestamp(pickupJson, 'completed_at'),
      );
    }
  }
  add(ReturnTrackingEventKind.receivedAtStore, receivedAt);
  add(
    rejected
        ? ReturnTrackingEventKind.inspectionRejected
        : ReturnTrackingEventKind.inspectionAccepted,
    inspectedAt,
  );

  ReturnRefundRecord? refund;
  if (refundJson != null) {
    refund = ReturnRefundRecord(
      amountVnd: requiredInt(refundJson, 'amount_vnd', min: 1),
      refundedAt: requiredUtcTimestamp(refundJson, 'refunded_at'),
      hasTransferEvidence: requiredBool(refundJson, 'has_transfer_evidence'),
    );
    add(ReturnTrackingEventKind.refunded, refund.refundedAt);
  }

  ReturnRedelivery? redelivery;
  if (redeliveryJson != null) {
    final completedAt = nullableUtcTimestamp(redeliveryJson, 'completed_at');
    final state = switch (redeliveryStatus) {
      'delivered' => ReturnRedeliveryState.completed,
      'failed' || 'manager_action_required' => ReturnRedeliveryState.failed,
      _ => ReturnRedeliveryState.pending,
    };
    redelivery = ReturnRedelivery(
      state: state,
      assignment: _person(redeliveryJson),
      completedAt: state == ReturnRedeliveryState.completed
          ? completedAt
          : null,
    );
    if (state == ReturnRedeliveryState.completed) {
      add(ReturnTrackingEventKind.redeliveryCompleted, completedAt);
    } else if (state == ReturnRedeliveryState.failed) {
      add(ReturnTrackingEventKind.redeliveryFailed, completedAt);
    }
  }

  events.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

  final items = requiredList(json, 'items')
      .map((raw) {
        if (raw is! Map) throw const FormatException('Invalid return item');
        final item = Map<String, Object?>.from(raw);
        return ReturnTrackingItem(
          name: requiredString(item, 'name', nonBlank: true),
          variantLabel: nullableString(item, 'variant_label'),
          quantity: requiredInt(item, 'quantity', min: 1),
        );
      })
      .toList(growable: false);

  return ReturnTracking(
    returnId: returnId,
    // No customer-facing codes exist in the schema: show full UUIDs.
    returnCode: returnId,
    orderId: orderId,
    orderCode: orderId,
    status: status,
    reason: ReturnReason.fromWire(requiredString(json, 'reason')),
    submittedAt: submittedAt,
    refreshedAt: requiredUtcTimestamp(json, 'server_now'),
    events: List.unmodifiable(events),
    items: items,
    merchandiseVnd: requiredInt(json, 'merchandise_vnd', min: 0),
    deliveryFeeVnd: requiredInt(json, 'delivery_fee_vnd', min: 0),
    pickupAddress: requiredString(json, 'pickup_address', nonBlank: true),
    pickup: pickupJson == null ? null : _person(pickupJson),
    decisionReason: nullableString(json, 'decision_reason'),
    // The schema has no "more information" request yet (needs MH15).
    infoRequest: null,
    refund: refund,
    refundBankName: nullableString(json, 'refund_bank_name'),
    refundAccountMasked: nullableString(json, 'refund_account_masked'),
    redelivery: redelivery,
  );
}

/// Only the person on an active task is returned by the server; no schedule
/// exists in the schema, so none is ever set here.
ReturnPickupAssignment? _person(Map<String, Object?> task) {
  final person = nullableObject(task, 'person');
  if (person == null) return null;
  return ReturnPickupAssignment(
    shipperName: requiredString(person, 'name', nonBlank: true),
    shipperPhone: nullableString(person, 'phone'),
  );
}
