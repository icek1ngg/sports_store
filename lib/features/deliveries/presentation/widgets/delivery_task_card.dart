import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';

import '../../domain/models/delivery_task.dart';

/// A compact, read-only MH10 task summary.
///
/// This card deliberately renders only fields returned by the delivery task
/// projection. Historical or restricted snapshots therefore show a bounded
/// message instead of trying to reconstruct recipient/order data from another
/// table.
class DeliveryTaskCard extends StatelessWidget {
  const DeliveryTaskCard({required this.task, required this.onTap, super.key});

  final DeliveryTaskSnapshot task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isMasked = task.destination == null;
    final reference = task.orderId ?? task.taskId;

    return Semantics(
      button: true,
      label: 'Xem chi tiết nhiệm vụ $reference',
      child: Card(
        key: ValueKey('delivery-task-${task.taskId}'),
        margin: EdgeInsets.zero,
        elevation: 1,
        shadowColor: scheme.shadow.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.hairlineSoft),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MetaRow(task: task, reference: reference),
                const SizedBox(height: 14),
                _DestinationBlock(task: task, masked: isMasked),
                const SizedBox(height: 14),
                _OperationalSummary(task: task),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Xem chi tiết nhiệm vụ',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      child: const Icon(Icons.chevron_right, size: 20),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.task, required this.reference});

  final DeliveryTaskSnapshot task;
  final String reference;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      runSpacing: 8,
      spacing: 8,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Badge(
              icon: _kindIcon(task.kind),
              label: _kindLabel(task.kind),
              filled: true,
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: SelectableText(
                '#$reference',
                maxLines: 2,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        _Badge(
          icon: _statusIcon(task.status),
          label: _statusLabel(task.status, task.kind),
          filled: false,
        ),
      ],
    );
  }
}

class _DestinationBlock extends StatelessWidget {
  const _DestinationBlock({required this.task, required this.masked});

  final DeliveryTaskSnapshot task;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (masked) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.softCloud,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Thông tin đã được giới hạn cho nhiệm vụ này.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final destination = task.destination!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          destination.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.location_on_outlined, size: 18, color: scheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                destination.address,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OperationalSummary extends StatelessWidget {
  const _OperationalSummary({required this.task});

  final DeliveryTaskSnapshot task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isOutbound = task.kind == DeliveryTaskKind.outbound;
    final isPickup = task.kind == DeliveryTaskKind.returnPickup;
    final amount = task.amountToCollectVnd;
    final details = <Widget>[
      Text(
        isOutbound
            ? 'TIỀN COD THU'
            : isPickup
            ? 'THU HỒI TẠI KHÁCH'
            : 'GIAO LẠI MIỄN PHÍ',
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        isOutbound
            ? amount == null
                  ? 'Thông tin COD được giới hạn'
                  : _formatVnd(amount)
            : isPickup
            ? 'Không thu tiền'
            : 'Không thu COD',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.headlineSmall?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    ];
    if (isOutbound) details.add(const SizedBox(height: 3));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.softCloud,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairlineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...details,
          if (isOutbound) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _Badge(
                icon: Icons.replay_outlined,
                label: 'Lần giao ${task.attemptNumber} / 2',
                filled: false,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.filled});

  final IconData icon;
  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final background = filled ? AppColors.softCloud : AppColors.surface;
    final foreground = filled ? AppColors.ink : AppColors.mute;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.hairlineSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: foreground),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatVnd(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final groups = <String>[];
  for (var end = digits.length; end > 0;) {
    final start = (end - 3).clamp(0, end);
    groups.insert(0, digits.substring(start, end));
    end = start;
  }
  return '${negative ? '-' : ''}${groups.join('.')} đ';
}

String _kindLabel(DeliveryTaskKind kind) => switch (kind) {
  DeliveryTaskKind.outbound => 'GIAO HÀNG',
  DeliveryTaskKind.returnPickup => 'THU HỒI HÀNG',
  DeliveryTaskKind.redelivery => 'GIAO LẠI MIỄN PHÍ',
};

IconData _kindIcon(DeliveryTaskKind kind) => switch (kind) {
  DeliveryTaskKind.outbound => Icons.local_shipping_outlined,
  DeliveryTaskKind.returnPickup => Icons.assignment_return_outlined,
  DeliveryTaskKind.redelivery => Icons.swap_horizontal_circle_outlined,
};

String _statusLabel(DeliveryTaskStatus status, DeliveryTaskKind kind) {
  if (kind == DeliveryTaskKind.returnPickup) {
    return switch (status) {
      DeliveryTaskStatus.failed => 'Lấy hàng thất bại',
      DeliveryTaskStatus.returnedToStore => 'Cửa hàng đã nhận',
      _ => _genericStatusLabel(status),
    };
  }
  return _genericStatusLabel(status);
}

String _genericStatusLabel(DeliveryTaskStatus status) => switch (status) {
  DeliveryTaskStatus.pendingAssignment => 'Chờ phân công',
  DeliveryTaskStatus.assigned => 'Đã phân công',
  DeliveryTaskStatus.accepted => 'Đã nhận hàng',
  DeliveryTaskStatus.inTransit => 'Đang vận chuyển',
  DeliveryTaskStatus.delivered => 'Đã giao thành công',
  DeliveryTaskStatus.failed => 'Giao thất bại',
  DeliveryTaskStatus.returnedToStore => 'Đã trả về kho',
  DeliveryTaskStatus.cancelled => 'Đã hủy',
  DeliveryTaskStatus.managerActionRequired => 'Chờ quản lý xử lý',
};

IconData _statusIcon(DeliveryTaskStatus status) => switch (status) {
  DeliveryTaskStatus.pendingAssignment => Icons.schedule_outlined,
  DeliveryTaskStatus.assigned => Icons.storefront_outlined,
  DeliveryTaskStatus.accepted => Icons.assignment_turned_in_outlined,
  DeliveryTaskStatus.inTransit => Icons.local_shipping_outlined,
  DeliveryTaskStatus.delivered => Icons.check_circle_outline,
  DeliveryTaskStatus.failed => Icons.error_outline,
  DeliveryTaskStatus.returnedToStore => Icons.inventory_2_outlined,
  DeliveryTaskStatus.cancelled => Icons.cancel_outlined,
  DeliveryTaskStatus.managerActionRequired =>
    Icons.admin_panel_settings_outlined,
};
