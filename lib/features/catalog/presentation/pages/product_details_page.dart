import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/storefront_theme.dart';
import '../../../cart/domain/models/cart_failure.dart';
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

  static void _backToCatalog(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router == null) {
      Navigator.maybePop(context);
    } else if (router.canPop()) {
      router.pop();
    } else {
      router.go('/customer/products');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productState = ref.watch(productDetailsProvider(productId));
    final imagePath = productState.asData?.value?.imagePath;
    final cart = ref.watch(cartProvider);
    final cartQuantity = cart.isLoading || cart.hasError
        ? 0
        : cart.asData?.value.totalQuantity ?? 0;

    return StorefrontTheme(
      child: Scaffold(
        key: const ValueKey('catalog-product-details'),
        appBar: AppBar(
          leading: BackButton(onPressed: () => _backToCatalog(context)),
          title: const Text(
            'CHI TIẾT SẢN PHẨM',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
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
              icon: Badge(
                isLabelVisible: cartQuantity > 0,
                label: Text(cartQuantity > 99 ? '99+' : '$cartQuantity'),
                backgroundColor: StorefrontTheme.ink,
                child: const Icon(Icons.shopping_bag_outlined),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: _buildBody(context, ref, productState),
      ),
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
    final product = ref.read(detailProvider).asData?.value;
    final imagePaths = <String>{
      if (imagePath?.trim().isNotEmpty == true) imagePath!.trim(),
      for (final variant in product?.variants ?? <ProductVariant>[])
        ...variant.imagePaths,
    };
    ref.invalidate(detailProvider);
    for (final path in imagePaths) {
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
              onPressed: () => ProductDetailsPage._backToCatalog(context),
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

  ProductVariant get _initialVariant => widget.product.variants.firstWhere(
    (variant) => variant.isInStock,
    orElse: () => widget.product.variants.first,
  );

  bool get _inStock => _selectedVariant.availableQuantity > 0;

  @override
  void initState() {
    super.initState();
    _selectedVariantId = _initialVariant.id;
    _syncQuantity();
  }

  @override
  void didUpdateWidget(covariant _ProductDetailsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedStillExists = widget.product.variants.any(
      (variant) => variant.id == _selectedVariantId,
    );
    if (!selectedStillExists) {
      _selectedVariantId = _initialVariant.id;
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

  String? _attribute(ProductVariant variant, List<String> names) {
    for (final name in names) {
      final value = variant.attributes[name];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  String? _rawColor(ProductVariant variant) =>
      variant.color ?? _attribute(variant, const ['Màu', 'màu']);

  String? _color(ProductVariant variant) {
    final color = _rawColor(variant);
    if (color != null) return color;
    // Manager-created legacy variants remain selectable alongside new colors.
    return widget.product.variants.any((v) => _rawColor(v) != null)
        ? 'Phiên bản khác'
        : null;
  }

  String? _size(ProductVariant variant) =>
      variant.size ?? _attribute(variant, const ['Cỡ', 'cỡ']);

  List<String> get _colors =>
      widget.product.variants.map(_color).whereType<String>().toSet().toList();

  List<ProductVariant> get _colorVariants {
    final variants = widget.product.variants
        .where((variant) => _color(variant) == _color(_selectedVariant))
        .toList();
    const clothingOrder = {
      'XXS': 0,
      'XS': 1,
      'S': 2,
      'M': 3,
      'L': 4,
      'XL': 5,
      'XXL': 6,
      '2XL': 6,
      'XXXL': 7,
      '3XL': 7,
      '4XL': 8,
    };
    // Preserve repository order for legacy variants without recognizable sizes.
    num? rank(ProductVariant variant) {
      final size = _size(variant)?.toUpperCase();
      return size == null ? null : num.tryParse(size) ?? clothingOrder[size];
    }

    if (variants.every((variant) => rank(variant) != null)) {
      variants.sort((left, right) {
        final comparison = rank(left)!.compareTo(rank(right)!);
        return comparison != 0 ? comparison : left.id.compareTo(right.id);
      });
    }
    return variants;
  }

  List<String> get _images {
    final images = _selectedVariant.imagePaths;
    if (images.isNotEmpty) return images;
    final path = widget.product.imagePath?.trim();
    return path == null || path.isEmpty ? const [] : [path];
  }

  bool get _hasColorImage => _selectedVariant.imagePaths.isNotEmpty;

  void _selectVariant(ProductVariant variant) {
    if (variant.id == _selectedVariantId) return;
    setState(() {
      _selectedVariantId = variant.id;
      _quantity = variant.availableQuantity > 0 ? 1 : 0;
    });
  }

  void _selectColor(String color) {
    final variants = widget.product.variants
        .where((variant) => _color(variant) == color)
        .toList();
    final previousSize = _size(_selectedVariant);
    final matching = variants.where(
      (variant) => _size(variant) == previousSize,
    );
    final available = variants.where((variant) => variant.isInStock);
    _selectVariant(
      matching.isNotEmpty
          ? matching.first
          : available.isNotEmpty
          ? available.first
          : variants.first,
    );
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
    final colors = _colors;
    final selectedColor = _color(_selectedVariant);
    final cart = ref.watch(cartProvider);
    final cartData = cart.asData?.value;
    final loadError = cart.error;
    final busy = cartData?.isMutating == true;
    final pending = cartData?.hasPendingMutation == true;
    final scheme = Theme.of(context).colorScheme;
    final variants = colors.isEmpty ? product.variants : _colorVariants;
    final hasSizes = variants.any((variant) => _size(variant) != null);
    final canAdd =
        _inStock && !cart.isLoading && !cart.hasError && !busy && !pending;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            key: const ValueKey('catalog-product-details-scroll'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'STRIDE // PERFORMANCE',
                        style: TextStyle(
                          fontFamily: 'BarlowCondensed',
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                          letterSpacing: .5,
                        ),
                      ),
                    ),
                    _ProductGallery(
                      key: ValueKey('gallery-${_images.join('|')}'),
                      images: _images,
                    ),
                    if (_hasColorImage &&
                        _selectedVariant.attributes['image_source'] ==
                            'ai_color_preview')
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Ảnh phối màu minh họa bằng AI.',
                          key: const ValueKey('catalog-color-image-note'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    if (colors.isNotEmpty && !_hasColorImage)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Ảnh mẫu sản phẩm; màu $selectedColor chưa có ảnh riêng.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    const SizedBox(height: 20),
                    if (product.categoryName.trim().isNotEmpty)
                      Text(
                        product.categoryName.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: StorefrontTheme.muted,
                          letterSpacing: 1,
                        ),
                      ),
                    const SizedBox(height: 5),
                    Text(
                      product.name,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      formatVnd(_selectedVariant.priceVnd),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (product.description?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 10),
                      Text(
                        product.description!.trim(),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(),
                    ),
                    if (colors.isNotEmpty) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          const Text(
                            'MÀU SẮC',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            '— $selectedColor',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            '(${colors.length} màu)',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final largeText =
                              MediaQuery.textScalerOf(context).scale(14) > 22;
                          final width = largeText
                              ? constraints.maxWidth
                              : (constraints.maxWidth - 8) / 2;
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final color in colors)
                                SizedBox(
                                  width: width,
                                  child: _ColorChoice(
                                    key: ValueKey('catalog-color-$color'),
                                    color: color,
                                    selected: color == selectedColor,
                                    hex: product.variants
                                        .firstWhere((v) => _color(v) == color)
                                        .colorHex,
                                    onTap: () => _selectColor(color),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                    ],
                    Text(
                      hasSizes ? 'KÍCH CỠ' : 'PHIÊN BẢN',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final variant in variants)
                          ChoiceChip(
                            key: ValueKey('catalog-variant-${variant.id}'),
                            showCheckmark: false,
                            selected: variant.id == _selectedVariantId,
                            selectedColor: scheme.primary,
                            backgroundColor: StorefrontTheme.cloud,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(3),
                            ),
                            side: BorderSide.none,
                            label: Text(
                              _size(variant) ?? variant.label,
                              style: TextStyle(
                                color: variant.id == _selectedVariantId
                                    ? scheme.onPrimary
                                    : variant.isInStock
                                    ? scheme.onSurface
                                    : scheme.outline,
                                fontWeight: FontWeight.w700,
                                decoration: variant.isInStock
                                    ? null
                                    : TextDecoration.lineThrough,
                              ),
                            ),
                            tooltip: variant.isInStock
                                ? variant.label
                                : '${variant.label} — hết hàng',
                            onSelected: (_) => _selectVariant(variant),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 7,
                          color: _inStock
                              ? StorefrontTheme.success
                              : scheme.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _inStock
                                ? formatAvailableQuantity(
                                    _selectedVariant.availableQuantity,
                                  )
                                : 'Tạm hết hàng',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: _inStock
                                      ? StorefrontTheme.success
                                      : scheme.error,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _QuantityPicker(
                      quantity: _quantity,
                      availableQuantity: _selectedVariant.availableQuantity,
                      onDecrease: _decreaseQuantity,
                      onIncrease: _increaseQuantity,
                    ),
                    const SizedBox(height: 18),
                    const _DeliveryNote(),
                    const SizedBox(height: 14),
                    Text(
                      'Thêm vào giỏ chưa giữ hàng. Giá và tồn được kiểm tra lại khi đặt.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (cart.hasError || cartData?.mutationError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        cartData?.mutationError?.message ??
                            (loadError is CartFailure
                                ? loadError.loadMessage
                                : 'Không tải được giỏ hàng. Vui lòng thử lại.'),
                        style: TextStyle(color: scheme.error),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () {
                                final notifier = ref.read(
                                  cartProvider.notifier,
                                );
                                if (pending) {
                                  notifier.retryPendingMutation();
                                } else {
                                  notifier.refresh();
                                }
                              },
                        child: Text(
                          pending
                              ? 'Thử lại thao tác đang chờ'
                              : 'Tải lại giỏ hàng',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const ValueKey('catalog-cart-action'),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                        disabledBackgroundColor: scheme.surfaceContainerHighest,
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 12,
                        ),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: canAdd ? _addToCart : null,
                      icon: const Icon(Icons.shopping_bag_outlined, size: 20),
                      label: Text(
                        busy
                            ? 'Đang cập nhật giỏ…'
                            : !_inStock
                            ? 'Tạm hết hàng'
                            : 'Thêm vào giỏ • ${formatVnd(safeVndTotal(_selectedVariant.priceVnd, _quantity))}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProductGallery extends StatefulWidget {
  const _ProductGallery({required this.images, super.key});
  final List<String> images;
  @override
  State<_ProductGallery> createState() => _ProductGalleryState();
}

class _ProductGalleryState extends State<_ProductGallery> {
  int _index = 0;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1.12,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: ColoredBox(
              color: StorefrontTheme.cloud,
              child: widget.images.isEmpty
                  ? const CatalogProductImage(imagePath: null)
                  : PageView.builder(
                      onPageChanged: (index) => setState(() => _index = index),
                      itemCount: widget.images.length,
                      itemBuilder: (context, index) => CatalogProductImage(
                        key: ValueKey(
                          'catalog-detail-image-${widget.images[index]}',
                        ),
                        imagePath: widget.images[index],
                        fit: BoxFit.contain,
                        borderRadius: 4,
                      ),
                    ),
            ),
          ),
        ),
        if (widget.images.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              alignment: WrapAlignment.center,
              runSpacing: 6,
              children: List.generate(
                widget.images.length,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: index == _index ? 18 : 6,
                  height: 5,
                  decoration: BoxDecoration(
                    color: index == _index
                        ? StorefrontTheme.ink
                        : const Color(0xffcccccc),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.color,
    required this.selected,
    required this.onTap,
    this.hex,
    super.key,
  });
  final String color;
  final bool selected;
  final VoidCallback onTap;
  final String? hex;

  Color get _swatch {
    final parsed = int.tryParse((hex ?? '').replaceFirst('#', ''), radix: 16);
    if (parsed != null && (hex!.replaceFirst('#', '').length == 6)) {
      return Color(0xff000000 | parsed);
    }
    final name = color.toLowerCase();
    if (name.contains('đen')) return const Color(0xff171717);
    if (name.contains('cam')) return const Color(0xfffc6c21);
    if (name.contains('đỏ')) return const Color(0xffdf3535);
    if (name.contains('navy')) return const Color(0xff20324e);
    if (name.contains('ngọc')) return const Color(0xff20c7b0);
    if (name.contains('xanh')) return const Color(0xff299ada);
    if (name.contains('trắng')) return Colors.white;
    return const Color(0xffa4a5a9);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? scheme.primary : StorefrontTheme.cloud,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: _swatch,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xffc6c6c6)),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  color,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected ? scheme.onPrimary : scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
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
    return Container(
      color: StorefrontTheme.cloud,
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          const Text('Số lượng', style: TextStyle(fontWeight: FontWeight.w700)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const ValueKey('catalog-quantity-decrease'),
                onPressed: quantity > 1 && availableQuantity > 0
                    ? onDecrease
                    : null,
                tooltip: 'Giảm số lượng',
                icon: const Icon(Icons.remove, size: 18),
              ),
              Container(
                key: const ValueKey('catalog-quantity-value'),
                constraints: const BoxConstraints(minWidth: 32),
                alignment: Alignment.center,
                child: Text(
                  '$quantity',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                key: const ValueKey('catalog-quantity-increase'),
                onPressed: quantity < availableQuantity && availableQuantity > 0
                    ? onIncrease
                    : null,
                tooltip: 'Tăng số lượng',
                icon: const Icon(Icons.add, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeliveryNote extends StatelessWidget {
  const _DeliveryNote();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.local_shipping_outlined, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Giao hàng COD tại Hà Nội',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
                SizedBox(height: 3),
                Text(
                  'Phí giao hàng cố định 30.000 đ.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
