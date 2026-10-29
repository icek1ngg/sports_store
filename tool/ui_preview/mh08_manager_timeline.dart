import 'package:sports_store/features/orders/domain/models/order.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/domain/models/order_timeline_entry.dart';

import 'mh08_manager_projections.dart';

/// Builds only the typed historical/snapshot timeline used by MH08 details.
final class Mh08ManagerTimeline {
  static List<OrderTimelineEntry> build(
    Order order,
    String taskId,
    bool failed,
  ) {
    final suffix = int.parse(order.id.substring(order.id.length - 12));
    final result = <OrderTimelineEntry>[
      _event(
        Mh08ManagerProjections.uuid(12000 + suffix),
        TimelineEntityType.order,
        order.id,
        'order_placed',
        null,
        OrderStatus.pendingConfirmation.wireValue,
        null,
        TimelineActorSource.customer,
        order.placedAt,
        TimelineSource.actualEvent,
      ),
    ];
    if (order.status == OrderStatus.rejected || order.confirmedAt != null) {
      final rejected = order.status == OrderStatus.rejected;
      result.add(
        _event(
          Mh08ManagerProjections.uuid(13000 + suffix),
          TimelineEntityType.order,
          order.id,
          rejected ? 'order_rejected' : 'order_confirmed_manual',
          OrderStatus.pendingConfirmation.wireValue,
          rejected
              ? OrderStatus.rejected.wireValue
              : OrderStatus.preparing.wireValue,
          Mh08ManagerProjections.uuid(8000),
          TimelineActorSource.manager,
          order.confirmedAt ?? order.updatedAt,
          TimelineSource.actualEvent,
          reason: order.cancelReason,
          label: 'Quản lý',
        ),
      );
    }
    if (failed || order.status == OrderStatus.delivered) {
      result.add(
        _event(
          Mh08ManagerProjections.uuid(14000 + suffix),
          TimelineEntityType.deliveryTask,
          taskId,
          failed ? 'outbound_failed' : 'outbound_delivered',
          DeliveryTaskStatus.inTransit.wireValue,
          (failed ? DeliveryTaskStatus.failed : DeliveryTaskStatus.delivered)
              .wireValue,
          Mh08ManagerProjections.uuid(9000),
          TimelineActorSource.shipper,
          order.deliveredAt ?? order.updatedAt,
          TimelineSource.actualEvent,
          reason: failed ? 'Không liên lạc được người nhận.' : null,
          label: 'Nguyễn Văn Shipper',
        ),
      );
    }
    result.add(
      _event(
        null,
        TimelineEntityType.order,
        order.id,
        'snapshot_milestone',
        null,
        order.status.wireValue,
        null,
        TimelineActorSource.system,
        order.updatedAt,
        TimelineSource.snapshotMilestone,
        label: 'Ảnh chụp trạng thái',
      ),
    );
    return result;
  }

  static OrderTimelineEntry _event(
    String? eventId,
    TimelineEntityType entity,
    String entityId,
    String kind,
    String? from,
    String? to,
    String? actorId,
    TimelineActorSource actor,
    DateTime occurredAt,
    TimelineSource source, {
    String? reason,
    String? label,
  }) => OrderTimelineEntry(
    eventId: eventId,
    sourceEntityType: entity,
    sourceEntityId: entityId,
    eventKind: kind,
    fromState: from,
    toState: to,
    actorId: actorId,
    actorLabel: label,
    actorSource: actor,
    occurredAt: occurredAt,
    reason: reason,
    source: source,
  );
}
