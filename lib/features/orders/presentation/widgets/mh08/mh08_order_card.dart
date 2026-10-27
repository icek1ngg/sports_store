import 'package:flutter/material.dart';

import '../../../domain/models/order_summary.dart';
import '../order_notification_theme.dart';
import 'mh08_buyer_section.dart';
import 'mh08_card_actions.dart';
import 'mh08_card_header.dart';
import 'mh08_item_preview.dart';
import 'mh08_operational_notice.dart';
import 'mh08_payment_section.dart';

/// Isolated MH08 composition. Parent owns authorization and decision visibility.
class Mh08OrderCard extends StatelessWidget {
  const Mh08OrderCard({
    required this.summary,
    required this.isFresh,
    required this.showDecisionActions,
    this.canConfirm = false,
    this.canReject = false,
    this.enabled = true,
    this.isBusy = false,
    this.onConfirm,
    this.onReject,
    this.onOpenOrder,
    super.key,
  });

  final OrderSummary summary;
  final bool isFresh;
  final bool showDecisionActions;
  final bool canConfirm;
  final bool canReject;
  final bool enabled;
  final bool isBusy;
  final VoidCallback? onConfirm;
  final VoidCallback? onReject;
  final VoidCallback? onOpenOrder;

  @override
  Widget build(BuildContext context) {
    final order = summary.order;
    final detailAvailable = enabled && !isBusy && onOpenOrder != null;
    final detailReason = !enabled
        ? 'Chi tiết đơn hàng hiện không khả dụng'
        : isBusy
        ? 'Đang xử lý đơn hàng'
        : onOpenOrder == null
        ? 'Chi tiết đơn hàng hiện chưa khả dụng'
        : 'Xem chi tiết đơn hàng';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: OrderNotificationTheme.ink.withValues(alpha: .06),
            offset: const Offset(0, 4),
            blurRadius: 16,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Mh08CardHeader(order: order),
            const SizedBox(height: 8),
            Mh08BuyerSection(summary: summary),
            const SizedBox(height: 8),
            Mh08ItemPreview(summary: summary, showQuantity: false),
            const SizedBox(height: 8),
            Mh08PaymentSection(
              totalCodVnd: order.totalCodVnd,
              itemQuantityTotal: summary.itemQuantityTotal,
              codSummary: summary.codSummary,
            ),
            if (summary.warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              Mh08OperationalNotice(warnings: summary.warnings),
            ],
            if (!isFresh) ...[
              const SizedBox(height: 8),
              const Text('Dữ liệu có thể chưa cập nhật'),
            ],
            if (showDecisionActions) ...[
              const SizedBox(height: 8),
              Mh08CardActions(
                canConfirm: canConfirm,
                canReject: canReject,
                isFresh: isFresh,
                enabled: enabled,
                isBusy: isBusy,
                onConfirm: onConfirm,
                onReject: onReject,
              ),
            ],
            if (isBusy && !showDecisionActions)
              Semantics(
                liveRegion: true,
                child: const Text('Đang xử lý đơn hàng'),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: Tooltip(
                message: detailReason,
                child: OutlinedButton(
                  key: const ValueKey('mh08-open-order'),
                  onPressed: detailAvailable ? onOpenOrder : null,
                  child: Text(
                    detailAvailable
                        ? 'Xem chi tiết đơn hàng'
                        : 'Chi tiết chưa khả dụng',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
