/// Server-computed MH13 read model (`get_return_request_context`).
///
/// All timestamps are server instants (UTC). `serverNow` is the server clock
/// used for the deadline label; the final 7-day check happens again inside
/// `submit_return_request` at submission time.
class ReturnRequestContext {
  const ReturnRequestContext({
    required this.orderId,
    required this.orderStatus,
    required this.deliveredAt,
    required this.items,
    required this.deliveryFeeVnd,
    required this.totalPaidVnd,
    required this.serverNow,
    required this.returnDeadline,
    required this.canSubmitReturn,
    required this.eligibility,
    this.activeReturnId,
  });

  final String orderId;
  final String orderStatus;
  final DateTime? deliveredAt;
  final List<ReturnContextItem> items;
  final int deliveryFeeVnd;
  final int totalPaidVnd;
  final DateTime serverNow;
  final DateTime? returnDeadline;
  final bool canSubmitReturn;
  final ReturnEligibility eligibility;
  final String? activeReturnId;
}

class ReturnContextItem {
  const ReturnContextItem({
    required this.orderItemId,
    required this.productName,
    required this.variantLabel,
    required this.quantity,
    required this.unitPriceVnd,
    this.imageUrl,
  });

  final String orderItemId;
  final String productName;
  final String variantLabel;
  final int quantity;
  final int unitPriceVnd;

  /// HTTPS image snapshotted when the order was placed, if any.
  final String? imageUrl;
}

enum ReturnEligibility {
  eligible(null),
  notDelivered('not_delivered'),
  activeReturnExists('active_return_exists'),
  returnWindowExpired('return_window_expired');

  const ReturnEligibility(this.wireValue);

  final String? wireValue;

  static ReturnEligibility fromWire(String? value) {
    for (final item in values) {
      if (item.wireValue == value) return item;
    }
    throw FormatException('Unknown eligibility reason: $value');
  }
}
