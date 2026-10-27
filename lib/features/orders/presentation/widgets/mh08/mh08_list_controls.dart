import 'package:flutter/material.dart';

import '../../../domain/models/order_page.dart';
import '../../../domain/models/order_status.dart';
import '../order_notification_theme.dart';
import 'mh08_kpi_strip.dart';
import 'mh08_page_layout.dart';
import 'mh08_search_section.dart';
import 'mh08_status_chips.dart';

/// Controlled MH08 inputs and counts, with no query or authorization state.
class Mh08ListControls extends StatelessWidget {
  const Mh08ListControls({
    required this.searchValue,
    required this.onSearchChanged,
    required this.onClear,
    required this.onStatusSelected,
    required this.page,
    required this.selectedStatus,
    this.searchError,
    super.key,
  });

  final String searchValue;
  final String? searchError;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClear;
  final ValueChanged<OrderStatus?> onStatusSelected;
  final OrderPage? page;
  final OrderStatus? selectedStatus;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Mh08SearchSection(
          value: searchValue,
          onChanged: onSearchChanged,
          onClear: onClear,
          errorText: searchError,
        ),
        if (!Mh08KeyboardVisibility.isVisibleOf(context)) ...[
          const SizedBox(height: 8),
          Mh08KpiStrip(
            pendingCount: page?.statusCounts[OrderStatus.pendingConfirmation],
            shippingCount: page?.statusCounts[OrderStatus.delivering],
          ),
        ],
        const SizedBox(height: 8),
        Mh08StatusChips(
          leading: Mh08KeyboardVisibility.isVisibleOf(context)
              ? null
              : Text(
                  page == null
                      ? 'Đang cập nhật số lượng đơn'
                      : '${page!.totalCount} đơn hàng',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: OrderNotificationTheme.muted),
                ),
          selectedStatus: selectedStatus,
          counts: page?.statusCounts,
          onSelected: onStatusSelected,
        ),
      ],
    ),
  );
}
