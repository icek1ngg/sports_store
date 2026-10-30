import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../cart/presentation/view_models/cart_providers.dart';
import '../../domain/models/product.dart';
import '../../domain/models/product_variant.dart';
import '../view_models/catalog_providers.dart';
import '../widgets/catalog_formatters.dart';
import '../widgets/catalog_image.dart';
import '../widgets/catalog_status.dart';

/// MH05: product selection and adding to the current customer's cart.
/// Neither selection nor cart writes reserve inventory.
class ProductDetailsPage extends ConsumerWidget {
  const ProductDetailsPage({required this.productId, super.key});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productState = ref.watch(productDetailsProvider(productId));
    final imagePath = productState.asData?.value?.imagePath;

    return Scaffold(
      key: const ValueKey('catalog-product-details'),
      appBar: AppBar(
        title: const Text('Chi tiết sản phẩm'),
        actions: [
          IconButton(
            key: const ValueKey('catalog-product-refresh'),
            onPressed: () => _refresh(ref, imagePath),
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            key: const ValueKey('catalog-open-cart'),
            onPressed: () => context.push('/customer/cart'),
            tooltip: 'Giỏ hàng',
            icon: const Icon(Icons.shopping_bag_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(context, ref, productState),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<Product?> productState,
  ) {
    // Check loading before asData so a new account/session never sees the
    // previous account's product snapshot while its request is in flight.
    if (productState.isLoading) {
      return const CatalogLoadingState();
    }
    if (productState.hasError) {
      return CatalogErrorState(
        onRetry: () => ref.invalidate(productDetailsProvider(productId)),
        message: 'Không tải được thông tin sản phẩm. Vui lòng thử lại.',
      );
    }

    final product = productState.asData?.value;
    if (product == null) {
      return const _UnavailableProductState(
        title: 'Sản phẩm không còn khả dụng',
        message: 'Sản phẩm có thể đã được ẩn hoặc không tồn tại.',
      );
    }
    if (product.variants.isEmpty) {
      return _UnavailableProductState(
        title: product.name,
        message: 'Sản phẩm tạm thời không khả dụng.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => _refresh(ref, product.imagePath),
      child: _ProductDetailsContent(product: product),
    );
  }

  Future<void> _refresh(WidgetRef ref, String? imagePath) async {
    final detailProvider = productDetailsProvider(productId);
    ref.invalidate(detailProvider);
    final path = imagePath?.trim();
    if (path != null && path.isNotEmpty) {
      ref.invalidate(productImageProvider(path));
    }
    try {
      await ref.read(detailProvider.future);
    } catch (_) {
      // The page renders the safe error state and retry action after refresh.
    }
  }
}

class _UnavailableProductState extends StatelessWidget {
  const _UnavailableProductState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('catalog-product-unavailable'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Quay lại'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductDetailsContent extends ConsumerStatefulWidget {
  const _ProductDetailsContent({required this.product});

  final Product product;

  @override
  ConsumerState<_ProductDetailsContent> createState() =>
      _ProductDetailsContentState();
}

class _ProductDetailsContentState
    extends ConsumerState<_ProductDetailsContent> {
  late String _selectedVariantId;
  int _quantity = 1;

  int get _selectedVariantIndex {
    final index = widget.product.variants.indexWhere(
      (variant) => variant.id == _selectedVariantId,
    );
    return index < 0 ? 0 : index;
  }

  ProductVariant get _selectedVariant =>
      widget.product.variants[_selectedVariantIndex];

  bool get _inStock => _selectedVariant.availableQuantity > 0;

  @override
  void initState() {
    super.initState();
    _selectedVariantId = widget.product.variants.first.id;
    _syncQuantity();
  }

  @override
  void didUpdateWidget(covariant _ProductDetailsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedStillExists = widget.product.variants.any(
      (variant) => variant.id == _selectedVariantId,
    );
    if (!selectedStillExists) {
      _selectedVariantId = widget.product.variants.first.id;
    }
    // A refresh can change stock without changing the selected variant. Clamp
    // the local quantity on every new product snapshot.
    _syncQuantity();
  }

  void _syncQuantity() {
    final available = _selectedVariant.availableQuantity;
    if (available <= 0) {
      _quantity = 0;
      return;
    }
    if (_quantity < 1) _quantity = 1;
    if (_quantity > available) _quantity = available;
  }

  void _selectVariant(int index) {
    if (index == _selectedVariantIndex) return;
    setState(() {
      _selectedVariantId = widget.product.variants[index].id;
      _quantity = widget.product.variants[index].availableQuantity > 0 ? 1 : 0;
    });
  }

  void _decreaseQuantity() {
    if (_quantity <= 1) return;
    setState(() => _quantity--);
  }

  void _increaseQuantity() {
    if (!_inStock || _quantity >= _selectedVariant.availableQuantity) return;
    setState(() => _quantity++);
  }

  Future<void> _addToCart() async {
    final success = await ref
        .read(cartProvider.notifier)
        .addItem(variantId: _selectedVariant.id, quantity: _quantity);
    if (!mounted || !success) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Đã thêm vào giỏ hàng.'),
        action: SnackBarAction(
          label: 'Xem giỏ',
          onPressed: () => context.push('/customer/cart'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final category = product.categoryName.trim();
    final cart = ref.watch(cartProvider);
    final cartData = cart.asData?.value;
    final busy = cartData?.isMutating == true;
    final pending = cartData?.hasPendingMutation == true;

    return SingleChildScrollView(
      key: const ValueKey('catalog-product-details-scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final imageHeight = constraints.maxWidth < 380 ? 230.0 : 300.0;
              return SizedBox(
                width: double.infinity,
                height: imageHeight,
                child: CatalogProductImage(
                  imagePath: product.imagePath,
                  width: double.infinity,
                  height: imageHeight,
                  borderRadius: 22,
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          if (category.isNotEmpty)
            Text(
              category,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            product.name,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (product.description?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Text(
              product.description!.trim(),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Phiên bản',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var index = 0; index < product.variants.length; index++)
                _VariantChoice(
                  key: ValueKey(
                    'catalog-variant-${product.variants[index].id}',
                  ),
                  variant: product.variants[index],
                  index: index,
                  selected: index == _selectedVariantIndex,
                  onSelected: _selectVariant,
                ),
            ],
          ),
          const SizedBox(height: 20),
          _SelectedVariantSummary(
            variant: _selectedVariant,
            quantity: _quantity,
          ),
          const SizedBox(height: 20),
          _QuantityPicker(
            quantity: _quantity,
            availableQuantity: _selectedVariant.availableQuantity,
            onDecrease: _decreaseQuantity,
            onIncrease: _increaseQuantity,
          ),
          const SizedBox(height: 22),
          const Text(
            'Thêm vào giỏ chưa giữ hàng. Giá và tồn được kiểm tra lại khi đặt.',
          ),
          if (cart.hasError || cartData?.mutationError != null) ...[
            const SizedBox(height: 8),
            Text(
              cartData?.mutationError?.message ??
                  'Không tải được giỏ hàng. Vui lòng thử lại.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () {
                      final notifier = ref.read(cartProvider.notifier);
                      if (pending) {
                        notifier.retryPendingMutation();
                      } else {
                        notifier.refresh();
                      }
                    },
              child: Text(
                pending ? 'Thử lại thao tác đang chờ' : 'Tải lại giỏ hàng',
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const ValueKey('catalog-cart-action'),
              onPressed:
                  _inStock &&
                      !cart.isLoading &&
                      !cart.hasError &&
                      !busy &&
                      !pending
                  ? _addToCart
                  : null,
              icon: const Icon(Icons.shopping_bag_outlined),
              label: Text(busy ? 'Đang cập nhật giỏ…' : 'Thêm vào giỏ'),
            ),
          ),
        ],
      ),
    );
  }
}

class _VariantChoice extends StatelessWidget {
  const _VariantChoice({
    required this.variant,
    required this.index,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final ProductVariant variant;
  final int index;
  final bool selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final label = variant.label.trim().isEmpty
        ? 'Phiên bản ${index + 1}'
        : variant.label.trim();
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(index),
      avatar: variant.availableQuantity > 0
          ? null
          : const Icon(Icons.remove_shopping_cart_outlined, size: 18),
    );
  }
}

class _SelectedVariantSummary extends StatelessWidget {
  const _SelectedVariantSummary({
    required this.variant,
    required this.quantity,
  });

  final ProductVariant variant;
  final int quantity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final attributes = variant.attributes.entries
        .where((entry) => entry.value.toString().trim().isNotEmpty)
        .toList(growable: false);

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatVnd(variant.priceVnd),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              variant.availableQuantity > 0
                  ? formatAvailableQuantity(variant.availableQuantity)
                  : 'Tạm hết hàng',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: variant.availableQuantity > 0
                    ? scheme.onSurfaceVariant
                    : scheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tạm tính: ${formatVnd(safeVndTotal(variant.priceVnd, quantity))}',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (attributes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final attribute in attributes)
                    Chip(
                      label: Text(
                        '${formatVariantAttributeLabel(attribute.key)}: ${attribute.value}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuantityPicker extends StatelessWidget {
  const _QuantityPicker({
    required this.quantity,
    required this.availableQuantity,
    required this.onDecrease,
    required this.onIncrease,
  });

  final int quantity;
  final int availableQuantity;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    final inStock = availableQuantity > 0;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(
          'Số lượng',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        IconButton(
          key: const ValueKey('catalog-quantity-decrease'),
          onPressed: inStock && quantity > 1 ? onDecrease : null,
          tooltip: 'Giảm số lượng',
          icon: const Icon(Icons.remove),
        ),
        Container(
          key: const ValueKey('catalog-quantity-value'),
          constraints: const BoxConstraints(minWidth: 38),
          alignment: Alignment.center,
          child: Text(
            '$quantity',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          key: const ValueKey('catalog-quantity-increase'),
          onPressed: inStock && quantity < availableQuantity
              ? onIncrease
              : null,
          tooltip: 'Tăng số lượng',
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
