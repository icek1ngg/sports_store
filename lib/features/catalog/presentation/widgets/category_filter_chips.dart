import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/category.dart';

class CategoryFilterChips extends StatelessWidget {
  const CategoryFilterChips({
    required this.categories,
    required this.selectedCategoryId,
    required this.onSelected,
    this.onRetry,
    super.key,
  });

  final AsyncValue<List<Category>> categories;
  final String? selectedCategoryId;
  final ValueChanged<String?> onSelected;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (categories.isLoading) {
      return const SizedBox(
        height: 52,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (categories.hasError) {
      return SizedBox(
        height: 52,
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Không tải được danh mục.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Thử lại')),
          ],
        ),
      );
    }

    final values = [...?categories.asData?.value];
    int rank(Category category) => switch (category.code) {
      'shoes' => 0,
      'apparel' => 1,
      'equipment' => 2,
      _ => 3,
    };
    values.sort((a, b) => rank(a).compareTo(rank(b)));
    return SizedBox(
      height: MediaQuery.textScalerOf(context).scale(14) + 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _CategoryChip(
            key: const ValueKey('catalog-category-all'),
            label: 'TẤT CẢ',
            selected: selectedCategoryId == null,
            onSelected: () => onSelected(null),
          ),
          for (final category in values) ...[
            const SizedBox(width: 8),
            _CategoryChip(
              key: ValueKey('catalog-category-${category.id}'),
              label: category.name.toUpperCase(),
              selected: selectedCategoryId == category.id,
              onSelected: () => onSelected(category.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      backgroundColor: const Color(0xfff5f5f5),
      selectedColor: const Color(0xff111111),
      color: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? const Color(0xff111111)
            : const Color(0xfff5f5f5),
      ),
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: selected ? Colors.white : const Color(0xff111111),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
    );
  }
}
