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
    super.key,
  });

  final CartItem item;
  final bool mutationsEnabled;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onRemove;

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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final imageSize = constraints.maxWidth < 360 ? 76.0 : 92.0;
        return Card(
          key: ValueKey('cart-item-${item.variantId}'),
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProductImage(
                  imagePath: item.product?.imagePath,
                  size: imageSize,
                ),
                const SizedBox(width: 10),
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
          _variantLabel,
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
              icon: const Icon(Icons.delete_outline),
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
        _QuantityControls(
          item: item,
          enabled: mutationsEnabled && item.isAvailable,
          onIncrease: onIncrease,
          onDecrease: onDecrease,
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

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      runSpacing: 4,
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
        Container(
          key: ValueKey('cart-quantity-${item.variantId}'),
          constraints: const BoxConstraints(minWidth: 30),
          alignment: Alignment.center,
          child: Text(
            '${item.quantity}',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
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
    );
  }
}
