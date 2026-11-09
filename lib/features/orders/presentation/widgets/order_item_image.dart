import 'package:flutter/material.dart';

import '../../../../app/theme/storefront_theme.dart';
import '../../../catalog/domain/models/product_variant.dart';
import '../../../catalog/presentation/widgets/catalog_image.dart';
import '../../domain/models/order_item.dart';

/// Renders only image metadata captured on this immutable order item.
/// Missing snapshots never trigger a lookup of today's catalog photograph.
class OrderItemImage extends StatelessWidget {
  const OrderItemImage({
    required this.item,
    this.size = 72,
    this.borderRadius = 16,
    super.key,
  });

  final OrderItem item;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    // Reuse the same metadata normalization as the checkout receipt. This
    // adapter is not a current catalog variant or a claim about available stock.
    final path = ProductVariant(
      id: item.variantId,
      productId: item.productId,
      sku: '',
      label: item.variantLabel,
      attributes: item.attributes,
      priceVnd: item.unitPriceVnd,
      availableQuantity: 0,
    ).imagePaths.firstOrNull;
    if (path == null) {
      return OrderItemImagePlaceholder(size: size, borderRadius: borderRadius);
    }
    return CatalogProductImage(
      imagePath: path,
      width: size,
      height: size,
      fit: BoxFit.contain,
      borderRadius: borderRadius,
      compact: true,
    );
  }
}

class OrderItemImagePlaceholder extends StatelessWidget {
  const OrderItemImagePlaceholder({
    this.size = 72,
    this.borderRadius = 16,
    super.key,
  });

  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    excludeSemantics: true,
    image: true,
    label: 'Không có ảnh sản phẩm',
    child: Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: StorefrontTheme.cloud,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: const Icon(
        Icons.image_not_supported_outlined,
        color: StorefrontTheme.muted,
        size: 24,
      ),
    ),
  );
}
