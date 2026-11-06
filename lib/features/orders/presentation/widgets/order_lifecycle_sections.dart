import 'package:flutter/material.dart';

import '../../../../core/utils/display_formatters.dart';
import '../../domain/models/cod_summary.dart';
import '../../domain/models/delivery_summary.dart';
import '../../domain/models/order_status.dart';
import '../../domain/models/return_summary.dart';

/// Presents the operational projections in separate cards.
///
/// An absent projection is different from an [CodStatus.uncollected] or a
/// pending delivery state. The cards therefore keep the unavailable message
/// explicit and never manufacture a lifecycle state from a missing row.
class OrderLifecycleSections extends StatelessWidget {
  const OrderLifecycleSections({
    required this.deliverySummary,
    required this.codSummary,
    required this.returnSummaries,
    this.onOpenCod,
    this.onOpenReturn,
    super.key,
  });

  final DeliverySummary? deliverySummary;
  final CodSummary? codSummary;
  final List<ReturnSummary> returnSummaries;
  final ValueChanged<String>? onOpenCod;
  final ValueChanged<String>? onOpenReturn;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrderDeliverySection(summary: deliverySummary),
        const SizedBox(height: 12),
        OrderCodLifecycleSection(summary: codSummary, onOpen: onOpenCod),
        const SizedBox(height: 12),
        OrderReturnsSection(
          summaries: returnSummaries,
          onOpenReturn: onOpenReturn,
        ),
      ],
    );
  }
}

/// Shows the current outbound projection and the authoritative attempt facts.
class OrderDeliverySection extends StatelessWidget {
  const OrderDeliverySection({required this.summary, super.key});

  final DeliverySummary? summary;

  @override
  Widget build(BuildContext context) {
    return _LifecycleCard(
      title: 'Giao hàng',
      icon: Icons.local_shipping_outlined,
      child: summary == null
          ? const _UnavailableText('Chưa có dữ liệu giao hàng')
          : _DeliveryContent(summary: summary!),
    );
  }
}

class _DeliveryContent extends StatelessWidget {
  const _DeliveryContent({required this.summary});

  final DeliverySummary summary;

  @override
  Widget build(BuildContext context) {
    final attempt = summary.latestAttempt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LifecycleRow(
          label: 'Loại nhiệm vụ',
          value: summary.kind == null
              ? 'Chưa có dữ liệu'
              : _deliveryKindLabel(summary.kind!),
        ),
        const SizedBox(height: 8),
        _LifecycleRow(
          label: 'Trạng thái nhiệm vụ',
          value: summary.taskStatus == null
              ? 'Chưa có dữ liệu'
              : deliveryStatusLabel(summary.taskStatus),
        ),
        const SizedBox(height: 8),
        _LifecycleRow(
          label: 'Shipper',
          value: summary.assignedShipperName?.trim().isNotEmpty == true
              ? summary.assignedShipperName!
              : 'Chưa có dữ liệu',
        ),
        const SizedBox(height: 8),
        _LifecycleRow(label: 'Số lần giao', value: '${summary.attemptCount}/2'),
        if (summary.assignedAt != null) ...[
          const SizedBox(height: 8),
          _LifecycleRow(
            label: 'Đã phân công lúc',
            value: formatHanoiDateTime(summary.assignedAt!),
          ),
        ],
        if (summary.acceptedAt != null) ...[
          const SizedBox(height: 8),
          _LifecycleRow(
            label: 'Đã tiếp nhận lúc',
            value: formatHanoiDateTime(summary.acceptedAt!),
          ),
        ],
        if (summary.startedAt != null) ...[
          const SizedBox(height: 8),
          _LifecycleRow(
            label: 'Bắt đầu lúc',
            value: formatHanoiDateTime(summary.startedAt!),
          ),
        ],
        if (summary.completedAt != null) ...[
          const SizedBox(height: 8),
          _LifecycleRow(
            label: 'Hoàn tất lúc',
            value: formatHanoiDateTime(summary.completedAt!),
          ),
        ],
        if (summary.failureReason?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 8),
          _ReasonRow(
            label: 'Lý do giao thất bại',
            reason: summary.failureReason!,
          ),
        ],
        if (attempt != null) ...[
          const Divider(height: 24),
          Text(
            'Lần giao gần nhất',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          _LifecycleRow(
            label: 'Kết quả',
            value: attempt.result == DeliveryAttemptResult.success
                ? 'Giao thành công'
                : 'Giao thất bại',
          ),
          const SizedBox(height: 8),
          _LifecycleRow(
            label: 'Thời điểm',
            value: formatHanoiDateTime(attempt.occurredAt),
          ),
          if (attempt.reason?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            _ReasonRow(label: 'Lý do', reason: attempt.reason!),
          ],
        ],
      ],
    );
  }
}

/// Shows the COD lifecycle without treating a missing row as uncollected.
class OrderCodLifecycleSection extends StatelessWidget {
  const OrderCodLifecycleSection({
    required this.summary,
    this.onOpen,
    super.key,
  });

  final CodSummary? summary;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    return _LifecycleCard(
      title: 'Đối soát COD',
      icon: Icons.payments_outlined,
      child: summary == null
          ? const _UnavailableText('Chưa có dữ liệu COD')
          : _CodContent(summary: summary!, onOpen: onOpen),
    );
  }
}

class _CodContent extends StatelessWidget {
  const _CodContent({required this.summary, this.onOpen});

  final CodSummary summary;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LifecycleRow(
          label: 'Trạng thái',
          value: codStatusLabel(summary.status),
        ),
        const SizedBox(height: 8),
        _LifecycleRow(
          label: 'Nghĩa vụ COD',
          value: formatVnd(summary.expectedAmountVnd),
        ),
        const SizedBox(height: 8),
        _LifecycleRow(
          label: 'Đã thu từ khách',
          value: formatVnd(summary.collectedAmountVnd),
        ),
        const SizedBox(height: 8),
        _LifecycleRow(
          label: 'Cửa hàng đã nhận',
          value: formatVnd(summary.receivedAmountVnd),
        ),
        if (summary.collectedAt != null) ...[
          const SizedBox(height: 8),
          _LifecycleRow(
            label: 'Thu lúc',
            value: formatHanoiDateTime(summary.collectedAt!),
          ),
        ],
        if (summary.receivedAt != null) ...[
          const SizedBox(height: 8),
          _LifecycleRow(
            label: 'Cửa hàng nhận lúc',
            value: formatHanoiDateTime(summary.receivedAt!),
          ),
        ],
        const SizedBox(height: 12),
        _UnavailableOrAction(
          label: 'Mở đối soát COD',
          unavailableMessage: 'Điều hướng đối soát COD chưa khả dụng',
          onPressed: onOpen == null ? null : () => onOpen!(summary.orderId),
        ),
      ],
    );
  }
}

/// Shows return requests independently from the order and COD lifecycles.
class OrderReturnsSection extends StatelessWidget {
  const OrderReturnsSection({
    required this.summaries,
    this.onOpenReturn,
    super.key,
  });

  final List<ReturnSummary> summaries;
  final ValueChanged<String>? onOpenReturn;

  @override
  Widget build(BuildContext context) {
    return _LifecycleCard(
      title: 'Yêu cầu trả hàng',
      icon: Icons.assignment_return_outlined,
      child: summaries.isEmpty
          ? const _UnavailableText('Chưa có dữ liệu yêu cầu trả hàng')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < summaries.length; index++) ...[
                  if (index > 0) const Divider(height: 24),
                  _ReturnContent(
                    summary: summaries[index],
                    onOpen: onOpenReturn,
                  ),
                ],
              ],
            ),
    );
  }
}

class _ReturnContent extends StatelessWidget {
  const _ReturnContent({required this.summary, this.onOpen});

  final ReturnSummary summary;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    final reason = summary.decisionReason?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LifecycleRow(label: 'Mã yêu cầu', value: summary.returnId),
        const SizedBox(height: 8),
        _LifecycleRow(
          label: 'Trạng thái',
          value: returnStatusLabel(summary.status),
        ),
        const SizedBox(height: 8),
        _LifecycleRow(
          label: 'Gửi lúc',
          value: formatHanoiDateTime(summary.submittedAt),
        ),
        if (summary.closedAt != null) ...[
          const SizedBox(height: 8),
          _LifecycleRow(
            label: 'Đóng lúc',
            value: formatHanoiDateTime(summary.closedAt!),
          ),
        ],
        if (reason != null && reason.isNotEmpty) ...[
          const SizedBox(height: 8),
          _ReasonRow(label: 'Lý do xử lý', reason: reason),
        ],
        const SizedBox(height: 12),
        _UnavailableOrAction(
          label: 'Mở xử lý trả hàng',
          unavailableMessage: 'Điều hướng xử lý trả hàng chưa khả dụng',
          onPressed: onOpen == null ? null : () => onOpen!(summary.returnId),
        ),
      ],
    );
  }
}

class _LifecycleCard extends StatelessWidget {
  const _LifecycleCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, semanticLabel: title),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _LifecycleRow extends StatelessWidget {
  const _LifecycleRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelWidget = Text(
          label,
          style: Theme.of(context).textTheme.labelMedium,
        );
        final valueWidget = Text(value, softWrap: true);
        if (constraints.maxWidth < 320) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [labelWidget, const SizedBox(height: 2), valueWidget],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 124, child: labelWidget),
            const SizedBox(width: 8),
            Expanded(child: valueWidget),
          ],
        );
      },
    );
  }
}

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({required this.label, required this.reason});

  final String label;
  final String reason;

  @override
  Widget build(BuildContext context) {
    return _LifecycleRow(label: label, value: reason);
  }
}

class _UnavailableText extends StatelessWidget {
  const _UnavailableText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: message,
      child: Text(message, softWrap: true),
    );
  }
}

class _UnavailableOrAction extends StatelessWidget {
  const _UnavailableOrAction({
    required this.label,
    required this.unavailableMessage,
    required this.onPressed,
  });

  final String label;
  final String unavailableMessage;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (onPressed != null) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton(onPressed: onPressed, child: Text(label)),
      );
    }
    return Semantics(
      container: true,
      label: unavailableMessage,
      child: Text(unavailableMessage, softWrap: true),
    );
  }
}

String _deliveryKindLabel(DeliveryTaskKind kind) {
  return switch (kind) {
    DeliveryTaskKind.outbound => 'Giao đến khách',
    DeliveryTaskKind.returnPickup => 'Lấy hàng trả',
    DeliveryTaskKind.redelivery => 'Giao lại hàng',
  };
}
