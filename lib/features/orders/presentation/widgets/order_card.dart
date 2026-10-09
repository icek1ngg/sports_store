import 'package:flutter/material.dart';

import '../../../../core/utils/display_formatters.dart';
import '../../domain/models/order_summary.dart';
import 'order_status_badge.dart';

/// Shared order summary card for MH07 and MH08.
///
/// The manager variant adds the buyer/address and operational projection that
/// the server supplied. It never reads a raw delivery task or infers an action
/// from an order status.
class OrderCard extends StatelessWidget {
  const OrderCard({
    required this.summary,
    this.showManagerContext = false,
    this.onTap,
    this.isStale = false,
    this.mutationInProgress = false,
    super.key,
  });

  final OrderSummary summary;
  final bool showManagerContext;
  final VoidCallback? onTap;
  final bool isStale;
  final bool mutationInProgress;

  @override
  Widget build(BuildContext context) {
    final order = summary.order;
    final effectiveOnTap = mutationInProgress ? null : onTap;
    final body = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(summary: summary, showManagerContext: showManagerContext),
          const SizedBox(height: 12),
          _ItemsPreview(summary: summary),
          if (showManagerContext) ...[
            const SizedBox(height: 12),
            _ManagerProjection(summary: summary),
          ],
          const SizedBox(height: 12),
          _Footer(summary: summary),
          if (isStale) ...[
            const SizedBox(height: 12),
            const _StaleCardNotice(),
          ],
        ],
      ),
    );

    final card = Card(
      clipBehavior: Clip.antiAlias,
      child: effectiveOnTap == null
          ? body
          : InkWell(onTap: effectiveOnTap, child: body),
    );

    return Semantics(
      button: effectiveOnTap != null,
      enabled: mutationInProgress ? false : null,
      onTap: effectiveOnTap,
      label:
          'Đơn hàng ${formatFullUuid(order.id)}. ${orderStatusLabel(order.status)}',
      child: card,
    );
  }
}

/// Explicit role variants keep page code readable while sharing one visual
/// contract and one server projection.
class CustomerOrderCard extends OrderCard {
  const CustomerOrderCard({
    required super.summary,
    super.onTap,
    super.isStale,
    super.mutationInProgress,
    super.key,
  }) : super(showManagerContext: false);
}

class ManagerOrderCard extends OrderCard {
  const ManagerOrderCard({
    required super.summary,
    super.onTap,
    super.isStale,
    super.mutationInProgress,
    super.key,
  }) : super(showManagerContext: true);
}

class _Header extends StatelessWidget {
  const _Header({required this.summary, required this.showManagerContext});

  final OrderSummary summary;
  final bool showManagerContext;

  @override
  Widget build(BuildContext context) {
    final order = summary.order;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            return Wrap(
              alignment: WrapAlignment.spaceBetween,
              runAlignment: WrapAlignment.start,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth > 320
                        ? constraints.maxWidth - 150
                        : constraints.maxWidth,
                  ),
                  child: Text(
                    'Đơn hàng ${formatFullUuid(order.id)}',
                    softWrap: true,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                OrderStatusBadge(status: order.status),
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        Text('Đặt lúc ${formatHanoiDateTime(order.placedAt)}'),
        if (showManagerContext) ...[
          const SizedBox(height: 6),
          Text(
            summary.customerDisplayName == null ||
                    summary.customerDisplayName!.trim().isEmpty
                ? 'Người nhận: ${order.recipientName}'
                : 'Khách hàng: ${summary.customerDisplayName}',
            softWrap: true,
          ),
          const SizedBox(height: 4),
          Text('Địa chỉ: ${order.addressDetail}', softWrap: true),
        ],
      ],
    );
  }
}

class _ItemsPreview extends StatelessWidget {
  const _ItemsPreview({required this.summary});

  final OrderSummary summary;

  @override
  Widget build(BuildContext context) {
    final preview = summary.itemPreview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${summary.itemQuantityTotal} sản phẩm · ${summary.itemLineCount} dòng',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        if (preview.isEmpty)
          const Text('Chưa có bản xem trước sản phẩm')
        else
          ...preview
              .take(2)
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${item.productName} · ${item.variantLabel} × ${item.quantity}',
                    softWrap: true,
                  ),
                ),
              ),
        if (summary.itemLineCount > preview.length)
          Text(
            'Và ${summary.itemLineCount - preview.length} dòng sản phẩm khác',
          ),
      ],
    );
  }
}

class _ManagerProjection extends StatelessWidget {
  const _ManagerProjection({required this.summary});

  final OrderSummary summary;

  @override
  Widget build(BuildContext context) {
    final delivery = summary.deliverySummary;
    final warnings = summary.warnings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (delivery?.taskStatus != null)
          _ProjectionRow(
            icon: Icons.local_shipping_outlined,
            label: 'Giao hàng',
            value: deliveryStatusLabel(delivery!.taskStatus),
          ),
        if (delivery?.assignedShipperName != null &&
            delivery!.assignedShipperName!.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          _ProjectionRow(
            icon: Icons.person_pin_circle_outlined,
            label: 'Shipper',
            value: delivery.assignedShipperName!,
          ),
        ],
        if (warnings.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...warnings.map(
            (warning) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_outlined,
                    size: 18,
                    color: Theme.of(context).colorScheme.error,
                    semanticLabel: 'Cảnh báo',
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(warning.message, softWrap: true)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.summary});

  final OrderSummary summary;

  @override
  Widget build(BuildContext context) {
    final cod = summary.codSummary;
    final amount = summary.order.totalCodVnd;
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        Text('COD: ${formatVnd(amount)}'),
        Text(
          cod == null
              ? 'Chưa có dữ liệu COD'
              : 'COD: ${codStatusLabel(cod.status)}',
        ),
      ],
    );
  }
}

class _ProjectionRow extends StatelessWidget {
  const _ProjectionRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, semanticLabel: label),
        const SizedBox(width: 6),
        Expanded(child: Text('$label: $value', softWrap: true)),
      ],
    );
  }
}

class _StaleCardNotice extends StatelessWidget {
  const _StaleCardNotice();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: 'Dữ liệu có thể chưa cập nhật',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.sync_problem_outlined,
            size: 18,
            color: Theme.of(context).colorScheme.outline,
            semanticLabel: 'Dữ liệu có thể chưa cập nhật',
          ),
          const SizedBox(width: 6),
          const Expanded(child: Text('Dữ liệu có thể chưa cập nhật')),
        ],
      ),
    );
  }
}
