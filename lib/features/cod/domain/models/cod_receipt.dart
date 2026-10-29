import '../../../deliveries/domain/models/operational_failure.dart';

/// The only successful state returned by `confirm_cod_received`.
enum CodReceiptStatus {
  received('received');

  const CodReceiptStatus(this.value);

  final String value;

  static CodReceiptStatus fromValue(String value) {
    for (final status in values) {
      if (status.value == value) return status;
    }
    throw FormatException('Unknown COD receipt status: $value');
  }
}

/// The client-controlled, idempotent input for the manager receipt command.
///
/// The manager identity, COD holder, authoritative expected amount and all
/// timestamps are deliberately absent: the database derives them while
/// holding the order and COD locks.
final class CodReceiptCommand {
  const CodReceiptCommand({
    required this.orderId,
    required this.receivedAmountVnd,
    required this.requestId,
  });

  static final BigInt maxSafeInteger = BigInt.parse('9007199254740991');

  final String orderId;
  final int receivedAmountVnd;
  final String requestId;

  /// Returns a fresh RPC argument map after validating all client inputs.
  Map<String, dynamic> toRpcParams() {
    validate();
    return <String, dynamic>{
      'p_order_id': orderId,
      'p_received_amount_vnd': receivedAmountVnd,
      'p_request_id': requestId,
    };
  }

  /// The repository maps this deterministic validation failure to
  /// [OperationalFailureCode.invalidData].
  void validate() {
    if (!_uuidPattern.hasMatch(orderId)) {
      throw const FormatException('Invalid p_order_id: expected a UUID');
    }
    if (!_uuidPattern.hasMatch(requestId)) {
      throw const FormatException('Invalid p_request_id: expected a UUID');
    }
    final amount = BigInt.from(receivedAmountVnd);
    if (amount <= BigInt.zero || amount > maxSafeInteger) {
      throw const FormatException(
        'Invalid p_received_amount_vnd: expected a positive safe integer',
      );
    }
  }
}

/// Server-authoritative result of a successful COD receipt confirmation.
///
/// The result contains no client-supplied identity or timestamps. It is
/// accepted only after [CodReceiptDto] has checked each field against the
/// command and the manager identity captured by the access epoch.
final class CodReceipt {
  const CodReceipt({
    required this.orderId,
    required this.status,
    required this.receivedAmountVnd,
    required this.receivedBy,
    required this.receivedAt,
    required this.handedOverAt,
    required this.eventId,
    required this.notificationId,
  });

  final String orderId;
  final CodReceiptStatus status;
  final int receivedAmountVnd;
  final String receivedBy;
  final DateTime receivedAt;
  final DateTime handedOverAt;
  final String eventId;
  final String notificationId;

  String get statusValue => status.value;

  @override
  bool operator ==(Object other) {
    return other is CodReceipt &&
        orderId == other.orderId &&
        status == other.status &&
        receivedAmountVnd == other.receivedAmountVnd &&
        receivedBy == other.receivedBy &&
        receivedAt == other.receivedAt &&
        handedOverAt == other.handedOverAt &&
        eventId == other.eventId &&
        notificationId == other.notificationId;
  }

  @override
  int get hashCode => Object.hash(
    orderId,
    status,
    receivedAmountVnd,
    receivedBy,
    receivedAt,
    handedOverAt,
    eventId,
    notificationId,
  );
}

/// Business errors returned by the receipt transaction. These values are
/// intentionally a closed, non-PII mapping of server error markers.
enum CodReceiptFailureCode {
  amountMismatch,
  stateConflict,
  idempotencyConflict,
  corruptCodState,
}

/// The RPC returned, but its acknowledgement could not be verified. The write
/// may have committed: retain the original command and request ID for retry.
final class CodReceiptAcknowledgementFailure extends OperationalFailure {
  const CodReceiptAcknowledgementFailure()
    : super(OperationalFailureCode.invalidData);

  @override
  String get message =>
      'Chưa xác minh được phản hồi nhận tiền. Thử lại cùng yêu cầu để kiểm tra kết quả.';
}

/// A safe typed representation of a P06.3 business conflict.
final class CodReceiptFailure extends OperationalFailure {
  const CodReceiptFailure(
    this.receiptCode, {
    OperationalFailureCode operationalCode = OperationalFailureCode.invalidData,
  }) : super(operationalCode);

  final CodReceiptFailureCode receiptCode;

  @override
  String get message => switch (receiptCode) {
    CodReceiptFailureCode.amountMismatch =>
      'Số tiền không khớp khoản COD đầy đủ trên máy chủ. Hãy đọc lại dữ liệu.',
    CodReceiptFailureCode.stateConflict =>
      'Khoản COD đã thay đổi hoặc đã được nhận. Hãy đọc lại dữ liệu.',
    CodReceiptFailureCode.idempotencyConflict => 'Request ID đã được dùng với nội dung khác. Không gửi lại bằng nội dung mới.',
    CodReceiptFailureCode.corruptCodState =>
      'Thông tin khoản COD chưa nhất quán. Không thể xác nhận nhận tiền.',
  };

  @override
  String toString() => 'CodReceiptFailure(${receiptCode.name})';
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
