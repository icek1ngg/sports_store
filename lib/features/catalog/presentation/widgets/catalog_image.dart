import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../view_models/catalog_providers.dart';

/// Displays a product image from the private, signed image URL provider.
///
/// The catalog deliberately has a neutral placeholder for products without
/// an image. It also turns signed URL and network failures into a customer
/// friendly state instead of exposing storage or backend details.
class CatalogProductImage extends ConsumerWidget {
  const CatalogProductImage({
    required this.imagePath,
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 16,
    this.compact = false,
  });

  final String? imagePath;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = imagePath?.trim();
    if (path == null || path.isEmpty) {
      return _CatalogImageState(
        width: width,
        height: height,
        borderRadius: borderRadius,
        message: 'Chưa có ảnh',
        compact: compact,
      );
    }

    final image = ref.watch(productImageProvider(path));
    if (image.isLoading) {
      return _CatalogImageState(
        width: width,
        height: height,
        borderRadius: borderRadius,
        loading: true,
        compact: compact,
      );
    }

    final url = image.asData?.value?.trim();
    if (image.hasError || url == null || url.isEmpty) {
      return _CatalogImageState(
        width: width,
        height: height,
        borderRadius: borderRadius,
        message: 'Không tải được ảnh',
        compact: compact,
        isError: true,
        onRetry: () => ref.invalidate(productImageProvider(path)),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        semanticLabel: 'Ảnh sản phẩm',
        errorBuilder: (context, error, stackTrace) => _CatalogImageState(
          width: width,
          height: height,
          borderRadius: borderRadius,
          message: 'Không tải được ảnh',
          compact: compact,
          isError: true,
          onRetry: () => ref.invalidate(productImageProvider(path)),
        ),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _CatalogImageState(
            width: width,
            height: height,
            borderRadius: borderRadius,
            loading: true,
            compact: compact,
          );
        },
      ),
    );
  }
}

class _CatalogImageState extends StatelessWidget {
  const _CatalogImageState({
    required this.width,
    required this.height,
    required this.borderRadius,
    this.message,
    this.loading = false,
    this.isError = false,
    this.onRetry,
    this.compact = false,
  });

  final double? width;
  final double? height;
  final double borderRadius;
  final String? message;
  final bool loading;
  final bool isError;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isError
            ? scheme.errorContainer.withValues(alpha: 0.4)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      alignment: Alignment.center,
      child: loading
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            )
          : compact
          ? Semantics(
              image: true,
              label: message,
              child: isError && onRetry != null
                  ? IconButton(
                      tooltip: 'Thử tải lại ảnh',
                      onPressed: onRetry,
                      icon: Icon(
                        Icons.broken_image_outlined,
                        color: scheme.error,
                      ),
                    )
                  : Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isError ? Icons.broken_image_outlined : Icons.image_outlined,
                  color: isError ? scheme.error : scheme.onSurfaceVariant,
                  size: 30,
                ),
                if (message != null) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      message!,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  if (isError && onRetry != null)
                    TextButton(
                      onPressed: onRetry,
                      child: const Text('Thử lại'),
                    ),
                ],
              ],
            ),
    );
  }
}
