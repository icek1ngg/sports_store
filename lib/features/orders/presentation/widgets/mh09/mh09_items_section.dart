import 'package:flutter/material.dart';

import 'package:sports_store/core/utils/display_formatters.dart';
import 'package:sports_store/features/orders/domain/models/order_item.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_notification_theme.dart';

/// Renders the immutable product and variant snapshots stored on an order.
class Mh09ItemsSection extends StatelessWidget {
  Mh09ItemsSection({required List<OrderItem> items, super.key})
    : items = List<OrderItem>.unmodifiable(items);

  final List<OrderItem> items;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Semantics(
        container: true,
        header: true,
        child: Text('Sản phẩm trong đơn', style: _itemsHeading(context)),
      ),
      const SizedBox(height: 16),
      Text('${items.length} dòng sản phẩm'),
      const SizedBox(height: 12),
    ];
    if (items.isEmpty) {
      children.add(
        Text(
          'Không có dòng sản phẩm',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    } else {
      for (var index = 0; index < items.length; index++) {
        final item = items[index];
        children.add(
          Padding(
            padding: EdgeInsets.only(
              bottom: index == items.length - 1 ? 0 : 12,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: _Mh09ItemRow(key: ValueKey<String>(item.id), item: item),
              ),
            ),
          ),
        );
      }
    }

    return Card(
      key: const ValueKey('mh09-items-card'),
      color: OrderNotificationTheme.cloud,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

TextStyle _itemsHeading(BuildContext context) {
  return Theme.of(context).textTheme.bodyLarge?.copyWith(
        fontFamily: 'Inter',
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: OrderNotificationTheme.ink,
      ) ??
      const TextStyle(
        fontFamily: 'Inter',
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: OrderNotificationTheme.ink,
      );
}

// Keep the complete OrderItem snapshot on the row. Current fixtures expose
// source metadata in attributes; color and size are already represented by
// variantLabel, so rendering attributes would duplicate or expose debug data.
class _Mh09ItemRow extends StatelessWidget {
  const _Mh09ItemRow({required this.item, super.key});

  final OrderItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          excludeSemantics: true,
          label: 'Không có ảnh sản phẩm',
          child: SizedBox.square(
            dimension: 64,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.image_not_supported_outlined,
                color: OrderNotificationTheme.muted,
                semanticLabel: 'Không có ảnh sản phẩm',
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.productName,
                softWrap: true,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: OrderNotificationTheme.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text('Biến thể: ${item.variantLabel}', softWrap: true),
              const SizedBox(height: 4),
              Text('Số lượng: ${item.quantity}', softWrap: true),
              const SizedBox(height: 4),
              Text('Đơn giá: ${formatVnd(item.unitPriceVnd)}', softWrap: true),
              Text(
                'Thành tiền: ${formatVnd(item.lineTotalVnd)}',
                softWrap: true,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: OrderNotificationTheme.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
