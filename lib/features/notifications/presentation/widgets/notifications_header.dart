import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import 'unread_badge.dart';

/// Header only: the exact unread count comes from the foundation provider.
// Return the real AppBar so its inherited toolbar-height/layout contract and
// existing AppBar inspection clients remain compatible.
AppBar notificationsHeader({int? unreadCount}) => AppBar(
  title: const Text('Thông báo'),
  actions: [
    if (unreadCount != null)
      Padding(
        padding: const EdgeInsetsDirectional.only(end: 12),
        child: Center(child: _HeaderBadge(count: unreadCount)),
      ),
  ],
);

class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return Theme(
      data: AppTheme.notifications(base).copyWith(
        colorScheme: base.colorScheme.copyWith(
          error: base.colorScheme.onSurface,
        ),
      ),
      child: UnreadBadge(count: count),
    );
  }
}
