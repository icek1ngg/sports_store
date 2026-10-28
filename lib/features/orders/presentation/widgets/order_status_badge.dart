import 'package:flutter/material.dart';

import '../../../../core/utils/display_formatters.dart';
import '../../domain/models/order_status.dart';

/// A text-first order badge. Colour reinforces the lifecycle label but never
/// carries the only meaning of a status.
class OrderStatusBadge extends StatelessWidget {
  const OrderStatusBadge({required this.status, super.key});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tone = _toneFor(status);
    final background = switch (tone) {
      _StatusTone.info => colors.primaryContainer,
      _StatusTone.progress => colors.secondaryContainer,
      _StatusTone.success => colors.tertiaryContainer,
      _StatusTone.warning => colors.errorContainer,
      _StatusTone.neutral => colors.surfaceContainerHighest,
    };
    final foreground = switch (tone) {
      _StatusTone.info => colors.onPrimaryContainer,
      _StatusTone.progress => colors.onSecondaryContainer,
      _StatusTone.success => colors.onTertiaryContainer,
      _StatusTone.warning => colors.onErrorContainer,
      _StatusTone.neutral => colors.onSurfaceVariant,
    };
    final label = orderStatusLabel(status);

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: 'Trạng thái đơn: $label',
      child: Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  _StatusTone _toneFor(OrderStatus status) {
    return switch (status) {
      OrderStatus.pendingConfirmation => _StatusTone.info,
      OrderStatus.preparing ||
      OrderStatus.awaitingPickup => _StatusTone.progress,
      OrderStatus.delivering ||
      OrderStatus.awaitingRedelivery => _StatusTone.progress,
      OrderStatus.delivered => _StatusTone.success,
      OrderStatus.cancelled || OrderStatus.rejected => _StatusTone.neutral,
      OrderStatus.awaitingStoreReturn ||
      OrderStatus.undeliverableReturned => _StatusTone.warning,
    };
  }
}

enum _StatusTone { info, progress, success, warning, neutral }
