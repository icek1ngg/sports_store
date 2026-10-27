import 'package:flutter/material.dart';

import '../../domain/models/buyer.dart';
import '../../domain/models/order.dart';

/// Shows buyer and immutable recipient snapshot as separate concepts.
class OrderRecipientSection extends StatelessWidget {
  const OrderRecipientSection({
    required this.order,
    this.buyer,
    this.showPhone = true,
    super.key,
  });

  final Order order;
  final Buyer? buyer;
  final bool showPhone;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Người mua và người nhận',
      icon: Icons.person_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (buyer != null) ...[
            _InfoRow(
              label: 'Người mua',
              value: buyer!.fullName == null || buyer!.fullName!.trim().isEmpty
                  ? 'Chưa có tên tài khoản'
                  : buyer!.fullName!,
            ),
            const SizedBox(height: 8),
          ],
          _InfoRow(label: 'Người nhận', value: order.recipientName),
          if (showPhone) ...[
            const SizedBox(height: 8),
            _InfoRow(label: 'Số điện thoại', value: order.recipientPhone),
          ],
          const SizedBox(height: 8),
          _InfoRow(label: 'Địa chỉ nhận hàng', value: order.addressDetail),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, semanticLabel: title),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 320;
        final labelWidget = Text(
          label,
          style: Theme.of(context).textTheme.labelMedium,
        );
        final valueWidget = Text(value, softWrap: true);
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [labelWidget, const SizedBox(height: 2), valueWidget],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 116, child: labelWidget),
            const SizedBox(width: 8),
            Expanded(child: valueWidget),
          ],
        );
      },
    );
  }
}
