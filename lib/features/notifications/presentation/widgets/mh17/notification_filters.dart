import 'package:flutter/material.dart';

import '../../../domain/models/notification_query.dart';

/// Controlled filter controls; the parent owns querying and refresh state.
class Mh17NotificationFilters extends StatelessWidget {
  const Mh17NotificationFilters({
    this.selectedFilter = NotificationFilter.all,
    this.onFilterChanged,
    this.onRefresh,
    this.isRefreshing = false,
    super.key,
  });

  final NotificationFilter selectedFilter;
  final ValueChanged<NotificationFilter>? onFilterChanged;
  final VoidCallback? onRefresh;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final filter in NotificationFilter.values)
              ChoiceChip(
                label: Text(
                  filter == NotificationFilter.all ? 'Tất cả' : 'Chưa đọc',
                ),
                selected: selectedFilter == filter,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                visualDensity: VisualDensity.standard,
                onSelected: onFilterChanged == null
                    ? null
                    : (_) => onFilterChanged!(filter),
              ),
            IconButton(
              tooltip: isRefreshing ? 'Đang làm mới' : 'Làm mới',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              visualDensity: VisualDensity.standard,
              onPressed: isRefreshing ? null : onRefresh,
              icon: isRefreshing
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }
}
