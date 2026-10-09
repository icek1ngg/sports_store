import 'package:flutter/material.dart';

/// Displays the exact server unread count, abbreviating only the visual
/// surface above 99 while preserving the full value in accessibility text.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({required this.count, super.key});

  final int? count;

  @override
  Widget build(BuildContext context) {
    if (count == null || count! <= 0) {
      return const SizedBox.shrink();
    }

    final visual = count! > 99 ? '99+' : count.toString();
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$count thông báo chưa đọc',
      child: Container(
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          visual,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onError,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
