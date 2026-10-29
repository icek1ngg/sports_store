import 'package:flutter/material.dart';

import '../order_notification_theme.dart';

/// The two server-authoritative operational counts shown above the feed.
class Mh08KpiStrip extends StatelessWidget {
  const Mh08KpiStrip({this.pendingCount, this.shippingCount, super.key});

  final int? pendingCount;
  final int? shippingCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _Mh08KpiPanel(
            label: 'Chờ xác nhận',
            caption: 'Cần xử lý ngay',
            count: pendingCount,
            emphasized: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Mh08KpiPanel(
            label: 'Đang giao',
            caption: 'Trên đường đi',
            count: shippingCount,
          ),
        ),
      ],
    );
  }
}

class _Mh08KpiPanel extends StatelessWidget {
  const _Mh08KpiPanel({
    required this.label,
    required this.caption,
    required this.count,
    this.emphasized = false,
  });

  final String label;
  final String caption;
  final int? count;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final foreground = emphasized ? Colors.white : OrderNotificationTheme.ink;
    final mutedForeground = emphasized
        ? Colors.white70
        : OrderNotificationTheme.muted;
    final textTheme = Theme.of(context).textTheme;
    final captionStyle = textTheme.bodySmall?.copyWith(
      color: mutedForeground,
      fontSize: 11,
      height: 14 / 11,
    );

    return Container(
      constraints: const BoxConstraints(minHeight: 81),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: emphasized
            ? OrderNotificationTheme.ink
            : OrderNotificationTheme.cloud,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: captionStyle),
          const SizedBox(height: 4),
          Semantics(
            key: ValueKey('mh08-kpi-value-$label'),
            container: true,
            excludeSemantics: true,
            label: count == null ? '$label: Chưa có dữ liệu' : '$label: $count',
            child: Text(
              count?.toString() ?? '—',
              style: textTheme.headlineSmall?.copyWith(
                fontFamily: 'BarlowCondensed',
                fontSize: 28,
                height: 1,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(caption, style: captionStyle),
        ],
      ),
    );
  }
}
