import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/utils/display_formatters.dart';
import '../../domain/models/manager_return.dart';
import 'create_return_sections.dart';

const managerReturnsTitle = 'Quản lý yêu cầu trả hàng';

const _title = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w700,
  height: 1.3,
  color: AppColors.ink,
);
const _section = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w700,
  letterSpacing: 0.4,
  color: AppColors.mute,
);
const _muted = TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.mute);
const _body = TextStyle(fontSize: 13, height: 1.45, color: AppColors.charcoal);
const _code = TextStyle(
  fontSize: 12,
  height: 1.35,
  color: AppColors.charcoal,
  fontFeatures: [FontFeature.tabularFigures()],
);

BoxDecoration managerCard() => BoxDecoration(
  color: AppColors.surface,
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: AppColors.hairlineSoft),
);

/// Statuses offered as filter tabs, in workflow order.
const managerReturnFilters = <ReturnRequestStatus>[
  ReturnRequestStatus.pendingReview,
  ReturnRequestStatus.awaitingReturnPickup,
  ReturnRequestStatus.returningToStore,
  ReturnRequestStatus.underInspection,
  ReturnRequestStatus.awaitingRefund,
  ReturnRequestStatus.awaitingRedelivery,
  ReturnRequestStatus.managerActionRequired,
  ReturnRequestStatus.refunded,
  ReturnRequestStatus.initiallyRejected,
  ReturnRequestStatus.rejectedAfterInspection,
];

String managerStatusLabel(ReturnRequestStatus status) => switch (status) {
  ReturnRequestStatus.pendingReview => 'Chờ duyệt',
  ReturnRequestStatus.initiallyRejected => 'Đã từ chối',
  ReturnRequestStatus.awaitingReturnPickup => 'Chờ lấy hàng',
  ReturnRequestStatus.returningToStore => 'Đang về cửa hàng',
  ReturnRequestStatus.underInspection => 'Đang kiểm tra',
  ReturnRequestStatus.awaitingRefund => 'Chờ hoàn tiền',
  ReturnRequestStatus.refunded => 'Đã hoàn tiền',
  ReturnRequestStatus.rejectedAfterInspection => 'Từ chối sau kiểm tra',
  ReturnRequestStatus.awaitingRedelivery => 'Chờ giao lại',
  ReturnRequestStatus.redeliveryFailed ||
  ReturnRequestStatus.managerActionRequired => 'Cần xử lý',
};

({Color bg, Color fg}) _statusColors(ReturnRequestStatus status) =>
    switch (status) {
      ReturnRequestStatus.refunded => (
        bg: ReturnPalette.successSurface,
        fg: AppColors.success,
      ),
      ReturnRequestStatus.initiallyRejected ||
      ReturnRequestStatus.rejectedAfterInspection ||
      ReturnRequestStatus.awaitingRedelivery => (
        bg: const Color(0xfffdecec),
        fg: AppColors.saleDeep,
      ),
      ReturnRequestStatus.pendingReview ||
      ReturnRequestStatus.managerActionRequired ||
      ReturnRequestStatus.redeliveryFailed => (
        bg: ReturnPalette.creamSurface,
        fg: ReturnPalette.warningAccent,
      ),
      _ => (bg: ReturnPalette.selectedSurface, fg: AppColors.infoDeep),
    };

class ManagerStatusPill extends StatelessWidget {
  const ManagerStatusPill({required this.status, super.key});

  final ReturnRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = _statusColors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        managerStatusLabel(status),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: colors.fg,
        ),
      ),
    );
  }
}

/// Top bar shared by the list and the detail.
class ManagerReturnsHeader extends StatelessWidget {
  const ManagerReturnsHeader({
    required this.onRefresh,
    this.onBack,
    this.subtitle,
    super.key,
  });

  final VoidCallback? onBack;
  final VoidCallback? onRefresh;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.hairlineSoft)),
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              tooltip: 'Quay lại',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, color: AppColors.ink),
            )
          else
            const SizedBox(width: 12),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  managerReturnsTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _muted,
                  ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('mh15-refresh'),
            tooltip: 'Tải lại',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, color: AppColors.ink),
          ),
        ],
      ),
    );
  }
}

class ManagerReturnSearchField extends StatefulWidget {
  const ManagerReturnSearchField({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<ManagerReturnSearchField> createState() =>
      _ManagerReturnSearchFieldState();
}

class _ManagerReturnSearchFieldState extends State<ManagerReturnSearchField> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const ValueKey('mh15-search'),
      controller: _controller,
      onChanged: (value) {
        widget.onChanged(value);
        setState(() {});
      },
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppColors.surface,
        hintText: 'Tìm mã yêu cầu, mã đơn hoặc tên khách',
        prefixIcon: const Icon(Icons.search, color: AppColors.mute),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Xóa tìm kiếm',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                  setState(() {});
                },
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: const BorderSide(color: AppColors.ink, width: 1.4),
        ),
      ),
    );
  }
}

class ManagerReturnFilterBar extends StatelessWidget {
  const ManagerReturnFilterBar({
    required this.selected,
    required this.counts,
    required this.onSelected,
    super.key,
  });

  final ReturnRequestStatus? selected;
  final Map<ReturnRequestStatus, int> counts;
  final ValueChanged<ReturnRequestStatus?> onSelected;

  int _count(ReturnRequestStatus s) =>
      (counts[s] ?? 0) +
      (s == ReturnRequestStatus.managerActionRequired
          ? counts[ReturnRequestStatus.redeliveryFailed] ?? 0
          : 0);

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold(0, (a, b) => a + b);
    // Hide empty tabs except the selected one and the actionable ones.
    final tabs = [
      for (final s in managerReturnFilters)
        if (_count(s) > 0 ||
            s == selected ||
            s == ReturnRequestStatus.pendingReview ||
            s == ReturnRequestStatus.awaitingReturnPickup)
          s,
    ];
    Widget chip(String label, bool active, VoidCallback onTap, Key key) =>
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            key: key,
            label: Text(label),
            selected: active,
            onSelected: (_) => onTap(),
            showCheckmark: false,
            labelStyle: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active ? AppColors.onPrimary : AppColors.ink,
            ),
            selectedColor: AppColors.primary,
            backgroundColor: AppColors.surface,
            side: BorderSide(
              color: active ? AppColors.primary : AppColors.hairline,
            ),
            shape: const StadiumBorder(),
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          chip(
            'Tất cả ($total)',
            selected == null,
            () => onSelected(null),
            const ValueKey('mh15-filter-all'),
          ),
          for (final s in tabs)
            chip(
              '${managerStatusLabel(s)} (${_count(s)})',
              selected == s,
              () => onSelected(s),
              ValueKey('mh15-filter-${s.wireValue}'),
            ),
        ],
      ),
    );
  }
}

class ManagerReturnCard extends StatelessWidget {
  const ManagerReturnCard({
    required this.item,
    required this.onOpen,
    super.key,
  });

  final ManagerReturnSummary item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final more = item.lineCount > 1 ? ' +${item.lineCount - 1} sản phẩm' : '';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('mh15-row-${item.returnId}'),
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: managerCard(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _title,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ManagerStatusPill(status: item.status),
                ],
              ),
              const SizedBox(height: 6),
              Text('Yêu cầu ${item.returnId}', style: _code),
              Text(
                'Đơn ${item.orderId}',
                style: _code.copyWith(color: AppColors.mute),
              ),
              const SizedBox(height: 8),
              Text(
                '${item.firstItemName ?? 'Sản phẩm'}$more',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _body,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item.reason.title} · ${formatHanoiDateTime(item.submittedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _muted,
                    ),
                  ),
                  Text(
                    formatVnd(item.totalVnd),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ManagerSection extends StatelessWidget {
  const ManagerSection({
    required this.title,
    required this.child,
    this.trailing,
    this.icon,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: managerCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: AppColors.mute),
                const SizedBox(width: 6),
              ],
              Expanded(child: Text(title.toUpperCase(), style: _section)),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: DefaultTextStyle.merge(
                    textAlign: TextAlign.end,
                    child: trailing!,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class ManagerSummaryCard extends StatelessWidget {
  const ManagerSummaryCard({required this.detail, super.key});

  final ManagerReturnDetail detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: managerCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(child: Text('Mã yêu cầu', style: _muted)),
              ManagerStatusPill(status: detail.status),
            ],
          ),
          const SizedBox(height: 2),
          SelectableText(
            detail.returnId,
            style: _code.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text('Mã đơn hàng', style: _muted),
          SelectableText(detail.orderId, style: _code),
          const SizedBox(height: 8),
          Text(
            'Gửi lúc ${formatHanoiDateTime(detail.submittedAt)}'
            '${detail.deliveredAt == null ? '' : ' · Giao lúc ${formatHanoiDateTime(detail.deliveredAt!)}'}',
            style: _muted,
          ),
        ],
      ),
    );
  }
}

class ManagerContactCard extends StatelessWidget {
  const ManagerContactCard({required this.detail, this.onCall, super.key});

  final ManagerReturnDetail detail;
  final ValueChanged<String>? onCall;

  @override
  Widget build(BuildContext context) {
    final customer = detail.customer;
    final phone = customer.phone ?? detail.recipient.phone;
    return ManagerSection(
      title: 'Khách hàng',
      icon: Icons.person_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.softCloud,
                child: Text(
                  customer.name.characters.first.toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customer.name, style: _title),
                    if (phone != null) Text(phone, style: _body),
                  ],
                ),
              ),
              if (phone != null && onCall != null)
                IconButton.outlined(
                  tooltip: 'Gọi khách',
                  onPressed: () => onCall!(phone),
                  icon: const Icon(Icons.call_outlined),
                ),
            ],
          ),
          if (detail.recipient.address != null) ...[
            const SizedBox(height: 10),
            Text(
              'Địa chỉ lấy hàng: ${detail.recipient.address}',
              style: _muted,
            ),
          ],
        ],
      ),
    );
  }
}

class ManagerOrderItemsCard extends StatelessWidget {
  const ManagerOrderItemsCard({required this.detail, super.key});

  final ManagerReturnDetail detail;

  @override
  Widget build(BuildContext context) {
    final collected = {
      for (final i in detail.returnItems)
        if (i.orderItemId != null) i.orderItemId!: i,
    };
    return ManagerSection(
      title: detail.returnItems.isEmpty
          ? 'Sản phẩm trong đơn'
          : 'Sản phẩm thu hồi',
      icon: Icons.inventory_2_outlined,
      child: Column(
        children: [
          for (final item in detail.orderItems) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.softCloud,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.checkroom_outlined,
                    color: AppColors.stone,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.productName,
                        style: _body.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      if (item.variantLabel != null)
                        Text(item.variantLabel!, style: _muted),
                      Text(
                        'SL đặt: ${item.quantity} · ${formatVnd(item.unitPriceVnd)}',
                        style: _muted,
                      ),
                      if (collected[item.orderItemId] case final r?)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Thu hồi: ${r.quantityToCollect}'
                            '${r.quantityCollected > 0 ? ' · Đã nhận: ${r.quantityCollected}' : ''}',
                            style: _body.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.infoDeep,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Text(formatVnd(item.lineTotalVnd), style: _body),
              ],
            ),
            const SizedBox(height: 12),
          ],
          const Divider(height: 1, color: AppColors.hairlineSoft),
          const SizedBox(height: 10),
          _MoneyRow('Tiền hàng', detail.subtotalVnd),
          _MoneyRow('Phí giao ban đầu', detail.deliveryFeeVnd),
          _MoneyRow('Tổng đã thanh toán (COD)', detail.totalVnd, strong: true),
        ],
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow(this.label, this.amount, {this.strong = false});

  final String label;
  final int amount;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final style = strong
        ? const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          )
        : _body;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(formatVnd(amount), style: style),
        ],
      ),
    );
  }
}

class ManagerReasonCard extends StatelessWidget {
  const ManagerReasonCard({required this.detail, super.key});

  final ManagerReturnDetail detail;

  @override
  Widget build(BuildContext context) {
    return ManagerSection(
      title: 'Lý do khách gửi',
      icon: Icons.report_gmailerrorred_outlined,
      trailing: Text(detail.reason.title, style: _muted),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.softCloud,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '“${detail.description}”',
          style: _body.copyWith(fontStyle: FontStyle.italic),
        ),
      ),
    );
  }
}

class ManagerVideoCard extends StatelessWidget {
  const ManagerVideoCard({
    required this.paths,
    required this.onOpen,
    required this.openingPath,
    required this.error,
    super.key,
  });

  final List<String> paths;
  final ValueChanged<String> onOpen;
  final String? openingPath;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return ManagerSection(
      title: 'Video mở kiện của khách',
      icon: Icons.videocam_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, path) in paths.indexed) ...[
            OutlinedButton.icon(
              key: ValueKey('mh15-video-$index'),
              onPressed: openingPath == null ? () => onOpen(path) : null,
              icon: openingPath == path
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_circle_outline),
              label: Text(
                index == 0 ? 'Xem video ban đầu' : 'Xem video bổ sung $index',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.ink,
                minimumSize: const Size.fromHeight(44),
                shape: const StadiumBorder(),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (error != null)
            Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 16,
                  color: AppColors.sale,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    error!,
                    style: _muted.copyWith(color: AppColors.sale),
                  ),
                ),
              ],
            )
          else
            const Text(
              'Video mở trong tab mới bằng liên kết riêng, hết hạn sau 10 phút.',
              style: _muted,
            ),
        ],
      ),
    );
  }
}

class ManagerBankCard extends StatelessWidget {
  const ManagerBankCard({required this.bank, super.key});

  final ManagerReturnBank bank;

  @override
  Widget build(BuildContext context) {
    return ManagerSection(
      title: 'Thông tin nhận hoàn (chỉ quản lý)',
      icon: Icons.lock_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(bank.bankName, style: _body),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  bank.accountNumber,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppColors.ink,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Sao chép số tài khoản',
                icon: const Icon(Icons.copy_outlined, size: 20),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: bank.accountNumber));
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(content: Text('Đã sao chép số tài khoản.')),
                  );
                },
              ),
            ],
          ),
          Text(bank.accountHolder.toUpperCase(), style: _muted),
        ],
      ),
    );
  }
}

String _taskStatusLabel(String status) => switch (status) {
  'pending_assignment' => 'Chờ phân công',
  'assigned' => 'Đã phân công',
  'accepted' => 'Shipper đã nhận',
  'in_transit' => 'Đang mang về cửa hàng',
  'returned_to_store' => 'Đã về cửa hàng',
  'failed' => 'Lấy hàng thất bại',
  'manager_action_required' => 'Cần quản lý xử lý',
  'cancelled' => 'Đã hủy',
  _ => status,
};

class ManagerPickupCard extends StatelessWidget {
  const ManagerPickupCard({
    required this.task,
    this.title = 'Thu hồi hàng',
    super.key,
  });

  final ManagerReturnPickupTask task;
  final String title;

  @override
  Widget build(BuildContext context) {
    return ManagerSection(
      title: title,
      icon: Icons.local_shipping_outlined,
      trailing: Text(_taskStatusLabel(task.status), style: _muted),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(task.shipperName, style: _title),
          if (task.shipperPhone != null) Text(task.shipperPhone!, style: _body),
          if (task.assignedAt != null)
            Text(
              'Phân công lúc ${formatHanoiDateTime(task.assignedAt!)}',
              style: _muted,
            ),
          if (task.failureReason != null)
            Text('Lý do thất bại: ${task.failureReason}', style: _muted),
        ],
      ),
    );
  }
}

class ManagerDecisionCard extends StatelessWidget {
  const ManagerDecisionCard({required this.detail, super.key});

  final ManagerReturnDetail detail;

  @override
  Widget build(BuildContext context) {
    return ManagerSection(
      title: 'Quyết định',
      icon: Icons.gavel_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (detail.status == ReturnRequestStatus.initiallyRejected)
            Text('Lý do từ chối: ${detail.decisionReason ?? '—'}', style: _body)
          else
            const Text(
              'Đã duyệt lấy hàng. Đây chưa phải quyết định hoàn tiền.',
              style: _body,
            ),
          if (detail.decisionAt != null)
            Text(formatHanoiDateTime(detail.decisionAt!), style: _muted),
        ],
      ),
    );
  }
}

/// Explains what happens next when no action is available yet.
class ManagerNextStepNote extends StatelessWidget {
  const ManagerNextStepNote({required this.status, super.key});

  final ReturnRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final text = switch (status) {
      ReturnRequestStatus.awaitingReturnPickup => 'Chờ shipper lấy hàng từ khách. Khi hàng về cửa hàng, quản lý ghi nhận đã nhận và kiểm tra.',
      ReturnRequestStatus.initiallyRejected =>
        'Yêu cầu đã đóng. Hàng vẫn ở khách, không tạo thu hồi hay hoàn tiền.',
      ReturnRequestStatus.refunded => 'Đã hoàn tiền. Yêu cầu đã đóng.',
      ReturnRequestStatus.rejectedAfterInspection =>
        'Đã giao lại hàng cho khách. Yêu cầu đã đóng.',
      ReturnRequestStatus.returningToStore => 'Shipper đang mang hàng về. Nút nhận hàng xuất hiện khi shipper báo đã bàn giao tại cửa hàng.',
      ReturnRequestStatus.underInspection ||
      ReturnRequestStatus.pendingReview => 'Đang chờ khách bổ sung thông tin. Các quyết định mở lại khi khách phản hồi.',
      ReturnRequestStatus.awaitingRedelivery => 'Đang giao lại miễn phí cho khách (không thu COD). Yêu cầu đóng khi khách nhận lại hàng.',
      ReturnRequestStatus.redeliveryFailed ||
      ReturnRequestStatus.managerActionRequired => 'Thu hồi hoặc giao lại chưa thành công. Liên hệ khách và shipper để sắp xếp lại; yêu cầu chưa tự đóng.',
      _ => 'Không có thao tác ở bước này.',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReturnPalette.creamSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ReturnPalette.creamBorder),
      ),
      child: Text(text, style: _body.copyWith(color: ReturnPalette.warningInk)),
    );
  }
}

class ManagerInfoRequestCard extends StatelessWidget {
  const ManagerInfoRequestCard({
    required this.request,
    this.onOpenVideo,
    super.key,
  });

  final ManagerInfoRequest request;
  final VoidCallback? onOpenVideo;

  @override
  Widget build(BuildContext context) {
    return ManagerSection(
      title: 'Yêu cầu bổ sung',
      icon: Icons.help_outline,
      trailing: Text(
        request.isOpen ? 'Chờ khách phản hồi' : 'Khách đã phản hồi',
        style: _muted,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(request.message, style: _body),
          Text(formatHanoiDateTime(request.requestedAt), style: _muted),
          if (request.responseText != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.softCloud,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '“${request.responseText}”',
                style: _body.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
            if (request.respondedAt != null)
              Text(formatHanoiDateTime(request.respondedAt!), style: _muted),
          ],
          if (onOpenVideo != null)
            TextButton.icon(
              onPressed: onOpenVideo,
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Xem video bổ sung'),
              style: TextButton.styleFrom(foregroundColor: AppColors.ink),
            ),
        ],
      ),
    );
  }
}

class ManagerInspectionCard extends StatelessWidget {
  const ManagerInspectionCard({
    required this.detail,
    required this.onOpenEvidence,
    super.key,
  });

  final ManagerReturnDetail detail;
  final ValueChanged<String> onOpenEvidence;

  @override
  Widget build(BuildContext context) {
    final inspected = detail.returnItems.any(
      (i) => i.sellableQuantity + i.damagedQuantity > 0,
    );
    return ManagerSection(
      title: 'Kết quả kiểm tra',
      icon: Icons.fact_check_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (inspected)
            for (final i in detail.returnItems)
              Text(
                '${i.name}: ${i.sellableQuantity} bán được · '
                '${i.damagedQuantity} lỗi (không nhập kho bán)',
                style: _body,
              )
          else if (detail.status == ReturnRequestStatus.awaitingRedelivery ||
              detail.status == ReturnRequestStatus.rejectedAfterInspection)
            const Text(
              'Không chấp nhận. Toàn bộ hàng thực nhận được giao lại miễn phí.',
              style: _body,
            ),
          if (detail.inspectedAt != null)
            Text(formatHanoiDateTime(detail.inspectedAt!), style: _muted),
          for (final (index, path) in detail.inspectionEvidencePaths.indexed)
            TextButton.icon(
              onPressed: () => onOpenEvidence(path),
              icon: const Icon(Icons.attach_file, size: 18),
              label: Text('Bằng chứng kiểm tra ${index + 1}'),
              style: TextButton.styleFrom(foregroundColor: AppColors.ink),
            ),
        ],
      ),
    );
  }
}

class ManagerRefundCard extends StatelessWidget {
  const ManagerRefundCard({
    required this.refund,
    required this.onOpenEvidence,
    super.key,
  });

  final ManagerRefundRecord refund;
  final VoidCallback onOpenEvidence;

  @override
  Widget build(BuildContext context) {
    return ManagerSection(
      title: 'Hoàn tiền',
      icon: Icons.account_balance_outlined,
      trailing: Text(
        formatVnd(refund.amountVnd),
        style: _body.copyWith(fontWeight: FontWeight.w700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chuyển khoản lúc ${formatHanoiDateTime(refund.refundedAt)}',
            style: _body,
          ),
          TextButton.icon(
            onPressed: onOpenEvidence,
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: const Text('Xem chứng từ chuyển khoản'),
            style: TextButton.styleFrom(foregroundColor: AppColors.ink),
          ),
        ],
      ),
    );
  }
}
