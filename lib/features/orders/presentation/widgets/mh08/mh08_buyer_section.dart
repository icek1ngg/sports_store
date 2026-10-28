import 'package:flutter/material.dart';

import '../../../domain/models/order_summary.dart';
import '../order_notification_theme.dart';

/// Shows the account buyer separately from the immutable recipient snapshot.
class Mh08BuyerSection extends StatelessWidget {
  const Mh08BuyerSection({required this.summary, super.key});

  final OrderSummary summary;

  @override
  Widget build(BuildContext context) {
    final order = summary.order;
    final accountName = _nonBlank(summary.customerDisplayName);
    final recipientName = order.recipientName.trim();
    final showRecipient = accountName != null && accountName != recipientName;

    return Container(
      key: const ValueKey('mh08-buyer-section'),
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: OrderNotificationTheme.cloud,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BuyerAvatar(),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _NameLine(
                  label: accountName == null ? 'Người nhận' : 'Khách hàng',
                  value: accountName ?? recipientName,
                ),
                if (showRecipient) ...[
                  const SizedBox(height: 2),
                  _NameLine(label: 'Người nhận', value: recipientName),
                ],
                const SizedBox(height: 2),
                Text(
                  order.addressDetail,
                  softWrap: true,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: OrderNotificationTheme.muted),
                ),
                const SizedBox(height: 2),
                Text(
                  order.recipientPhone,
                  softWrap: true,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: OrderNotificationTheme.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String? _nonBlank(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class _BuyerAvatar extends StatelessWidget {
  const _BuyerAvatar();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Thông tin người mua',
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.person_outline,
          size: 18,
          color: OrderNotificationTheme.ink,
        ),
      ),
    );
  }
}

class _NameLine extends StatelessWidget {
  const _NameLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth <= 240 ||
            MediaQuery.textScalerOf(context).scale(14) > 18;
        final labelText = Text(
          label,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: OrderNotificationTheme.muted),
        );
        final valueText = Text(
          value,
          softWrap: true,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            height: 18 / 14,
            fontWeight: FontWeight.w600,
            color: OrderNotificationTheme.ink,
          ),
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [labelText, valueText],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            labelText,
            const SizedBox(width: 4),
            Expanded(child: valueText),
          ],
        );
      },
    );
  }
}
