import 'model_validators.dart';
import 'order_status.dart';

class StableOrderCommand {
  StableOrderCommand({
    required String orderId,
    required String requestId,
    required this.operation,
    String? reason,
  }) : orderId = validateUuidValue(orderId, field: 'orderId'),
       requestId = validateUuidValue(requestId, field: 'requestId'),
       reason = _normalizeReason(operation, reason) {
    if (!operation.isClientOperation) {
      throw InvalidDomainArgumentException(
        'auto_confirm belongs to the server job.',
      );
    }
  }

  final String orderId;
  final String requestId;
  final OrderOperation operation;
  final String? reason;

  static String? _normalizeReason(OrderOperation operation, String? value) {
    final normalized = value == null
        ? null
        : contractTrim(value.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));
    final requiresReason =
        operation == OrderOperation.reject ||
        operation == OrderOperation.managerCancel;
    if (requiresReason && (normalized == null || normalized.isEmpty)) {
      throw InvalidDomainArgumentException(
        '${operation.wireValue} requires a non-blank reason.',
      );
    }
    if (!requiresReason && normalized != null && normalized.isNotEmpty) {
      throw InvalidDomainArgumentException(
        '${operation.wireValue} does not accept a reason.',
      );
    }
    if (normalized != null && normalized.runes.length > 1000) {
      throw InvalidDomainArgumentException(
        'reason must contain at most 1000 Unicode scalar values.',
      );
    }
    return normalized;
  }

  Map<String, Object?> toRpcParams() => {
    'p_order_id': orderId,
    'p_request_id': requestId,
    if (reason != null) 'p_reason': reason,
  };
}
