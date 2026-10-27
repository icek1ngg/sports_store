const taskId = '11111111-1111-4111-8111-111111111111';
const orderId = '22222222-2222-4222-8222-222222222222';
const returnRequestId = '33333333-3333-4333-8333-333333333333';
const itemId = '44444444-4444-4444-8444-444444444444';

Map<String, dynamic> currentTaskDto({
  String kind = 'outbound',
  String status = 'assigned',
  String? task = taskId,
  String? order = orderId,
  String? returnRequest,
  Object amount = 550000,
  String itemSource = 'order_snapshot',
  Object? acceptedAt,
  Object? startedAt,
}) {
  return {
    'task_id': task,
    'kind': kind,
    'status': status,
    'attempt_number': 1,
    'snapshot_scope': 'current',
    'order_id': order,
    'return_request_id': returnRequest,
    'amount_to_collect_vnd': amount,
    'destination_name': 'Nguyễn Văn A',
    'destination_phone': '0900000000',
    'destination_address': 'Hà Nội',
    'destination_latitude': '21.028511',
    'destination_longitude': 105.804817,
    'assigned_at': '2026-10-23T10:00:00+07:00',
    'accepted_at': acceptedAt,
    'started_at': startedAt,
    'completed_at': null,
    'item_source': itemSource,
  };
}

Map<String, dynamic> maskedTaskDto({
  String status = 'failed',
  String scope = 'restricted',
  String kind = 'outbound',
  String itemSource = 'unavailable',
}) {
  return {
    'task_id': taskId,
    'kind': kind,
    'status': status,
    'attempt_number': 1,
    'snapshot_scope': scope,
    'order_id': null,
    'return_request_id': null,
    'amount_to_collect_vnd': null,
    'destination_name': null,
    'destination_phone': null,
    'destination_address': null,
    'destination_latitude': null,
    'destination_longitude': null,
    'assigned_at': null,
    'accepted_at': null,
    'started_at': null,
    'completed_at': '2026-10-23T03:00:00Z',
    'item_source': itemSource,
  };
}

Map<String, dynamic> outboundItemDto({
  Object quantity = 2,
  Object? quantityCollected,
  Object? unitPrice = 260000,
  Object? lineTotal = 520000,
  Object? attributes,
}) {
  return {
    'item_id': itemId,
    'item_source': 'order_snapshot',
    'product_name': 'Bóng đá',
    'variant_label': 'Size 5',
    'attributes':
        attributes ??
        {
          'color': 'white',
          'options': <Object?>[
            'official',
            <String, Object?>{'weight': 420},
          ],
        },
    'quantity': quantity,
    'quantity_collected': quantityCollected,
    'unit_price_vnd': unitPrice,
    'line_total_vnd': lineTotal,
  };
}

Map<String, dynamic> returnItemDto({
  Object quantity = 2,
  Object? quantityCollected = 1,
}) {
  return {
    'item_id': itemId,
    'item_source': 'return_plan',
    'product_name': 'Bóng đá bị lỗi',
    'variant_label': null,
    'attributes': null,
    'quantity': quantity,
    'quantity_collected': quantityCollected,
    'unit_price_vnd': null,
    'line_total_vnd': null,
  };
}
