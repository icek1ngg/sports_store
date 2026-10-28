import 'model_validators.dart';
import 'order_status.dart';

class ReturnSummary {
  ReturnSummary({
    required String returnId,
    required String orderId,
    required this.status,
    required DateTime submittedAt,
    required DateTime? closedAt,
    required this.decisionReason,
    required this.isActive,
    required this.canSubmitReturn,
    required this.eligibilityReason,
    required DateTime? returnDeadline,
  }) : returnId = validateUuidValue(returnId, field: 'returnId'),
       orderId = validateUuidValue(orderId, field: 'orderId'),
       submittedAt = validateUtc(submittedAt, field: 'submittedAt'),
       closedAt = closedAt == null
           ? null
           : validateUtc(closedAt, field: 'closedAt'),
       returnDeadline = returnDeadline == null
           ? null
           : validateUtc(returnDeadline, field: 'returnDeadline');

  final String returnId;
  final String orderId;
  final ReturnRequestStatus status;
  final DateTime submittedAt;
  final DateTime? closedAt;
  final String? decisionReason;
  final bool isActive;
  final bool canSubmitReturn;
  final EligibilityReason? eligibilityReason;
  final DateTime? returnDeadline;

  Map<String, Object?> toMap() => {
    'return_id': returnId,
    'order_id': orderId,
    'status': status.wireValue,
    'submitted_at': submittedAt.toIso8601String(),
    'closed_at': closedAt?.toIso8601String(),
    'decision_reason': decisionReason,
    'is_active': isActive,
    'can_submit_return': canSubmitReturn,
    'eligibility_reason': eligibilityReason?.wireValue,
    'return_deadline': returnDeadline?.toIso8601String(),
  };
}
