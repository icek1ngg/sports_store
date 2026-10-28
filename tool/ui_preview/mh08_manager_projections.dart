import 'package:sports_store/features/orders/domain/models/cod_summary.dart';
import 'package:sports_store/features/orders/domain/models/delivery_summary.dart';
import 'package:sports_store/features/orders/domain/models/order.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';

/// Construction helpers kept separate from the aggregate so preview files
/// remain small while still exposing typed delivery and COD projections.
final class Mh08ManagerProjections {
  static DeliverySummary delivery(
    Order order,
    OrderStatus status,
    String taskId,
    bool failed,
    DateTime placedAt,
    DateTime? confirmed,
  ) {
    final hasTask =
        status != OrderStatus.pendingConfirmation &&
        status != OrderStatus.rejected;
    final delivered = status == OrderStatus.delivered;
    final attempt = failed
        ? AttemptSummary(
            id: uuid(10000 + order.deliveryAttemptCount),
            taskId: taskId,
            orderId: order.id,
            attemptNumber: 1,
            result: DeliveryAttemptResult.failed,
            reason: 'Không liên lạc được người nhận.',
            occurredAt: placedAt.add(const Duration(hours: 1)),
            shipperId: uuid(9000),
          )
        : delivered
        ? AttemptSummary(
            id: uuid(11000 + order.deliveryAttemptCount),
            taskId: taskId,
            orderId: order.id,
            attemptNumber: 1,
            result: DeliveryAttemptResult.success,
            reason: null,
            occurredAt: order.deliveredAt!,
            shipperId: uuid(9000),
          )
        : null;
    return DeliverySummary(
      taskId: hasTask ? taskId : null,
      kind: hasTask ? DeliveryTaskKind.outbound : null,
      taskStatus: failed
          ? DeliveryTaskStatus.failed
          : delivered
          ? DeliveryTaskStatus.delivered
          : status == OrderStatus.delivering
          ? DeliveryTaskStatus.inTransit
          : status == OrderStatus.preparing
          ? DeliveryTaskStatus.assigned
          : null,
      assignedShipperId: hasTask ? uuid(9000) : null,
      assignedShipperName: hasTask ? 'Nguyễn Văn Shipper' : null,
      assignedAt: confirmed,
      acceptedAt: hasTask && status != OrderStatus.preparing
          ? placedAt.add(const Duration(minutes: 35))
          : null,
      startedAt: failed || delivered || status == OrderStatus.delivering
          ? placedAt.add(const Duration(minutes: 55))
          : null,
      completedAt: order.deliveredAt,
      amountToCollectVnd: hasTask ? order.totalCodVnd : null,
      attemptCount: order.deliveryAttemptCount,
      latestAttempt: attempt,
      failureReason: failed ? 'Không liên lạc được người nhận.' : null,
    );
  }

  static CodSummary cod(Order order, OrderStatus status) {
    final delivered = status == OrderStatus.delivered;
    final collected = delivered;
    return CodSummary(
      orderId: order.id,
      shipperId: collected ? uuid(9000) : null,
      status: delivered ? CodStatus.collected : CodStatus.uncollected,
      expectedAmountVnd: order.totalCodVnd,
      collectedAmountVnd: collected ? order.totalCodVnd : 0,
      receivedAmountVnd: 0,
      collectedAt: collected ? order.deliveredAt : null,
      collectedBy: collected ? uuid(9000) : null,
      handedOverAt: null,
      receivedAt: null,
      receivedBy: null,
    );
  }

  static String uuid(int value) =>
      '30000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';
}
