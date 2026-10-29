import 'package:flutter/material.dart';

import '../../../domain/models/order_item.dart';
import '../../../domain/models/order_summary.dart';
import '../order_notification_theme.dart';

/// Renders only the immutable item snapshot supplied in the order summary.
class Mh08ItemPreview extends StatelessWidget {
  const Mh08ItemPreview({
    required this.summary,
    this.showQuantity = true,
    super.key,
  });

  final OrderSummary summary;
  final bool showQuantity;

  @override
  Widget build(BuildContext context) {
    final preview = summary.itemPreview;
    return Column(
      key: const ValueKey('mh08-item-preview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showQuantity)
          Text(
            '${summary.itemQuantityTotal} sản phẩm',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              height: 20 / 14,
              color: OrderNotificationTheme.muted,
            ),
          ),
        if (preview.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Chưa có bản xem trước sản phẩm'),
          )
        else
          ...preview.asMap().entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _ItemRow(item: entry.value),
            ),
          ),
        if (summary.itemLineCount > preview.length)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Và ${summary.itemLineCount - preview.length} dòng sản phẩm khác',
              softWrap: true,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final OrderItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ProductPlaceholder(),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.productName,
                softWrap: true,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  height: 18 / 14,
                  fontWeight: FontWeight.w600,
                  color: OrderNotificationTheme.ink,
                ),
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 8,
                runSpacing: 0,
                children: [
                  Text(
                    'Biến thể: ${item.variantLabel}',
                    softWrap: true,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    'Số lượng: ${item.quantity}',
                    softWrap: true,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProductPlaceholder extends StatelessWidget {
  const _ProductPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Không có ảnh sản phẩm',
      container: true,
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.image_not_supported_outlined,
          size: 22,
          color: OrderNotificationTheme.muted,
        ),
      ),
    );
  }
}
