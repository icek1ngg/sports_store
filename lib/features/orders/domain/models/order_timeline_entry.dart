import 'model_validators.dart';
import 'order_status.dart';

class OrderTimelineEntry {
  OrderTimelineEntry({
    required String? eventId,
    required this.sourceEntityType,
    required String sourceEntityId,
    required String eventKind,
    required this.fromState,
    required this.toState,
    required String? actorId,
    required this.actorLabel,
    required this.actorSource,
    required DateTime occurredAt,
    required this.reason,
    required this.source,
  }) : eventId = eventId == null
           ? null
           : validateUuidValue(eventId, field: 'eventId'),
       sourceEntityId = validateUuidValue(
         sourceEntityId,
         field: 'sourceEntityId',
       ),
       eventKind = validateNonBlank(eventKind, field: 'eventKind'),
       actorId = actorId == null
           ? null
           : validateUuidValue(actorId, field: 'actorId'),
       occurredAt = validateUtc(occurredAt, field: 'occurredAt') {
    if (!_knownEventKinds.contains(eventKind)) {
      throw InvalidDomainArgumentException(
        'Unsupported timeline event kind: $eventKind.',
      );
    }
    if (eventKind == 'snapshot_milestone' &&
        source != TimelineSource.snapshotMilestone) {
      throw InvalidDomainArgumentException(
        'snapshot_milestone must use snapshot_milestone source.',
      );
    }
    if (eventKind != 'snapshot_milestone' &&
        source == TimelineSource.snapshotMilestone) {
      throw InvalidDomainArgumentException(
        'Only snapshot_milestone may use snapshot_milestone source.',
      );
    }
    if (source == TimelineSource.snapshotMilestone &&
        sourceEntityType != TimelineEntityType.order) {
      throw InvalidDomainArgumentException(
        'Snapshot milestones must reference the order entity.',
      );
    }
    if (eventKind == 'legacy_unknown' &&
        actorSource != TimelineActorSource.unknown) {
      throw InvalidDomainArgumentException(
        'Legacy timeline events must use the unknown actor source.',
      );
    }
    if (fromState != null && fromState!.trim().isEmpty) {
      throw InvalidDomainArgumentException('fromState must not be blank.');
    }
    if (toState != null && toState!.trim().isEmpty) {
      throw InvalidDomainArgumentException('toState must not be blank.');
    }
    final expectedEntity = _entityForEventKind(eventKind);
    if (expectedEntity != null && sourceEntityType != expectedEntity) {
      throw InvalidDomainArgumentException(
        '$eventKind must reference ${expectedEntity.wireValue}.',
      );
    }
    _validateState(sourceEntityType, fromState, 'fromState');
    _validateState(sourceEntityType, toState, 'toState');
  }

  final String? eventId;
  final TimelineEntityType sourceEntityType;
  final String sourceEntityId;
  final String eventKind;
  final String? fromState;
  final String? toState;
  final String? actorId;
  final String? actorLabel;
  final TimelineActorSource actorSource;
  final DateTime occurredAt;
  final String? reason;
  final TimelineSource source;

  static void _validateState(
    TimelineEntityType entityType,
    String? state,
    String field,
  ) {
    if (state == null) return;
    switch (entityType) {
      case TimelineEntityType.order:
        OrderStatus.parse(state, path: field);
        break;
      case TimelineEntityType.deliveryTask:
        DeliveryTaskStatus.parse(state, path: field);
        break;
      case TimelineEntityType.cod:
        CodStatus.parse(state, path: field);
        break;
      case TimelineEntityType.returnRequest:
        ReturnRequestStatus.parse(state, path: field);
        break;
    }
  }

  static const knownEventKinds = _knownEventKinds;

  static TimelineEntityType? _entityForEventKind(String kind) {
    return switch (kind) {
      'order_placed' ||
      'order_confirmed_manual' ||
      'order_confirmed_automatic' ||
      'order_rejected' ||
      'order_cancelled' => TimelineEntityType.order,
      'cod_received' => TimelineEntityType.cod,
      'return_submitted' => TimelineEntityType.returnRequest,
      _ => null,
    };
  }

  static const _knownEventKinds = <String>{
    'order_placed',
    'order_confirmed_manual',
    'order_confirmed_automatic',
    'order_rejected',
    'order_cancelled',
    'task_assigned',
    'task_reassigned',
    'outbound_delivered',
    'outbound_failed',
    'custody_incident',
    'cod_received',
    'return_submitted',
    'return_pickup_approved',
    'return_initial_rejected',
    'return_pickup_failed',
    'return_collection_rescheduled',
    'return_more_evidence_requested',
    'return_inspection_rejected',
    'refund_recorded',
    'rejected_goods_redelivery_assigned',
    'rejected_goods_redelivery_completed',
    'rejected_goods_redelivery_failed',
    'order_pickup',
    'order_store_handover',
    'order_store_received',
    'order_inventory_inspected',
    'task_assignment_audit',
    'legacy_unknown',
    'snapshot_milestone',
  };

  Map<String, Object?> toMap() => {
    'event_id': eventId,
    'source_entity_type': sourceEntityType.wireValue,
    'source_entity_id': sourceEntityId,
    'event_kind': eventKind,
    'from_state': fromState,
    'to_state': toState,
    'actor_id': actorId,
    'actor_label': actorLabel,
    'actor_source': actorSource.wireValue,
    'occurred_at': occurredAt.toIso8601String(),
    'reason': reason,
    'source': source.wireValue,
  };
}
