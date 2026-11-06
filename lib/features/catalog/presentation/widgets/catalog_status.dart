import 'package:flutter/material.dart';

class CatalogLoadingState extends StatelessWidget {
  const CatalogLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      key: ValueKey('catalog-products-loading'),
      child: CircularProgressIndicator(),
    );
  }
}

class CatalogErrorState extends StatelessWidget {
  const CatalogErrorState({required this.onRetry, super.key, this.message});

  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('catalog-products-error'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 42,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              message ?? 'Không tải được sản phẩm. Vui lòng thử lại.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }
}

class CatalogEmptyState extends StatelessWidget {
  const CatalogEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      key: ValueKey('catalog-products-empty'),
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_outlined, size: 44),
            SizedBox(height: 12),
            Text(
              'Chưa tìm thấy sản phẩm phù hợp.',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 4),
            Text(
              'Hãy thử từ khóa hoặc danh mục khác.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
