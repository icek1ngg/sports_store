import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../catalog/domain/models/product_variant.dart';
import '../../../catalog/presentation/widgets/catalog_formatters.dart';
import '../../../catalog/presentation/widgets/catalog_image.dart';
import '../../domain/models/cart_item.dart';
import 'cart_notice.dart';

/// A single editable row in MH06.
///
/// The row deliberately remains rendered for unavailable catalogue entries.
/// Customers must be able to remove those entries even when the catalogue no
/// longer exposes their product or variant.
class CartItemTile extends StatelessWidget {
  const CartItemTile({
    required this.item,
    required this.mutationsEnabled,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
    this.selected = true,
    this.onSelectionChanged,
    super.key,
  });

  final CartItem item;
  final bool mutationsEnabled;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onRemove;
  final bool selected;
  final ValueChanged<bool>? onSelectionChanged;

  String? get _productId {
    final id = item.product?.id.trim();
    return id == null || id.isEmpty ? null : id;
  }

  String get _productName {
    final name = item.product?.name.trim();
    return name == null || name.isEmpty ? 'Sản phẩm không còn khả dụng' : name;
  }

  String get _variantLabel {
    final variant = item.variant;
    if (variant == null) return 'Biến thể không còn khả dụng';
    final label = variant.label.trim();
    if (label.isNotEmpty) return label;
    final sku = variant.sku.trim();
    return sku.isEmpty ? 'Biến thể mặc định' : 'Mã hàng: $sku';
  }

  String get _variantDescription {
    final variant = item.variant;
    if (variant == null) return _variantLabel;
    final color = variant.color ?? variant.attributes['Màu'];
    final size = variant.size ?? variant.attributes['Cỡ'];
    final values = <String>[
      if (color is String && color.trim().isNotEmpty) color.trim(),
      if (size is String && size.trim().isNotEmpty) 'Cỡ ${size.trim()}',
    ];
    return (values.isEmpty ? _variantLabel : values.join(' • ')).toUpperCase();
  }

  String? get _imagePath {
    final images = item.variant?.imagePaths;
    return images != null && images.isNotEmpty
        ? images.first
        : item.product?.imagePath;
  }

  Widget _selection(BuildContext context) => SizedBox(
    width: 30,
    child: Checkbox(
      key: ValueKey('cart-select-${item.variantId}'),
      value: selected,
      semanticLabel: 'Chọn $_productName',
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      onChanged: mutationsEnabled && onSelectionChanged != null
          ? (value) => onSelectionChanged!(value ?? false)
          : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final imageSize = constraints.maxWidth < 350 ? 76.0 : 90.0;
        final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
        final image = _ProductImage(imagePath: _imagePath, size: imageSize);
        return Card(
          key: ValueKey('cart-item-${item.variantId}'),
          elevation: 0,
          color: Theme.of(context).colorScheme.surface,
          margin: const EdgeInsets.symmetric(vertical: 6),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: largeText
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (onSelectionChanged != null) ...[
                            _selection(context),
                            const SizedBox(width: 6),
                          ],
                          image,
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildDetails(context),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (onSelectionChanged != null) ...[
                        _selection(context),
                        const SizedBox(width: 6),
                      ],
                      image,
                      const SizedBox(width: 12),
                      Expanded(child: _buildDetails(context)),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildDetails(BuildContext context) {
    final productId = _productId;
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _productName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(
          _variantDescription,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: productId == null
                  ? identity
                  : InkWell(
                      key: ValueKey('cart-product-${item.variantId}'),
                      onTap: () =>
                          context.push('/customer/products/$productId'),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: identity,
                      ),
                    ),
            ),
            IconButton(
              key: ValueKey('cart-remove-${item.variantId}'),
              onPressed: mutationsEnabled ? onRemove : null,
              tooltip: 'Xóa khỏi giỏ hàng',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.delete_outline, size: 19),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          item.variant == null
              ? 'Giá không còn khả dụng'
              : formatVnd(item.variant!.priceVnd),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final controls = _QuantityControls(
              item: item,
              enabled: mutationsEnabled && item.isAvailable,
              onIncrease: onIncrease,
              onDecrease: onDecrease,
            );
            final total = item.lineTotalVnd;
            final totalLabel = total == null
                ? null
                : Text(
                    'Thành tiền: ${formatVnd(total)}',
                    key: ValueKey('cart-line-total-${item.variantId}'),
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.end,
                  );
            if (constraints.maxWidth > 330 &&
                MediaQuery.textScalerOf(context).scale(14) < 22) {
              return Row(
                children: [
                  controls,
                  const SizedBox(width: 8),
                  if (totalLabel != null) Expanded(child: totalLabel),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                controls,
                if (totalLabel != null) ...[
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: totalLabel),
                ],
              ],
            );
          },
        ),
        if (!item.isAvailable) ...[
          const SizedBox(height: 8),
          const CartNotice(
            isError: true,
            icon: Icons.remove_shopping_cart_outlined,
            message: 'Sản phẩm hoặc biến thể này không còn được bán. Bạn có thể xóa dòng hàng.',
          ),
        ] else if (!item.hasEnoughStock) ...[
          const SizedBox(height: 8),
          CartNotice(
            isError: true,
            icon: Icons.inventory_2_outlined,
            message:
                'Chỉ còn ${_stockMessage(item.variant!)}. Hãy giảm số lượng trước khi đặt hàng.',
          ),
        ] else if (item.variant!.availableQuantity <= 3) ...[
          const SizedBox(height: 8),
          Text(
            'Chỉ còn ${item.variant!.availableQuantity} sản phẩm trong kho',
            key: ValueKey('cart-low-stock-${item.variantId}'),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  static String _stockMessage(ProductVariant variant) {
    if (variant.availableQuantity <= 0) return '0 sản phẩm';
    return '${variant.availableQuantity} sản phẩm';
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.imagePath, required this.size});

  final String? imagePath;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = imagePath?.trim();
    if (path == null || path.isEmpty) {
      final scheme = Theme.of(context).colorScheme;
      return SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Semantics(
            label: 'Chưa có ảnh sản phẩm',
            image: true,
            child: Icon(
              Icons.image_outlined,
              color: scheme.onSurfaceVariant,
              size: size * 0.42,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: CatalogProductImage(
        compact: true,
        imagePath: path,
        width: size,
        height: size,
        borderRadius: 14,
        fit: BoxFit.contain,
      ),
    );
  }
}

class _QuantityControls extends StatelessWidget {
  const _QuantityControls({
    required this.item,
    required this.enabled,
    required this.onIncrease,
    required this.onDecrease,
  });

  final CartItem item;
  final bool enabled;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;

  @override
  Widget build(BuildContext context) {
    final variant = item.variant;
    final canIncrease =
        enabled && variant != null && variant.availableQuantity > item.quantity;
    final canDecrease =
        enabled &&
        item.quantity > 1 &&
        variant != null &&
        variant.availableQuantity > 0;
    final reduceToAvailable =
        enabled &&
        variant != null &&
        variant.availableQuantity > 0 &&
        item.quantity > variant.availableQuantity;

    return LayoutBuilder(
      builder: (context, constraints) => Container(
        constraints: BoxConstraints(
          maxWidth: constraints.maxWidth.clamp(0, 168).toDouble(),
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: ValueKey('cart-decrease-${item.variantId}'),
              onPressed: canDecrease ? onDecrease : null,
              tooltip: reduceToAvailable
                  ? 'Giảm còn ${variant.availableQuantity}'
                  : 'Giảm số lượng',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove),
            ),
            Flexible(
              child: Container(
                key: ValueKey('cart-quantity-${item.variantId}'),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                child: Semantics(
                  label: 'Số lượng ${item.quantity}',
                  container: true,
                  excludeSemantics: true,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${item.quantity}',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              key: ValueKey('cart-increase-${item.variantId}'),
              onPressed: canIncrease ? onIncrease : null,
              tooltip: 'Tăng số lượng',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }
}
