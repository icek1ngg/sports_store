import 'package:flutter/material.dart';

import '../../../../../core/utils/display_formatters.dart';
import '../../../domain/models/order.dart';
import '../order_notification_theme.dart';
import '../order_status_badge.dart';

/// Compact, responsive identity block for an MH08 order card.
class Mh08CardHeader extends StatelessWidget {
  const Mh08CardHeader({required this.order, super.key});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth <= 300 ||
            MediaQuery.textScalerOf(context).scale(14) > 18;
        final uuid = _Uuid(order: order);
        final timestamp = _Timestamp(order: order);
        final status = ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: constraints.maxWidth * (stacked ? 1 : .56),
          ),
          child: OrderStatusBadge(status: order.status),
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              uuid,
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [timestamp, status],
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: uuid),
                const SizedBox(width: 8),
                Flexible(fit: FlexFit.loose, child: status),
              ],
            ),
            const SizedBox(height: 4),
            timestamp,
          ],
        );
      },
    );
  }
}

class _Uuid extends StatelessWidget {
  const _Uuid({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: 'Đơn hàng ${formatFullUuid(order.id)}',
      excludeSemantics: true,
      child: Tooltip(
        message: formatFullUuid(order.id),
        child: Text(
          formatFullUuid(order.id),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.titleMedium?.copyWith(
            fontSize: 20,
            height: 26 / 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _Timestamp extends StatelessWidget {
  const _Timestamp({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return Text(
      formatHanoiDateTime(order.placedAt),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        fontSize: 11,
        height: 14 / 11,
        color: OrderNotificationTheme.muted,
      ),
    );
  }
}
