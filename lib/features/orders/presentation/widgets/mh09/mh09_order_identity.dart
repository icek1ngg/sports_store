import 'package:flutter/material.dart';

import '../../../../../core/utils/display_formatters.dart';
import '../../../domain/models/order.dart';
import '../order_status_badge.dart';

/// Renders the supplied canonical snapshot without deriving capabilities.
class Mh09OrderIdentity extends StatelessWidget {
  const Mh09OrderIdentity({required this.order, super.key});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          label: 'Mã đơn hàng: ${order.id}',
          excludeSemantics: true,
          child: Tooltip(
            message: order.id,
            excludeFromSemantics: true,
            child: Text(
              order.id,
              softWrap: true,
              style: text.headlineSmall?.copyWith(
                fontFamily: 'BarlowCondensed',
                fontFamilyFallback: const ['Inter'],
                fontSize: 28,
                height: 32 / 28,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        OrderStatusBadge(status: order.status),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ExcludeSemantics(child: Icon(Icons.schedule, size: 16)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Đặt lúc: ${formatHanoiDateTime(order.placedAt)}',
                style: text.bodyMedium,
              ),
            ),
          ],
        ),
        if (order.deliveryAttemptCount > 0) ...[
          const SizedBox(height: 8),
          Text(
            'Số lần giao đã ghi nhận: ${order.deliveryAttemptCount}/2',
            style: text.bodyMedium,
          ),
        ],
      ],
    );
  }
}
