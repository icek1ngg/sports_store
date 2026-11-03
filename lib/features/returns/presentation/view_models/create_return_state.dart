import '../../domain/models/return_reason.dart';
import '../../domain/models/return_request_context.dart';

/// Maps the server context to the step-1 view data. Returns null when the
/// order has no delivery time yet (step 1 cannot be shown).
ReturnOrderOverview? returnOrderOverviewFromContext(ReturnRequestContext c) {
  final deliveredAt = c.deliveredAt;
  final deadline = c.returnDeadline;
  if (deliveredAt == null || deadline == null) return null;
  return ReturnOrderOverview(
    orderId: c.orderId,
    // Orders have no separate customer-facing code; show the full UUID.
    orderCode: c.orderId,
    deliveredAt: deliveredAt,
    returnDeadline: deadline,
    referenceTime: c.serverNow,
    deliveryFeeVnd: c.deliveryFeeVnd,
    canSubmitReturn: c.canSubmitReturn,
    lines: [
      for (final item in c.items)
        ReturnOrderLine(
          productName: item.productName,
          variantLabel: item.variantLabel,
          quantity: item.quantity,
          unitPriceVnd: item.unitPriceVnd,
          imageUrl: item.imageUrl,
        ),
    ],
  );
}

/// One delivered line shown on MH13. Values come from the order snapshot,
/// never from the live catalog. Amounts are integer VND.
class ReturnOrderLine {
  const ReturnOrderLine({
    required this.productName,
    required this.variantLabel,
    required this.quantity,
    required this.unitPriceVnd,
    this.imageUrl,
  }) : assert(quantity > 0),
       assert(unitPriceVnd >= 0);

  final String productName;
  final String variantLabel;
  final int quantity;
  final int unitPriceVnd;
  final String? imageUrl;

  int get lineTotalVnd => unitPriceVnd * quantity;
}

/// Read-only data MH13 step 1 renders. The page receives it as a parameter so
/// a later mapper can build it from the shared order/return contracts.
class ReturnOrderOverview {
  const ReturnOrderOverview({
    required this.orderId,
    required this.orderCode,
    required this.deliveredAt,
    required this.returnDeadline,
    required this.referenceTime,
    required this.lines,
    required this.deliveryFeeVnd,
    required this.canSubmitReturn,
  }) : assert(deliveryFeeVnd >= 0);

  /// Full order UUID used for routing/RPCs; not displayed.
  final String orderId;

  /// Customer-facing order code, e.g. `DH000128`.
  final String orderCode;

  /// Server timestamps (UTC). Displayed in Hanoi time.
  final DateTime deliveredAt;
  final DateTime returnDeadline;

  /// Server-provided "now" used for relative labels; avoids trusting the
  /// device clock for business decisions.
  final DateTime referenceTime;

  final List<ReturnOrderLine> lines;
  final int deliveryFeeVnd;

  /// Server eligibility flag (`ReturnSummary.canSubmitReturn`).
  final bool canSubmitReturn;

  int get merchandiseVnd =>
      lines.fold(0, (total, line) => total + line.lineTotalVnd);

  int get totalPaidVnd => merchandiseVnd + deliveryFeeVnd;

  Duration get timeRemaining => returnDeadline.difference(referenceTime);

  bool get isWithinDeadline =>
      !timeRemaining.isNegative && timeRemaining != Duration.zero;

  bool get isEligible => canSubmitReturn && isWithinDeadline;

  int get daysSinceDelivery {
    final days = referenceTime.difference(deliveredAt).inDays;
    return days < 0 ? 0 : days;
  }
}

class CreateReturnFormState {
  const CreateReturnFormState({this.reason});

  final ReturnReason? reason;
}
