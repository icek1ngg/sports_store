import '../../../../core/errors/wire_parsing.dart';
import '../../domain/models/return_request_context.dart';
import '../../domain/models/return_request_submission.dart';

/// Strict mapping of `get_return_request_context`. Throws
/// `UnsupportedDataException` on any missing/invalid field.
ReturnRequestContext returnRequestContextFromJson(Map<String, Object?> json) {
  final items = requiredList(json, 'items')
      .map((raw) {
        if (raw is! Map) throw const FormatException('Invalid return item');
        final item = Map<String, Object?>.from(raw);
        final quantity = requiredInt(item, 'quantity', min: 1);
        final unitPrice = requiredInt(item, 'unit_price_vnd', min: 0);
        if (requiredInt(item, 'line_total_vnd', min: 0) !=
            unitPrice * quantity) {
          throw const FormatException('Inconsistent line total');
        }
        return ReturnContextItem(
          orderItemId: requiredUuid(item, 'order_item_id'),
          productName: requiredString(item, 'product_name', nonBlank: true),
          variantLabel: requiredString(item, 'variant_label', nonBlank: true),
          quantity: quantity,
          unitPriceVnd: unitPrice,
          imageUrl: _httpsOrNull(nullableString(item, 'product_image_url')),
        );
      })
      .toList(growable: false);

  final active = nullableObject(json, 'active_return');
  return ReturnRequestContext(
    orderId: requiredUuid(json, 'order_id'),
    orderStatus: requiredString(json, 'order_status', nonBlank: true),
    deliveredAt: nullableUtcTimestamp(json, 'delivered_at'),
    items: items,
    deliveryFeeVnd: requiredInt(json, 'delivery_fee_vnd', min: 0),
    totalPaidVnd: requiredInt(json, 'total_paid_vnd', min: 0),
    serverNow: requiredUtcTimestamp(json, 'server_now'),
    returnDeadline: nullableUtcTimestamp(json, 'return_deadline'),
    canSubmitReturn: requiredBool(json, 'can_submit_return'),
    eligibility: ReturnEligibility.fromWire(
      nullableString(json, 'eligibility_reason'),
    ),
    activeReturnId: active == null
        ? null
        : requiredUuid(active, 'return_request_id'),
  );
}

String? _httpsOrNull(String? value) {
  final uri = value == null ? null : Uri.tryParse(value);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
      ? value
      : null;
}

/// Strict ACK mapping; the echo must match the command that was sent.
ReturnRequestReceipt returnRequestReceiptFromJson(
  Map<String, Object?> json, {
  required ReturnRequestCommand command,
}) {
  final orderId = requiredUuid(json, 'order_id');
  final requestId = requiredUuid(json, 'request_id');
  if (orderId != command.orderId || requestId != command.requestId) {
    throw const FormatException('Receipt does not match the command');
  }
  return ReturnRequestReceipt(
    returnRequestId: requiredUuid(json, 'return_request_id'),
    orderId: orderId,
    status: requiredString(json, 'status', nonBlank: true),
    submittedAt: requiredUtcTimestamp(json, 'submitted_at'),
    replayed: requiredBool(json, 'replayed'),
  );
}
