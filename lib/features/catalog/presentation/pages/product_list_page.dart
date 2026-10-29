import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/catalog_page.dart';
import '../../domain/models/catalog_query.dart';
import '../../domain/models/product.dart';
import '../view_models/catalog_providers.dart';
import '../widgets/catalog_status.dart';
import '../widgets/category_filter_chips.dart';
import '../widgets/product_card.dart';

/// MH04: the customer-facing catalog list.
class ProductListPage extends ConsumerStatefulWidget {
  const ProductListPage({super.key});

  @override
  ConsumerState<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends ConsumerState<ProductListPage> {
  late final TextEditingController _searchController;
  String? _lastAppliedQuerySearch;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _submitSearch(String value) {
    FocusManager.instance.primaryFocus?.unfocus();
    ref.read(catalogQueryProvider.notifier).setSearch(value.trim());
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {});
    _submitSearch('');
  }

  Future<void> _refreshCatalog() async {
    // Refreshing both streams keeps the category selector and products from
    // presenting different account/session snapshots.
    ref.invalidate(productImageProvider);
    try {
      await Future.wait<void>([
        ref.refresh(catalogPageProvider.future),
        ref.refresh(catalogCategoriesProvider.future),
      ]);
    } catch (_) {
      // The error state renders the safe retry message. RefreshIndicator still
      // completes its gesture even when the backend is unavailable.
    }
  }

  void _retryProducts() {
    ref.invalidate(productImageProvider);
    ref.invalidate(catalogPageProvider);
  }

  void _retryCategories() {
    ref.invalidate(catalogCategoriesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(catalogQueryProvider);
    final categories = ref.watch(catalogCategoriesProvider);
    final page = ref.watch(catalogPageProvider);

    // Only reconcile when the query itself changed (for example after an
    // account switch). An unrelated category/page rebuild must not erase text
    // the customer has typed but has not submitted yet.
    if (_lastAppliedQuerySearch != query.search) {
      _lastAppliedQuerySearch = query.search;
      _searchController.value = _searchController.value.copyWith(
        text: query.search,
        selection: TextSelection.collapsed(offset: query.search.length),
        composing: TextRange.empty,
      );
    }

    return Scaffold(
      key: const ValueKey('catalog-product-list'),
      appBar: AppBar(
        title: const Text('Sản phẩm'),
        actions: [
          IconButton(
            key: const ValueKey('catalog-open-cart'),
            onPressed: () => context.push('/customer/cart'),
            tooltip: 'Giỏ hàng',
            icon: const Icon(Icons.shopping_bag_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: TextField(
                key: const ValueKey('catalog-search-field'),
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                onSubmitted: _submitSearch,
                decoration: InputDecoration(
                  hintText: 'Tìm sản phẩm thể thao',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          key: const ValueKey('catalog-search-clear'),
                          tooltip: 'Xóa tìm kiếm',
                          onPressed: _clearSearch,
                          icon: const Icon(Icons.clear),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  filled: true,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
              child: CategoryFilterChips(
                categories: categories,
                selectedCategoryId: query.categoryId,
                onSelected: (categoryId) => ref
                    .read(catalogQueryProvider.notifier)
                    .setCategory(categoryId),
                onRetry: _retryCategories,
              ),
            ),
            Expanded(
              child: _CatalogResults(
                page: page,
                query: query,
                onRefresh: _refreshCatalog,
                onRetry: _retryProducts,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogResults extends ConsumerWidget {
  const _CatalogResults({
    required this.page,
    required this.query,
    required this.onRefresh,
    required this.onRetry,
  });

  final AsyncValue<CatalogPage> page;
  final CatalogQuery query;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (page.isLoading) {
      return const CatalogLoadingState();
    }
    if (page.hasError) {
      return CatalogErrorState(onRetry: onRetry);
    }

    final data = page.asData?.value;
    if (data == null) {
      return const CatalogLoadingState();
    }
    if (data.products.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          key: const ValueKey('catalog-products-empty-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 160),
            const CatalogEmptyState(),
            if (query.page > 0)
              _CatalogPagination(
                query: query,
                hasMore: false,
                isLoading: false,
              ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        key: const ValueKey('catalog-products-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.crossAxisExtent;
                final columns = width >= 760
                    ? 4
                    : width >= 540
                    ? 3
                    : width >= 360
                    ? 2
                    : 1;
                if (columns == 1) {
                  return SliverList.builder(
                    itemCount: data.products.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildProductCard(
                        context,
                        ref,
                        data.products[index],
                      ),
                    ),
                  );
                }
                return SliverGrid.builder(
                  itemCount: data.products.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    // Leave room for the user's text scale up to 2.0.
                    mainAxisExtent:
                        (width - 12 * (columns - 1)) / columns / 1.12 +
                        80 +
                        MediaQuery.textScalerOf(context).scale(115),
                  ),
                  itemBuilder: (context, index) {
                    return _buildProductCard(
                      context,
                      ref,
                      data.products[index],
                    );
                  },
                );
              },
            ),
          ),
          if (data.hasMore || query.page > 0)
            SliverToBoxAdapter(
              child: _CatalogPagination(
                query: query,
                hasMore: data.hasMore,
                isLoading: page.isLoading,
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 20)),
        ],
      ),
    );
  }

  Widget _buildProductCard(
    BuildContext context,
    WidgetRef ref,
    Product product,
  ) {
    return ProductCard(
      key: ValueKey('catalog-product-${product.id}'),
      product: product,
      onTap: product.id.isEmpty
          ? null
          : () async {
              await context.push(
                '/customer/products/${Uri.encodeComponent(product.id)}',
              );
              if (!context.mounted) return;
              ref.invalidate(productImageProvider);
              ref.invalidate(catalogPageProvider);
            },
    );
  }
}

class _CatalogPagination extends ConsumerWidget {
  const _CatalogPagination({
    required this.query,
    required this.hasMore,
    required this.isLoading,
  });

  final CatalogQuery query;
  final bool hasMore;
  final bool isLoading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canGoBack = query.page > 0;
    final canGoForward = hasMore;
    if (!canGoBack && !canGoForward) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('catalog-page-previous'),
            onPressed: !isLoading && canGoBack
                ? () => ref.read(catalogQueryProvider.notifier).previousPage()
                : null,
            icon: const Icon(Icons.chevron_left),
            label: const Text('Trước'),
          ),
          Text(
            'Trang ${query.page + 1}',
            semanticsLabel: 'Trang ${query.page + 1}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          OutlinedButton.icon(
            key: const ValueKey('catalog-page-next'),
            onPressed: !isLoading && canGoForward
                ? () => ref.read(catalogQueryProvider.notifier).nextPage()
                : null,
            icon: const Icon(Icons.chevron_right),
            label: const Text('Sau'),
          ),
        ],
      ),
    );
  }
}
