import 'package:flutter/material.dart';

import '../../../../core/utils/display_formatters.dart';
import '../../domain/models/order_item.dart';

/// Renders immutable product and variant snapshots from an order.
class OrderItemsSection extends StatelessWidget {
  const OrderItemsSection({
    required this.items,
    this.title = 'Sản phẩm trong đơn',
    this.showPrices = true,
    super.key,
  });

  final List<OrderItem> items;
  final String title;
  final bool showPrices;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const Text('Không có dòng sản phẩm')
            else
              ..._withDividers(),
          ],
        ),
      ),
    );
  }

  List<Widget> _withDividers() {
    final children = <Widget>[];
    for (var index = 0; index < items.length; index++) {
      if (index > 0) {
        children.add(const Divider(height: 24));
      }
      children.add(_OrderItemRow(item: items[index], showPrices: showPrices));
    }
    return children;
  }
}

class _OrderItemRow extends StatelessWidget {
  const _OrderItemRow({required this.item, required this.showPrices});

  final OrderItem item;
  final bool showPrices;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          excludeSemantics: true,
          label: 'Không có ảnh sản phẩm',
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.image_not_supported_outlined,
              color: colorScheme.outline,
              semanticLabel: 'Không có ảnh sản phẩm',
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.productName, style: textTheme.titleSmall),
              const SizedBox(height: 2),
              Text('Biến thể: ${item.variantLabel}', softWrap: true),
              const SizedBox(height: 4),
              Text('Số lượng: ${item.quantity}'),
              if (showPrices) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text('Đơn giá: ${formatVnd(item.unitPriceVnd)}'),
                    Text(
                      'Thành tiền: ${formatVnd(item.lineTotalVnd)}',
                      style: textTheme.labelLarge,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
