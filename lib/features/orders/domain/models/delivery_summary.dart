import 'model_validators.dart';
import 'order_status.dart';

class AttemptSummary {
  AttemptSummary({
    required String id,
    required String taskId,
    required String orderId,
    required this.attemptNumber,
    required this.result,
    required this.reason,
    required DateTime occurredAt,
    required String? shipperId,
  }) : id = validateUuidValue(id),
       taskId = validateUuidValue(taskId, field: 'taskId'),
       orderId = validateUuidValue(orderId, field: 'orderId'),
       occurredAt = validateUtc(occurredAt, field: 'occurredAt'),
       shipperId = shipperId == null
           ? null
           : validateUuidValue(shipperId, field: 'shipperId') {
    if (attemptNumber < 1 || attemptNumber > 2) {
      throw InvalidDomainArgumentException(
        'attemptNumber must be between 1 and 2.',
      );
    }
    // Manager/raw projections require a reason for a failed attempt, while
    // the customer-safe projection deliberately redacts it.  The shared
    // domain projection therefore permits null and leaves role-specific
    // enforcement to the server mapper.
  }

  final String id;
  final String taskId;
  final String orderId;
  final int attemptNumber;
  final DeliveryAttemptResult result;
  final String? reason;
  final DateTime occurredAt;
  final String? shipperId;

  Map<String, Object?> toMap() => {
    'id': id,
    'task_id': taskId,
    'order_id': orderId,
    'attempt_number': attemptNumber,
    'task_kind': DeliveryTaskKind.outbound.wireValue,
    'result': result.wireValue,
    'reason': reason,
    'occurred_at': occurredAt.toIso8601String(),
    'shipper_id': shipperId,
  };
}

class DeliverySummary {
  DeliverySummary({
    required String? taskId,
    required this.kind,
    required this.taskStatus,
    required String? assignedShipperId,
    required this.assignedShipperName,
    required DateTime? assignedAt,
    required DateTime? acceptedAt,
    required DateTime? startedAt,
    required DateTime? completedAt,
    required this.amountToCollectVnd,
    required this.attemptCount,
    required this.latestAttempt,
    required this.failureReason,
  }) : taskId = taskId == null ? null : validateUuidValue(taskId),
       assignedShipperId = assignedShipperId == null
           ? null
           : validateUuidValue(assignedShipperId, field: 'assignedShipperId'),
       assignedAt = assignedAt == null
           ? null
           : validateUtc(assignedAt, field: 'assignedAt'),
       acceptedAt = acceptedAt == null
           ? null
           : validateUtc(acceptedAt, field: 'acceptedAt'),
       startedAt = startedAt == null
           ? null
           : validateUtc(startedAt, field: 'startedAt'),
       completedAt = completedAt == null
           ? null
           : validateUtc(completedAt, field: 'completedAt') {
    if (attemptCount < 0 || attemptCount > 2) {
      throw InvalidDomainArgumentException(
        'attemptCount must be between 0 and 2.',
      );
    }
    final amount = amountToCollectVnd;
    if (amount != null && amount < 0) {
      throw InvalidDomainArgumentException(
        'amountToCollectVnd must be non-negative.',
      );
    }
    if (kind != DeliveryTaskKind.outbound && amount != null && amount != 0) {
      throw InvalidDomainArgumentException(
        'Non-outbound tasks cannot collect COD.',
      );
    }
    final latest = latestAttempt;
    if (latest != null) {
      if (taskId != null && latest.taskId != taskId) {
        throw InvalidDomainArgumentException(
          'Latest delivery attempt must reference taskId.',
        );
      }
      if (latest.attemptNumber > attemptCount) {
        throw InvalidDomainArgumentException(
          'Latest delivery attempt exceeds attemptCount.',
        );
      }
    }
  }

  final String? taskId;
  final DeliveryTaskKind? kind;
  final DeliveryTaskStatus? taskStatus;
  final String? assignedShipperId;
  final String? assignedShipperName;
  final DateTime? assignedAt;
  final DateTime? acceptedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int? amountToCollectVnd;
  final int attemptCount;
  final AttemptSummary? latestAttempt;
  final String? failureReason;

  Map<String, Object?> toMap() => {
    'task_id': taskId,
    'kind': kind?.wireValue,
    'task_status': taskStatus?.wireValue,
    'assigned_shipper_id': assignedShipperId,
    'assigned_shipper_name': assignedShipperName,
    'assigned_at': assignedAt?.toIso8601String(),
    'accepted_at': acceptedAt?.toIso8601String(),
    'started_at': startedAt?.toIso8601String(),
    'completed_at': completedAt?.toIso8601String(),
    'amount_to_collect_vnd': amountToCollectVnd,
    'attempt_count': attemptCount,
    'latest_attempt': latestAttempt?.toMap(),
    'failure_reason': failureReason,
  };
}
