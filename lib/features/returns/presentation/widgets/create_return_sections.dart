import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/utils/display_formatters.dart';
import '../../domain/models/return_reason.dart';
import '../view_models/create_return_state.dart';

/// Return-flow accents layered on the shared [AppColors] tokens.
abstract final class ReturnPalette {
  static const successSurface = Color(0xffeaf5ee);
  static const creamSurface = Color(0xfffffaee);
  static const creamBorder = Color(0xfff3e4bd);
  static const warningInk = Color(0xff5c4300);
  static const warningAccent = Color(0xffa15c07);
  static const selectedSurface = Color(0xfff3f6ff);
}

const _title = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w700,
  height: 1.3,
  color: AppColors.ink,
);
const _body = TextStyle(fontSize: 13, height: 1.4, color: AppColors.charcoal);
const _muted = TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.mute);

BoxDecoration _cardDecoration() => BoxDecoration(
  color: AppColors.surface,
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: AppColors.hairlineSoft),
);

class CreateReturnHeader extends StatelessWidget {
  const CreateReturnHeader({
    required this.stepLabel,
    this.onBack,
    this.onHelp,
    super.key,
  });

  final String stepLabel;
  final VoidCallback? onBack;

  /// The help button is shown only when the caller provides help content.
  final VoidCallback? onHelp;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.only(left: 4, right: 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.hairlineSoft)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Quay lại',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: AppColors.ink),
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Text(
              'Yêu cầu trả hàng',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.softCloud,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              stepLabel,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.ash,
              ),
            ),
          ),
          if (onHelp != null)
            IconButton(
              tooltip: 'Trợ giúp',
              onPressed: onHelp,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.help_outline, color: AppColors.ink),
            ),
        ],
      ),
    );
  }
}

class ReturnOrderCard extends StatelessWidget {
  const ReturnOrderCard({required this.order, super.key});

  final ReturnOrderOverview order;

  @override
  Widget build(BuildContext context) {
    final days = order.daysSinceDelivery;
    final receivedLabel = days == 0
        ? 'đã nhận hôm nay'
        : 'đã nhận $days ngày trước';
    final delivered = toHanoi(order.deliveredAt);
    final time =
        '${_two(delivered.hour)}:${_two(delivered.minute)}, '
        '${formatHanoiDate(order.deliveredAt)}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Đơn #${order.orderCode}',
                  // Real orders use the full UUID as their code; never cut it.
                  maxLines: 2,
                  style: _title,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: ReturnPalette.successSurface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Đã giao',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Giao lúc $time · $receivedLabel', style: _muted),
          const SizedBox(height: 14),
          for (var i = 0; i < order.lines.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, color: AppColors.hairlineSoft),
              ),
            _ReturnLineTile(
              line: order.lines[i],
              deliveryFeeVnd: i == order.lines.length - 1
                  ? order.deliveryFeeVnd
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _ReturnLineTile extends StatelessWidget {
  const _ReturnLineTile({required this.line, this.deliveryFeeVnd});

  final ReturnOrderLine line;
  final int? deliveryFeeVnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProductThumbnail(imageUrl: line.imageUrl),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      line.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatVnd(line.lineTotalVnd),
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('${line.variantLabel} · SL ${line.quantity}', style: _muted),
              const SizedBox(height: 2),
              Text('${formatVnd(line.unitPriceVnd)} / sản phẩm', style: _muted),
              if (deliveryFeeVnd != null)
                Text(
                  'Phí giao hàng ban đầu: ${formatVnd(deliveryFeeVnd!)}',
                  style: _muted,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProductThumbnail extends StatelessWidget {
  const _ProductThumbnail({this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    const placeholder = ColoredBox(
      color: AppColors.softCloud,
      child: Center(
        child: Icon(Icons.checkroom, color: AppColors.stone, size: 30),
      ),
    );
    final url = imageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox.square(
        dimension: 64,
        child: url == null
            ? placeholder
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

class ReturnTotalRow extends StatelessWidget {
  const ReturnTotalRow({required this.totalVnd, super.key});

  final int totalVnd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Tổng đã thanh toán',
              style: TextStyle(fontSize: 14, color: AppColors.charcoal),
            ),
          ),
          Text(
            formatVnd(totalVnd),
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class ReturnDeadlineNotice extends StatelessWidget {
  const ReturnDeadlineNotice({required this.order, super.key});

  final ReturnOrderOverview order;

  static const policy =
      'Vui lòng trả lại toàn bộ sản phẩm đã nhận. Cửa hàng chưa hỗ trợ trả '
      'một phần đơn hoặc đổi trực tiếp sản phẩm, kích cỡ.';

  String _remainingLabel() {
    final remaining = order.timeRemaining;
    if (!order.isWithinDeadline) return 'Đã hết hạn';
    if (remaining.inDays >= 1) return 'Còn ${remaining.inDays} ngày';
    final hours = (remaining.inMinutes / 60).ceil();
    return 'Còn $hours giờ';
  }

  @override
  Widget build(BuildContext context) {
    final deadline = toHanoi(order.returnDeadline);
    final deadlineText =
        '${_two(deadline.hour)}:${_two(deadline.minute)}, '
        '${formatHanoiDate(order.returnDeadline)}';
    final expired = !order.isWithinDeadline;
    final accent = expired ? AppColors.sale : ReturnPalette.warningAccent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ReturnPalette.creamSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ReturnPalette.creamBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Hạn gửi yêu cầu',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: ReturnPalette.warningInk,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      deadlineText,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: ReturnPalette.warningInk,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _remainingLabel(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            policy,
            style: _body.copyWith(
              fontSize: 12.5,
              color: ReturnPalette.warningInk,
            ),
          ),
          if (!expired && !order.canSubmitReturn) ...[
            const SizedBox(height: 8),
            const Text(
              'Đơn này hiện chưa thể gửi yêu cầu trả hàng.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.sale,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ReturnReasonSection extends StatelessWidget {
  const ReturnReasonSection({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final ReturnReason? selected;
  final ValueChanged<ReturnReason>? onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Vì sao bạn muốn trả hàng?', style: _title),
        const SizedBox(height: 2),
        const Text('Chọn một lý do', style: _muted),
        const SizedBox(height: 12),
        for (final reason in ReturnReason.values) ...[
          ReturnReasonTile(
            reason: reason,
            selected: reason == selected,
            onTap: onSelected == null ? null : () => onSelected!(reason),
          ),
          if (reason != ReturnReason.values.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

extension ReturnReasonPresentation on ReturnReason {
  String get title => switch (this) {
    ReturnReason.defective => 'Sản phẩm bị lỗi hoặc hư hỏng',
    ReturnReason.wrongItem => 'Giao sai sản phẩm',
    ReturnReason.missingItems => 'Giao thiếu sản phẩm',
  };

  String get description => switch (this) {
    ReturnReason.defective => 'Rách, bung chỉ, bẩn hoặc lỗi sản xuất',
    ReturnReason.wrongItem => 'Mẫu, màu sắc hoặc kích cỡ khác với đơn đã đặt',
    ReturnReason.missingItems => 'Thiếu sản phẩm hoặc phụ kiện so với đơn',
  };
}

class ReturnReasonTile extends StatelessWidget {
  const ReturnReasonTile({
    required this.reason,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final ReturnReason reason;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      child: Material(
        color: selected ? ReturnPalette.selectedSurface : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? AppColors.info : AppColors.hairlineSoft,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          key: ValueKey('mh13-reason-${reason.wireValue}'),
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reason.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(reason.description, style: _muted),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _RadioDot(selected: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.info : AppColors.hairline,
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: selected
          ? Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.info,
              ),
            )
          : null,
    );
  }
}

class CreateReturnSubmitBar extends StatelessWidget {
  const CreateReturnSubmitBar({required this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.hairlineSoft)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 52,
                child: FilledButton(
                  key: const ValueKey('mh13-submit'),
                  onPressed: onPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    disabledBackgroundColor: AppColors.surfaceContainerHigh,
                    disabledForegroundColor: AppColors.stone,
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Tiếp tục'),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tiếp theo: video và thông tin hoàn tiền',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.mute),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _two(int value) => value.toString().padLeft(2, '0');
