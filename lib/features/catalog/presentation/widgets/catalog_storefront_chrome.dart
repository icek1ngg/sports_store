import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/storefront_theme.dart';
import '../../../cart/presentation/view_models/cart_providers.dart';
import '../../domain/models/catalog_query.dart';
import '../view_models/catalog_providers.dart';

String catalogSortLabel(CatalogSort sort) => switch (sort) {
  CatalogSort.nameAscending => 'Tên A–Z',
  CatalogSort.nameDescending => 'Tên Z–A',
  CatalogSort.newest => 'Mới nhất',
};

class CatalogStorefrontHeader extends ConsumerWidget {
  const CatalogStorefrontHeader({required this.onSearch, super.key});
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final quantity = cart.isLoading || cart.hasError
        ? 0
        : cart.asData?.value.totalQuantity ?? 0;
    return Column(
      children: [
        Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xffeeeeee))),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          height: 60,
          child: Row(
            children: [
              const Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 88,
                    height: 32,
                    child: FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'STRIDE',
                        style: TextStyle(
                          fontFamily: 'BarlowCondensed',
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Tìm sản phẩm',
                onPressed: onSearch,
                icon: const Icon(Icons.search, size: 21),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 17,
                backgroundColor: StorefrontTheme.ink,
                child: Icon(
                  Icons.directions_run,
                  color: Colors.white,
                  size: 21,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 100,
                    height: 34,
                    child: FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'STRIDE',
                        style: TextStyle(
                          fontFamily: 'BarlowCondensed',
                          fontSize: 25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Badge(
                isLabelVisible: quantity > 0,
                label: Text(quantity > 99 ? '99+' : '$quantity'),
                backgroundColor: StorefrontTheme.ink,
                child: IconButton.filledTonal(
                  key: const ValueKey('catalog-open-cart'),
                  tooltip: 'Giỏ hàng',
                  style: IconButton.styleFrom(
                    backgroundColor: StorefrontTheme.cloud,
                  ),
                  onPressed: () => context.push('/customer/cart'),
                  icon: const Icon(Icons.shopping_bag_outlined, size: 22),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class CatalogCollectionHeading extends ConsumerWidget {
  const CatalogCollectionHeading({
    required this.count,
    required this.query,
    super.key,
  });
  final int count;
  final CatalogQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                'BỘ SƯU TẬP',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontSize: 29),
              ),
            ),
            const SizedBox(width: 7),
            Tooltip(
              message: '$count sản phẩm trên trang',
              child: Text(
                '($count)',
                style: const TextStyle(
                  fontSize: 12,
                  color: StorefrontTheme.muted,
                ),
              ),
            ),
          ],
        ),
        PopupMenuButton<CatalogSort>(
          key: const ValueKey('catalog-sort'),
          tooltip: 'Sắp xếp sản phẩm',
          initialValue: query.sort,
          onSelected: (sort) => ref
              .read(catalogQueryProvider.notifier)
              .setOptions(sort: sort, inStockOnly: query.inStockOnly),
          itemBuilder: (_) => [
            for (final sort in CatalogSort.values)
              CheckedPopupMenuItem(
                value: sort,
                checked: query.sort == sort,
                child: Text(catalogSortLabel(sort)),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.swap_vert, size: 16),
                const SizedBox(width: 4),
                Text(
                  catalogSortLabel(query.sort),
                  style: const TextStyle(
                    fontSize: 11,
                    color: StorefrontTheme.muted,
                  ),
                ),
                const Icon(Icons.expand_more, size: 15),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class CatalogMovementCard extends StatelessWidget {
  const CatalogMovementCard({required this.onExplore, super.key});
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('catalog-movement-card'),
    margin: const EdgeInsets.fromLTRB(20, 24, 20, 30),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xffe8e8e8)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      children: [
        const CircleAvatar(
          radius: 23,
          backgroundColor: StorefrontTheme.cloud,
          child: Icon(Icons.bolt, color: Color(0xff4651c5), size: 27),
        ),
        const SizedBox(height: 14),
        Text(
          'BỨT PHÁ MỌI GIỚI HẠN',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Sẵn sàng cho buổi tập tiếp theo.\nKhám phá giày, quần áo và dụng cụ thể thao.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: StorefrontTheme.muted,
            fontSize: 12,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onExplore,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    'Khám phá bộ sưu tập',
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(width: 10),
                Icon(Icons.arrow_forward, size: 17),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Giao COD tại Hà Nội · Phí 30.000 đ',
          textAlign: TextAlign.center,
          style: TextStyle(color: StorefrontTheme.muted, fontSize: 10),
        ),
      ],
    ),
  );
}

Future<void> showCatalogFilters(
  BuildContext context,
  WidgetRef ref,
  CatalogQuery query,
) async {
  var sort = query.sort;
  var stock = query.inStockOnly;
  final result = await showModalBottomSheet<({CatalogSort sort, bool stock})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StorefrontTheme(
      child: StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bộ lọc sản phẩm',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 18),
                const Text(
                  'SẮP XẾP',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in CatalogSort.values)
                      ChoiceChip(
                        label: Text(catalogSortLabel(option)),
                        selected: sort == option,
                        onSelected: (_) => setState(() => sort = option),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  key: const ValueKey('catalog-filter-in-stock'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Chỉ hiện sản phẩm còn hàng'),
                  subtitle: const Text('Theo tồn khả dụng của biến thể'),
                  value: stock,
                  onChanged: (value) => setState(() => stock = value),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() {
                          sort = CatalogSort.nameAscending;
                          stock = false;
                        }),
                        child: const Text('Đặt lại'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('catalog-filter-apply'),
                        onPressed: () =>
                            Navigator.pop(context, (sort: sort, stock: stock)),
                        child: const Text('Áp dụng'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  if (result != null && context.mounted) {
    ref
        .read(catalogQueryProvider.notifier)
        .setOptions(sort: result.sort, inStockOnly: result.stock);
  }
}
