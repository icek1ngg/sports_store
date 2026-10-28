import 'package:flutter/material.dart';

import '../../../domain/models/order_warning.dart';
import '../order_notification_theme.dart';

/// Renders only server-provided warning messages.
class Mh08OperationalNotice extends StatelessWidget {
  const Mh08OperationalNotice({required this.warnings, super.key});

  final List<OrderWarning> warnings;

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey('mh08-operational-notice'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < warnings.length; index++) ...[
          if (index > 0) const SizedBox(height: 8),
          _WarningRow(warning: warnings[index]),
        ],
      ],
    );
  }
}

class _WarningRow extends StatelessWidget {
  const _WarningRow({required this.warning});

  final OrderWarning warning;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: 'Cảnh báo: ${warning.message}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_outlined,
            size: 16,
            color: OrderNotificationTheme.sale,
            semanticLabel: 'Cảnh báo',
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              warning.message,
              softWrap: true,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                height: 14 / 11,
                color: OrderNotificationTheme.sale,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
