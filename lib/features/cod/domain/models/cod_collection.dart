/// The lifecycle state of an order's cash-on-delivery obligation.
enum CodStatus {
  uncollected('uncollected'),
  collected('collected'),
  received('received');

  const CodStatus(this.value);

  /// The value persisted by Supabase.
  final String value;

  static CodStatus fromValue(String value) {
    for (final status in values) {
      if (status.value == value) {
        return status;
      }
    }
    throw FormatException('Unknown COD status: $value');
  }
}

/// A read-only snapshot of an order's COD collection record.
class CodCollection {
  const CodCollection({
    required this.orderId,
    this.orderCode,
    this.orderCodeSource,
    this.shipperId,
    required this.status,
    required this.expectedAmountVnd,
    required this.collectedAmountVnd,
    required this.receivedAmountVnd,
    this.collectedBy,
    this.receivedBy,
    this.collectedAt,
    this.handedOverAt,
    this.receivedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String orderId;

  /// Display/reference code returned by the approved projection. The current
  /// schema has no separate short order code, so the server may expose the
  /// UUID text with source `order_uuid`.
  final String? orderCode;
  final String? orderCodeSource;
  final String? shipperId;
  final CodStatus status;
  final int expectedAmountVnd;
  final int collectedAmountVnd;
  final int receivedAmountVnd;
  final String? collectedBy;
  final String? receivedBy;
  final DateTime? collectedAt;
  final DateTime? handedOverAt;
  final DateTime? receivedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The amount collected by the shipper that the store has not received yet.
  ///
  /// An uncollected order has no COD amount owed by the shipper, and a
  /// received order has no outstanding amount. Database constraints make the
  /// amount for [CodStatus.collected] equal to the expected order amount.
  int get outstandingAmountVnd => status == CodStatus.collected
      ? collectedAmountVnd - receivedAmountVnd
      : 0;

  @override
  bool operator ==(Object other) {
    return other is CodCollection &&
        orderId == other.orderId &&
        orderCode == other.orderCode &&
        orderCodeSource == other.orderCodeSource &&
        shipperId == other.shipperId &&
        status == other.status &&
        expectedAmountVnd == other.expectedAmountVnd &&
        collectedAmountVnd == other.collectedAmountVnd &&
        receivedAmountVnd == other.receivedAmountVnd &&
        collectedBy == other.collectedBy &&
        receivedBy == other.receivedBy &&
        collectedAt == other.collectedAt &&
        handedOverAt == other.handedOverAt &&
        receivedAt == other.receivedAt &&
        createdAt == other.createdAt &&
        updatedAt == other.updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    orderId,
    orderCode,
    orderCodeSource,
    shipperId,
    status,
    expectedAmountVnd,
    collectedAmountVnd,
    receivedAmountVnd,
    collectedBy,
    receivedBy,
    collectedAt,
    handedOverAt,
    receivedAt,
    createdAt,
    updatedAt,
  );
}
