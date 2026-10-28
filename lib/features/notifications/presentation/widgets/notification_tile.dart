import 'package:flutter/material.dart';

import '../../../../core/utils/display_formatters.dart';
import '../../domain/models/notification_item.dart';

/// A read/unread notification row that only uses the server supplied text and
/// allowlisted subject type. It never derives a route from title or body.
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    required this.notification,
    this.onTap,
    this.onMarkRead,
    this.isPendingRead = false,
    super.key,
  });

  final NotificationItem notification;
  final VoidCallback? onTap;
  final VoidCallback? onMarkRead;
  final bool isPendingRead;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final unread = !notification.isRead;
    final surface = unread ? colors.surfaceContainerLow : colors.surface;
    final typeLabel = _subjectTypeLabel(notification.subjectType);
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SubjectIcon(type: notification.subjectType, unread: unread),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      // The outer tile label already announces title/type.
                      child: ExcludeSemantics(
                        child: Text(
                          notification.title,
                          softWrap: true,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: unread
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                        ),
                      ),
                    ),
                    if (unread)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, top: 4),
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.primary,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(notification.body, softWrap: true),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      formatHanoiDateTime(notification.createdAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    ExcludeSemantics(
                      child: Text(
                        typeLabel,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                if (unread && (onMarkRead != null || isPendingRead)) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: isPendingRead ? null : onMarkRead,
                      style: TextButton.styleFrom(
                        alignment: AlignmentDirectional.centerStart,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          isPendingRead
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.done, size: 18),
                          const SizedBox(width: 8),
                          const Expanded(child: Text('Đánh dấu đã đọc')),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return Semantics(
      container: true,
      button: onTap != null,
      label: '${unread ? 'Chưa đọc. ' : ''}${notification.title}. $typeLabel',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: onTap == null
            ? content
            : InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                child: content,
              ),
      ),
    );
  }
}

class _SubjectIcon extends StatelessWidget {
  const _SubjectIcon({required this.type, required this.unread});

  final NotificationSubjectType type;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final data = _subjectIcon(type);
    return CircleAvatar(
      radius: 22,
      backgroundColor: unread ? colors.primary : colors.surfaceContainerLow,
      child: Icon(
        data.icon,
        color: unread ? colors.onPrimary : colors.onSurfaceVariant,
      ),
    );
  }
}

({IconData icon, String label}) _subjectIcon(NotificationSubjectType type) {
  return switch (type.rawValue) {
    'order' => (icon: Icons.receipt_long_outlined, label: 'Đơn hàng'),
    'delivery_task' => (
      icon: Icons.local_shipping_outlined,
      label: 'Nhiệm vụ giao hàng',
    ),
    'cod' => (icon: Icons.payments_outlined, label: 'COD'),
    'return_request' => (
      icon: Icons.assignment_return_outlined,
      label: 'Yêu cầu trả hàng',
    ),
    'conversation' => (icon: Icons.chat_bubble_outline, label: 'Tin nhắn'),
    'notification_only' => (icon: Icons.notifications_none, label: 'Thông báo'),
    _ => (icon: Icons.help_outline, label: 'Thông báo chưa phân loại'),
  };
}

String _subjectTypeLabel(NotificationSubjectType type) {
  return _subjectIcon(type).label;
}
