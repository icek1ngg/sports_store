import 'package:flutter/material.dart';

import '../../../domain/models/order_details.dart';
import '../../../domain/models/order_operation.dart';

class Mh09LegacyActionFooter extends StatelessWidget {
  const Mh09LegacyActionFooter({
    super.key,
    required this.details,
    required this.onShowAction,
    required this.isStillAllowed,
    this.orderCommandsOnly = false,
    this.externalActionsOnly = false,
  });

  final OrderDetails details;
  final void Function(OrderOperation operation) onShowAction;
  final bool Function(OrderOperation operation) isStillAllowed;
  final bool orderCommandsOnly;
  final bool externalActionsOnly;

  @override
  Widget build(BuildContext context) {
    final capabilities = details.capabilities;
    final orderActions = <Widget>[];
    if (!externalActionsOnly && capabilities.canConfirm) {
      orderActions.add(
        FilledButton.icon(
          onPressed: isStillAllowed(OrderOperation.confirm)
              ? () => onShowAction(OrderOperation.confirm)
              : null,
          icon: const Icon(Icons.check),
          label: const Text('Xác nhận đơn'),
        ),
      );
    }
    if (!externalActionsOnly && capabilities.canReject) {
      orderActions.add(
        OutlinedButton.icon(
          onPressed: isStillAllowed(OrderOperation.reject)
              ? () => onShowAction(OrderOperation.reject)
              : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          icon: const Icon(Icons.block),
          label: const Text('Từ chối đơn'),
        ),
      );
    }
    if (!externalActionsOnly && capabilities.canCancelExceptional) {
      orderActions.add(
        OutlinedButton.icon(
          onPressed: isStillAllowed(OrderOperation.managerCancel)
              ? () => onShowAction(OrderOperation.managerCancel)
              : null,
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('Hủy ngoại lệ'),
        ),
      );
    }

    final externalActions = <Widget>[];
    if (!orderCommandsOnly && capabilities.canAssign) {
      externalActions.add(
        _UnavailableActionButton(
          label: 'Phân công',
          reason: 'Phân công chưa khả dụng do dịch vụ giao hàng chưa sẵn sàng',
        ),
      );
    }
    if (!orderCommandsOnly && capabilities.canReassign) {
      externalActions.add(
        _UnavailableActionButton(
          label: 'Phân công lại',
          reason:
              'Phân công lại chưa khả dụng do dịch vụ giao hàng chưa sẵn sàng',
        ),
      );
    }
    if (!orderCommandsOnly && capabilities.canArrangeSecondAttempt) {
      externalActions.add(
        _UnavailableActionButton(
          label: 'Giao lần hai',
          reason:
              'Giao lần hai chưa khả dụng do dịch vụ giao hàng chưa sẵn sàng',
        ),
      );
    }
    if (!orderCommandsOnly && capabilities.canRequestEarlyReturn) {
      externalActions.add(
        _UnavailableActionButton(
          label: 'Hoàn hàng sớm',
          reason:
              'Hoàn hàng sớm chưa khả dụng do dịch vụ giao hàng chưa sẵn sàng',
        ),
      );
    }
    if (!orderCommandsOnly && capabilities.canReceiveUndelivered) {
      externalActions.add(
        _UnavailableActionButton(
          label: 'Nhận và kiểm tra hàng',
          reason: 'Nhận và kiểm tra hàng chưa khả dụng do quy trình kho chưa sẵn sàng',
        ),
      );
    }

    if (orderActions.isEmpty && externalActions.isEmpty) {
      return const SizedBox.shrink();
    }
    if (orderCommandsOnly) {
      return Container(
        padding: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Wrap(spacing: 8, runSpacing: 8, children: orderActions),
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Thao tác quản lý',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (orderActions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: orderActions),
            ],
            if (externalActions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Các thao tác sau chưa khả dụng cho đến khi dịch vụ giao hàng và kho được tích hợp.',
                softWrap: true,
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: externalActions),
            ],
          ],
        ),
      ),
    );
  }
}

class _UnavailableActionButton extends StatelessWidget {
  const _UnavailableActionButton({required this.label, required this.reason});

  final String label;
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: reason,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton(onPressed: null, child: Text(label)),
          const SizedBox(height: 2),
          Text(reason, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
