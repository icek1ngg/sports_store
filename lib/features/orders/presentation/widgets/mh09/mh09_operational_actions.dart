import 'package:flutter/material.dart';

import '../../../domain/models/order_capabilities.dart';
import '../order_notification_theme.dart';

/// External operations remain unavailable until a separately authorized owner
/// integration exists. This component deliberately has no mutation callbacks.
class Mh09OperationalActions extends StatelessWidget {
  const Mh09OperationalActions({
    this.capabilities = const OrderCapabilities.none(),
    this.unavailableReason,
    super.key,
  });

  final OrderCapabilities capabilities;
  final String? unavailableReason;

  @override
  Widget build(BuildContext context) {
    final deliveryReason = 'Dịch vụ giao hàng chưa sẵn sàng.';
    final operations = <(String, String)>[
      if (capabilities.canAssign) ('Phân công', deliveryReason),
      if (capabilities.canReassign) ('Phân công lại', deliveryReason),
      if (capabilities.canArrangeSecondAttempt)
        ('Giao lần hai', deliveryReason),
      if (capabilities.canRequestEarlyReturn) ('Hoàn hàng sớm', deliveryReason),
      if (capabilities.canReceiveUndelivered)
        ('Nhận và kiểm tra hàng', 'Quy trình kho chưa sẵn sàng.'),
    ];
    if (operations.isEmpty) return const SizedBox.shrink();
    final customReason = unavailableReason?.trim();
    final text = Theme.of(context).textTheme;
    return Card(
      color: OrderNotificationTheme.cloud,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'THAO TÁC VẬN HÀNH',
              style: text.titleMedium?.copyWith(
                fontFamily: 'Inter',
                fontSize: 20,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < operations.length; index++) ...[
              if (index > 0) const SizedBox(height: 12),
              _UnavailableOperation(
                label: operations[index].$1,
                reason: customReason?.isNotEmpty == true
                    ? customReason!
                    : operations[index].$2,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UnavailableOperation extends StatelessWidget {
  const _UnavailableOperation({required this.label, required this.reason});

  final String label;
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      enabled: false,
      label: '$label. Chưa khả dụng. $reason',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton(
            onPressed: null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: const StadiumBorder(),
            ),
            child: Text(label, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 4),
          Text('Chưa khả dụng: $reason'),
        ],
      ),
    );
  }
}
