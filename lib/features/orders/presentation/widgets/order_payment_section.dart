import 'package:flutter/material.dart';

import '../../../../core/utils/display_formatters.dart';
import '../../domain/models/cod_summary.dart';
import '../../domain/models/order.dart';

/// Shows the immutable payment snapshot and the separate COD lifecycle.
class OrderPaymentSection extends StatelessWidget {
  const OrderPaymentSection({required this.order, this.codSummary, super.key});

  final Order order;
  final CodSummary? codSummary;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Thanh toán', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _MoneyRow(label: 'Tạm tính', amount: order.subtotalVnd),
            const SizedBox(height: 8),
            _MoneyRow(label: 'Phí giao hàng', amount: order.deliveryFeeVnd),
            const Divider(height: 24),
            _MoneyRow(
              label: 'Tổng COD',
              amount: order.totalCodVnd,
              emphasized: true,
            ),
            const SizedBox(height: 12),
            _CodState(codSummary: codSummary),
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
    this.emphasized = false,
  });

  final String label;
  final int amount;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            formatVnd(amount),
            textAlign: TextAlign.end,
            softWrap: true,
            style: style?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _CodState extends StatelessWidget {
  const _CodState({required this.codSummary});

  final CodSummary? codSummary;

  @override
  Widget build(BuildContext context) {
    final label = codSummary == null
        ? 'Chưa có dữ liệu COD'
        : 'Trạng thái COD: ${codStatusLabel(codSummary!.status)}';
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: label,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.payments_outlined, semanticLabel: 'COD'),
          const SizedBox(width: 8),
          Expanded(child: Text(label, softWrap: true)),
        ],
      ),
    );
  }
}
