import 'package:flutter/material.dart';

import '../../domain/models/product.dart';
import 'catalog_formatters.dart';
import 'catalog_image.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({required this.product, this.onTap, super.key});

  final Product product;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stock = product.availableQuantity;
    final category = product.categoryName.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.12,
              child: CatalogProductImage(
                imagePath: product.imagePath,
                width: double.infinity,
                fit: BoxFit.cover,
                borderRadius: 8,
              ),
            ),
            const SizedBox(height: 10),
            if (category.isNotEmpty)
              Text(
                category.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            const SizedBox(height: 3),
            Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              product.minPriceVnd == null
                  ? 'Liên hệ'
                  : 'Từ ${formatVnd(product.minPriceVnd)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formatAvailableQuantity(stock),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: stock > 0 ? scheme.onSurfaceVariant : scheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
