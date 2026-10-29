import 'package:flutter/material.dart';

import '../../../../../core/utils/display_formatters.dart';
import '../../../domain/models/order.dart';
import '../../../domain/models/order_details.dart';
import '../../../domain/models/order_operation.dart';
import '../../widgets/order_items_section.dart';
import '../../widgets/order_lifecycle_sections.dart';
import '../../widgets/order_payment_section.dart';
import '../../widgets/order_recipient_section.dart';
import '../../widgets/order_status_badge.dart';
import '../../widgets/order_timeline.dart';
import 'mh09_legacy_contact_actions.dart';
import 'mh09_legacy_action_footer.dart';

class Mh09LegacyDetailBody extends StatelessWidget {
  const Mh09LegacyDetailBody({
    super.key,
    required this.details,
    required this.onShowAction,
    required this.isStillAllowed,
    required this.onRefresh,
    this.onOpenCod,
    this.onOpenReturn,
    this.onOpenChat,
    this.onCallRecipient,
  });

  final OrderDetails details;
  final void Function(OrderOperation operation) onShowAction;
  final bool Function(OrderOperation operation) isStillAllowed;
  final Future<void> Function() onRefresh;
  final ValueChanged<String>? onOpenCod;
  final ValueChanged<String>? onOpenReturn;
  final ValueChanged<String>? onOpenChat;
  final ValueChanged<String>? onCallRecipient;

  @override
  Widget build(BuildContext context) {
    final order = details.order;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OrderHeader(order: order),
            const SizedBox(height: 12),
            OrderRecipientSection(order: order, buyer: details.buyer),
            const SizedBox(height: 12),
            OrderItemsSection(items: details.items),
            const SizedBox(height: 12),
            OrderPaymentSection(order: order, codSummary: details.codSummary),
            const SizedBox(height: 12),
            OrderLifecycleSections(
              deliverySummary: details.deliverySummary,
              codSummary: details.codSummary,
              returnSummaries: details.returnSummaries,
              onOpenCod: onOpenCod,
              onOpenReturn: onOpenReturn,
            ),
            const SizedBox(height: 12),
            OrderTimeline(
              entries: details.timeline,
              historyComplete: details.historyComplete,
            ),
            const SizedBox(height: 12),
            Mh09LegacyContactActions(
              customerId: order.customerId,
              recipientPhone: order.recipientPhone,
              onOpenChat: onOpenChat,
              onCallRecipient: onCallRecipient,
            ),
            const SizedBox(height: 12),
            Mh09LegacyActionFooter(
              details: details,
              externalActionsOnly: true,
              onShowAction: onShowAction,
              isStillAllowed: isStillAllowed,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _OrderHeader extends StatelessWidget {
  const _OrderHeader({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Đơn hàng ${order.id}',
              softWrap: true,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OrderStatusBadge(status: order.status),
                Text('Đặt lúc ${formatHanoiDateTime(order.placedAt)}'),
              ],
            ),
            if (order.deliveryAttemptCount > 0) ...[
              const SizedBox(height: 8),
              Text('Số lần giao đã ghi nhận: ${order.deliveryAttemptCount}/2'),
            ],
          ],
        ),
      ),
    );
  }
}
