import 'package:flutter/material.dart';

import '../../../../../core/utils/display_formatters.dart';
import '../../../domain/models/order_status.dart';
import '../order_notification_theme.dart';

/// Horizontal, parent-controlled filtering for every order lifecycle state.
class Mh08StatusChips extends StatelessWidget {
  const Mh08StatusChips({
    this.selectedStatus,
    this.counts,
    this.onSelected,
    this.leading,
    super.key,
  });

  final OrderStatus? selectedStatus;
  final Map<OrderStatus, int>? counts;
  final ValueChanged<OrderStatus?>? onSelected;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final allCount = counts?.values.fold<int>(0, (sum, count) => sum + count);

    return SingleChildScrollView(
      key: const ValueKey('mh08-status-chips-scroll'),
      scrollDirection: Axis.horizontal,
      primary: false,
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          _buildChip(
            context,
            label: 'Tất cả',
            count: allCount,
            selected: selectedStatus == null,
            onPressed: onSelected == null ? null : () => onSelected!(null),
          ),
          for (final status in OrderStatus.values)
            _buildChip(
              context,
              label: orderStatusLabel(status),
              count: counts?[status],
              selected: selectedStatus == status,
              onPressed: onSelected == null
                  ? null
                  : () => onSelected!(selectedStatus == status ? null : status),
            ),
        ],
      ),
    );
  }

  Widget _buildChip(
    BuildContext context, {
    required String label,
    required int? count,
    required bool selected,
    required VoidCallback? onPressed,
  }) {
    final foreground = selected ? Colors.white : OrderNotificationTheme.muted;
    final labelChildren = <Widget>[
      Text(
        label,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: foreground, letterSpacing: .24),
      ),
      if (count != null) ...[
        const SizedBox(width: 6),
        Container(
          constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? Colors.white24
                : OrderNotificationTheme.ink.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: foreground, height: 1),
          ),
        ),
      ],
    ];

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: FilterChip(
        selected: selected,
        onSelected: onPressed == null ? null : (_) => onPressed(),
        materialTapTargetSize: MaterialTapTargetSize.padded,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        label: Row(mainAxisSize: MainAxisSize.min, children: labelChildren),
        labelStyle: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: foreground),
        backgroundColor: OrderNotificationTheme.cloud,
        selectedColor: OrderNotificationTheme.ink,
        disabledColor: selected
            ? OrderNotificationTheme.ink
            : OrderNotificationTheme.cloud,
        side: BorderSide.none,
        showCheckmark: false,
      ),
    );
  }
}
