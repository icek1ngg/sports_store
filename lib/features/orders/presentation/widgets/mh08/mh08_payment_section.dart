import 'package:flutter/material.dart';

import '../../../../../core/utils/display_formatters.dart';
import '../../../domain/models/cod_summary.dart';
import '../order_notification_theme.dart';

/// Compact payment projection for a manager order card.
class Mh08PaymentSection extends StatelessWidget {
  const Mh08PaymentSection({
    required this.totalCodVnd,
    required this.itemQuantityTotal,
    required this.codSummary,
    super.key,
  });

  final int totalCodVnd;
  final int itemQuantityTotal;
  final CodSummary? codSummary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('mh08-payment-section'),
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 290 ||
              MediaQuery.textScalerOf(context).scale(14) > 18;
          final details = _PaymentDetails(codSummary: codSummary);
          final amount = _Amount(
            totalCodVnd: totalCodVnd,
            itemQuantityTotal: itemQuantityTotal,
          );
          return compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [amount, const SizedBox(height: 4), details],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: amount),
                    const SizedBox(width: 8),
                    Flexible(child: details),
                  ],
                );
        },
      ),
    );
  }
}

class _Amount extends StatelessWidget {
  const _Amount({required this.totalCodVnd, required this.itemQuantityTotal});

  final int totalCodVnd;
  final int itemQuantityTotal;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$itemQuantityTotal sản phẩm',
          softWrap: true,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            height: 20 / 14,
            color: OrderNotificationTheme.muted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          formatVnd(totalCodVnd),
          softWrap: true,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 20,
            height: 26 / 20,
            fontWeight: FontWeight.w700,
            color: OrderNotificationTheme.ink,
          ),
        ),
      ],
    );
  }
}

class _PaymentDetails extends StatelessWidget {
  const _PaymentDetails({required this.codSummary});

  final CodSummary? codSummary;

  @override
  Widget build(BuildContext context) {
    final status = codSummary == null
        ? 'Trạng thái COD: Chưa có dữ liệu'
        : 'Trạng thái COD: ${codStatusLabel(codSummary!.status)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: OrderNotificationTheme.cloud,
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text(
            'COD • Nhận tiền mặt',
            softWrap: true,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              height: 14 / 11,
              fontWeight: FontWeight.w600,
              color: OrderNotificationTheme.ink,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          status,
          softWrap: true,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
