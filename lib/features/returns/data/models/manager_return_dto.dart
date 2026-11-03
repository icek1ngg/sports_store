import '../../../../core/errors/wire_parsing.dart';
import '../../domain/models/manager_return.dart';
import '../../domain/models/return_reason.dart';

Map<String, Object?> _object(Object? raw, String path) {
  if (raw is! Map) {
    throw FormatException('Expected object at $path');
  }
  return Map<String, Object?>.from(raw);
}

List<Map<String, Object?>> _objects(Map<String, Object?> json, String key) => [
  for (final raw in requiredList(json, key)) _object(raw, key),
];

ReturnReason _reason(Map<String, Object?> json) =>
    ReturnReason.fromWire(requiredString(json, 'reason', nonBlank: true));

/// Strict mapping of `list_manager_return_requests`.
ManagerReturnList managerReturnListFromJson(Map<String, Object?> json) {
  final counts = <ReturnRequestStatus, int>{};
  final rawCounts = requiredObject(json, 'counts');
  for (final entry in rawCounts.entries) {
    final status = ReturnRequestStatus.parse(entry.key, path: 'counts');
    final value = entry.value;
    if (value is! int || value < 0) {
      throw FormatException('Invalid count for ${entry.key}');
    }
    counts[status] = value;
  }
  return ManagerReturnList(
    items: [
      for (final row in _objects(json, 'items'))
        ManagerReturnSummary(
          returnId: requiredUuid(row, 'return_id'),
          orderId: requiredUuid(row, 'order_id'),
          status: ReturnRequestStatus.parse(requiredField(row, 'status')),
          reason: _reason(row),
          submittedAt: requiredUtcTimestamp(row, 'submitted_at'),
          customerName: requiredString(row, 'customer_name', nonBlank: true),
          totalVnd: requiredInt(row, 'total_vnd', min: 0),
          lineCount: requiredInt(row, 'line_count', min: 0),
          firstItemName: nullableString(row, 'first_item_name'),
        ),
    ],
    counts: Map.unmodifiable(counts),
    serverNow: requiredUtcTimestamp(json, 'server_now'),
  );
}

ManagerReturnContact _contact(
  Map<String, Object?> json, {
  bool withAddress = false,
}) => ManagerReturnContact(
  name: requiredString(json, 'name', nonBlank: true),
  phone: nullableString(json, 'phone'),
  address: withAddress ? nullableString(json, 'address') : null,
);

/// Phase-2 keys are optional so a server that only has phase 1 still maps;
/// when present they are parsed strictly.
bool _has(Map<String, Object?> json, String key) => json.containsKey(key);

List<String> _paths(Map<String, Object?> json, String key) => [
  for (final raw in requiredList(json, key))
    if (raw is String && raw.trim().isNotEmpty)
      raw
    else
      throw FormatException('Invalid path in $key'),
];

ManagerReturnPickupTask _task(Map<String, Object?> json) =>
    ManagerReturnPickupTask(
      taskId: requiredUuid(json, 'task_id'),
      status: requiredString(json, 'status', nonBlank: true),
      shipperId: nullableUuid(json, 'shipper_id'),
      shipperName: requiredString(json, 'shipper_name', nonBlank: true),
      shipperPhone: nullableString(json, 'shipper_phone'),
      assignedAt: nullableUtcTimestamp(json, 'assigned_at'),
      completedAt: nullableUtcTimestamp(json, 'completed_at'),
      failureReason: nullableString(json, 'failure_reason'),
      handoverReported: _has(json, 'handover_reported')
          ? requiredBool(json, 'handover_reported')
          : false,
    );

/// Strict mapping of `get_manager_return_request`.
ManagerReturnDetail managerReturnDetailFromJson(Map<String, Object?> json) {
  final bankJson = nullableObject(json, 'bank');
  final taskJson = nullableObject(json, 'pickup_task');
  final videoPaths = [
    for (final raw in requiredList(json, 'video_paths'))
      if (raw is String && raw.trim().isNotEmpty)
        raw
      else
        throw const FormatException('Invalid video path'),
  ];
  if (videoPaths.isEmpty) throw const FormatException('Missing return video');

  return ManagerReturnDetail(
    returnId: requiredUuid(json, 'return_id'),
    orderId: requiredUuid(json, 'order_id'),
    status: ReturnRequestStatus.parse(requiredField(json, 'status')),
    reason: _reason(json),
    description: requiredString(json, 'description', nonBlank: true),
    submittedAt: requiredUtcTimestamp(json, 'submitted_at'),
    deliveredAt: nullableUtcTimestamp(json, 'delivered_at'),
    decisionReason: nullableString(json, 'decision_reason'),
    decisionAt: nullableUtcTimestamp(json, 'decision_at'),
    closedAt: nullableUtcTimestamp(json, 'closed_at'),
    customer: _contact(requiredObject(json, 'customer')),
    recipient: _contact(requiredObject(json, 'recipient'), withAddress: true),
    subtotalVnd: requiredInt(json, 'subtotal_vnd', min: 0),
    deliveryFeeVnd: requiredInt(json, 'delivery_fee_vnd', min: 0),
    totalVnd: requiredInt(json, 'total_vnd', min: 0),
    orderItems: [
      for (final row in _objects(json, 'order_items'))
        ManagerReturnOrderItem(
          orderItemId: requiredUuid(row, 'order_item_id'),
          productName: requiredString(row, 'product_name', nonBlank: true),
          variantLabel: nullableString(row, 'variant_label'),
          quantity: requiredInt(row, 'quantity', min: 1),
          unitPriceVnd: requiredInt(row, 'unit_price_vnd', min: 0),
          lineTotalVnd: requiredInt(row, 'line_total_vnd', min: 0),
          imageUrl: nullableString(row, 'image_url'),
        ),
    ],
    returnItems: [
      for (final row in _objects(json, 'return_items'))
        ManagerReturnItem(
          returnItemId: requiredUuid(row, 'return_item_id'),
          orderItemId: nullableUuid(row, 'order_item_id'),
          name: requiredString(row, 'name', nonBlank: true),
          quantityToCollect: requiredInt(row, 'quantity_to_collect', min: 1),
          quantityCollected: requiredInt(row, 'quantity_collected', min: 0),
          sellableQuantity: requiredInt(row, 'sellable_quantity', min: 0),
          damagedQuantity: requiredInt(row, 'damaged_quantity', min: 0),
        ),
    ],
    videoPaths: List.unmodifiable(videoPaths),
    bank: bankJson == null
        ? null
        : ManagerReturnBank(
            bankName: requiredString(bankJson, 'bank_name', nonBlank: true),
            accountNumber: requiredString(
              bankJson,
              'account_number',
              nonBlank: true,
            ),
            accountHolder: requiredString(
              bankJson,
              'account_holder',
              nonBlank: true,
            ),
          ),
    pickupTask: taskJson == null ? null : _task(taskJson),
    redeliveryTask: _has(json, 'redelivery_task')
        ? switch (nullableObject(json, 'redelivery_task')) {
            final t? => _task(t),
            null => null,
          }
        : null,
    inspectionStartedAt: _has(json, 'inspection_started_at')
        ? nullableUtcTimestamp(json, 'inspection_started_at')
        : null,
    inspectedAt: _has(json, 'inspected_at')
        ? nullableUtcTimestamp(json, 'inspected_at')
        : null,
    inspectionEvidencePaths: _has(json, 'inspection_evidence_paths')
        ? List.unmodifiable(_paths(json, 'inspection_evidence_paths'))
        : const [],
    refund: _has(json, 'refund')
        ? switch (nullableObject(json, 'refund')) {
            final r? => ManagerRefundRecord(
              amountVnd: requiredInt(r, 'amount_vnd', min: 1),
              refundedAt: requiredUtcTimestamp(r, 'refunded_at'),
              evidencePath: requiredString(r, 'evidence_path', nonBlank: true),
            ),
            null => null,
          }
        : null,
    infoRequests: _has(json, 'info_requests')
        ? List.unmodifiable([
            for (final row in _objects(json, 'info_requests'))
              ManagerInfoRequest(
                message: requiredString(row, 'message', nonBlank: true),
                requestedAt: requiredUtcTimestamp(row, 'requested_at'),
                responseText: nullableString(row, 'response_text'),
                responseVideoPath: nullableString(row, 'response_video_path'),
                respondedAt: nullableUtcTimestamp(row, 'responded_at'),
              ),
          ])
        : const [],
    shippers: [
      for (final row in _objects(json, 'shippers'))
        ManagerShipperOption(
          shipperId: requiredUuid(row, 'shipper_id'),
          name: requiredString(row, 'name', nonBlank: true),
          phone: nullableString(row, 'phone'),
        ),
    ],
    serverNow: requiredUtcTimestamp(json, 'server_now'),
  );
}

/// The command ACKs only need to confirm the server reached the expected
/// state for the same request; the screen reloads the detail afterwards.
void requireReturnAck(
  Object? raw, {
  required String operation,
  required String returnId,
  required String requestId,
  required String status,
}) {
  final json = _object(raw, 'ack');
  if (requiredString(json, 'operation') != operation ||
      requiredUuid(json, 'return_request_id') != returnId ||
      requiredUuid(json, 'request_id') != requestId ||
      requiredString(json, 'return_status') != status) {
    throw const FormatException('Unexpected return management ACK');
  }
}
