import 'package:flutter/material.dart';

import '../../../../../core/utils/display_formatters.dart';
import '../../../domain/models/cod_summary.dart';
import '../../../domain/models/order.dart';
import '../order_notification_theme.dart';

/// Financial overview of one accepted order aggregate, not COD reconciliation.
class Mh09PaymentSection extends StatelessWidget {
  const Mh09PaymentSection({required this.order, this.codSummary, super.key});

  final Order order;
  final CodSummary? codSummary;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      color: OrderNotificationTheme.cloud,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              container: true,
              header: true,
              child: Text(
                'THANH TOÁN',
                style: text.titleMedium?.copyWith(
                  fontFamily: 'Inter',
                  fontSize: 20,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _MoneyRow(label: 'Tạm tính', amount: order.subtotalVnd),
            const SizedBox(height: 8),
            _MoneyRow(label: 'Phí giao hàng', amount: order.deliveryFeeVnd),
            const Divider(height: 24),
            _MoneyRow(
              label: 'Tổng COD',
              amount: order.totalCodVnd,
              total: true,
            ),
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Thanh toán khi nhận hàng (COD)'),
                    const SizedBox(height: 8),
                    Text(
                      codSummary == null
                          ? 'Chưa có dữ liệu COD'
                          : 'Trạng thái COD: ${codStatusLabel(codSummary!.status)}',
                      style: text.labelLarge,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.amount,
    this.total = false,
  });

  final String label;
  final int amount;
  final bool total;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final formatted = formatVnd(amount);
    final valueStyle = total
        ? text.headlineMedium?.copyWith(
            fontFamily: 'BarlowCondensed',
            fontFamilyFallback: const ['Inter'],
            fontSize: 32,
            height: 36 / 32,
            fontWeight: FontWeight.w700,
          )
        : text.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$label: $formatted',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 300 ||
              MediaQuery.textScalerOf(context).scale(14) > 21;
          final labelWidget = Text(label, style: text.labelLarge);
          final valueWidget = Text(
            formatted,
            softWrap: true,
            style: valueStyle,
          );
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelWidget, const SizedBox(height: 4), valueWidget],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: labelWidget),
              const SizedBox(width: 12),
              Flexible(child: valueWidget),
            ],
          );
        },
      ),
    );
  }
}
