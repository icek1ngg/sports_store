import 'package:flutter/material.dart';

import '../../../../app/theme/storefront_theme.dart';
import '../../domain/models/product.dart';
import 'catalog_formatters.dart';
import 'catalog_image.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({required this.product, this.onTap, super.key});
  final Product product;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final stock = product.availableQuantity;
    final badge = stock == 0
        ? 'HẾT HÀNG'
        : product.variants.length > 1
        ? 'NHIỀU CỠ'
        : 'CÒN HÀNG';
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: StorefrontTheme.cloud,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: CatalogProductImage(
                      imagePath: product.imagePath,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      borderRadius: 6,
                      compact: true,
                    ),
                  ),
                  Positioned(
                    top: 9,
                    left: 9,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 110),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: stock == 0
                            ? StorefrontTheme.muted
                            : product.variants.length > 1
                            ? StorefrontTheme.ink
                            : StorefrontTheme.success,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        badge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: IconButton.filledTonal(
                      tooltip: 'Xem chi tiết sản phẩm',
                      onPressed: onTap,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        minimumSize: const Size(32, 32),
                        padding: const EdgeInsets.all(6),
                      ),
                      icon: const Icon(Icons.arrow_outward, size: 16),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              product.categoryName.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9,
                color: StorefrontTheme.muted,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              product.minPriceVnd == null
                  ? 'Chưa có giá'
                  : formatVnd(product.minPriceVnd),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
