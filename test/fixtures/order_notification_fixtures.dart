/// Contract fixtures distilled from Data/API §9. They use synthetic UUIDs and
/// never seed or contact a backend.
const fixtureOrderId = '10000000-0000-4000-8000-000000000001';
const fixtureCustomerId = '20000000-0000-4000-8000-000000000001';
const fixtureManagerId = '20000000-0000-4000-8000-000000000003';
const fixtureShipperId = '20000000-0000-4000-8000-000000000004';
const fixturePlacementRequestId = '30000000-0000-4000-8000-000000000009';
const fixtureMutationRequestId = '30000000-0000-4000-8000-000000000004';
const fixtureEventId = '40000000-0000-4000-8000-000000000002';
const fixtureOrderItemId = '60000000-0000-4000-8000-000000000001';
const fixtureProductId = '70000000-0000-4000-8000-000000000001';
const fixtureVariantId = '80000000-0000-4000-8000-000000000001';
const fixtureTaskId = '90000000-0000-4000-8000-000000000001';
const fixtureAttemptId = 'a0000000-0000-4000-8000-000000000001';
const fixtureReturnId = 'b0000000-0000-4000-8000-000000000001';
const fixtureNotificationId = '50000000-0000-4000-8000-000000000001';

Map<String, Object?> fixtureOrderJson({
  String status = 'pending_confirmation',
  String? confirmedAt,
  String? source,
  String? confirmedBy,
  String? deliveredAt,
  String? cancelReason,
}) {
  return {
    'id': fixtureOrderId,
    'customer_id': fixtureCustomerId,
    'request_id': fixturePlacementRequestId,
    'status': status,
    'recipient_name': 'Khách hàng minh họa',
    'recipient_phone': '0900000000',
    'address_detail': 'Địa chỉ minh họa Hà Nội; không đặt đơn thật',
    'latitude': 21.028,
    'longitude': 105.834,
    'subtotal_vnd': 3450000,
    'delivery_fee_vnd': 30000,
    'total_cod_vnd': 3480000,
    'delivery_attempt_count': 0,
    'placed_at': '2026-10-08T03:32:00Z',
    'confirmed_at': confirmedAt,
    'source': source,
    'confirmed_by': confirmedBy,
    'delivered_at': deliveredAt,
    'cancel_reason': cancelReason,
    'created_at': '2026-10-08T03:32:00Z',
    'updated_at': '2026-10-08T03:40:00Z',
  };
}

Map<String, Object?> fixtureOrderItemJson() => {
  'id': fixtureOrderItemId,
  'order_id': fixtureOrderId,
  'product_id': fixtureProductId,
  'variant_id': fixtureVariantId,
  'product_name': 'Sản phẩm minh họa',
  'variant_label': 'Biến thể minh họa',
  'attributes': <String, Object?>{},
  'unit_price_vnd': 3450000,
  'quantity': 1,
  'line_total_vnd': 3450000,
  'created_at': '2026-10-08T03:32:00Z',
};

Map<String, Object?> fixtureCapabilitiesJson({bool canCancelCustomer = true}) =>
    {
      'can_cancel_customer': canCancelCustomer,
      'can_confirm': false,
      'can_reject': false,
      'can_cancel_exceptional': false,
      'can_assign': false,
      'can_reassign': false,
      'can_arrange_second_attempt': false,
      'can_request_early_return': false,
      'can_receive_undelivered': false,
      'can_open_return_creation': false,
    };

Map<String, Object?> fixtureOrderSummaryJson() => {
  'order': fixtureOrderJson(),
  'customer_display_name': null,
  'item_preview': [fixtureOrderItemJson()],
  'item_line_count': 1,
  'item_quantity_total': 1,
  'delivery_summary': null,
  'cod_summary': null,
  'return_summary': null,
  'warnings': <Object?>[],
  'capabilities': fixtureCapabilitiesJson(),
};

Map<String, Object?> fixtureOrderListJson() => {
  'items': [fixtureOrderSummaryJson()],
  'next_cursor': null,
  'total_count': 1,
  'status_counts': {
    'pending_confirmation': 1,
    'preparing': 0,
    'awaiting_pickup': 0,
    'delivering': 0,
    'awaiting_redelivery': 0,
    'awaiting_store_return': 0,
    'delivered': 0,
    'cancelled': 0,
    'rejected': 0,
    'undeliverable_returned': 0,
  },
  'as_of': '2026-10-08T03:33:00Z',
};

Map<String, Object?> fixtureTimelineEntryJson({
  String eventId = fixtureEventId,
  String sourceEntityType = 'order',
  String sourceEntityId = fixtureOrderId,
  String eventKind = 'order_placed',
  String? fromState,
  String? toState = 'pending_confirmation',
  String? actorId,
  String? actorLabel,
  String actorSource = 'unknown',
  String occurredAt = '2026-10-08T03:32:00Z',
  String? reason,
  String source = 'actual_event',
}) => {
  'event_id': eventId,
  'source_entity_type': sourceEntityType,
  'source_entity_id': sourceEntityId,
  'event_kind': eventKind,
  'from_state': fromState,
  'to_state': toState,
  'actor_id': actorId,
  'actor_label': actorLabel,
  'actor_source': actorSource,
  'occurred_at': occurredAt,
  'reason': reason,
  'source': source,
};

Map<String, Object?> fixtureOrderDetailsJson({
  List<Object?>? timeline,
  Object? buyer,
}) => {
  'order': fixtureOrderJson(),
  'items': [fixtureOrderItemJson()],
  'buyer': buyer,
  'delivery_summary': null,
  'cod_summary': null,
  'return_summaries': <Object?>[],
  'timeline': timeline ?? <Object?>[],
  'history_complete': true,
  'capabilities': fixtureCapabilitiesJson(),
  'as_of': '2026-10-08T03:33:00Z',
};

Map<String, Object?> fixtureMutationReceiptJson({
  String operation = 'confirm',
  String status = 'preparing',
  bool replayed = false,
}) => {
  'operation': operation,
  'request_id': fixtureMutationRequestId,
  'event_id': fixtureEventId,
  'order': fixtureOrderJson(status: status),
  'committed_at': '2026-10-08T03:40:00Z',
  'replayed': replayed,
  'current_order': null,
};

Map<String, Object?> fixtureNotificationJson({
  Object? readAt,
  String subjectType = 'order',
}) => {
  'id': fixtureNotificationId,
  'recipient_id': fixtureCustomerId,
  'event_id': fixtureEventId,
  'subject_type': subjectType,
  'subject_id': fixtureOrderId,
  'title': 'Đơn hàng đã được từ chối',
  'body': 'Mở đơn để xem lý do và trạng thái hiện tại.',
  'read_at': readAt,
  'created_at': '2026-10-08T03:40:00Z',
};
