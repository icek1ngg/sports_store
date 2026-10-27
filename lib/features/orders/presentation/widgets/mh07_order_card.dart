import 'package:flutter/material.dart';

import '../../../../core/utils/display_formatters.dart';
import '../../domain/models/order_status.dart';
import '../../domain/models/order_summary.dart';

const mh07Ink = Color(0xff111111);
const mh07Cloud = Color(0xfff5f5f5);
const mh07Muted = Color(0xff707072);

/// MH07 presentation only. All action eligibility is supplied by its page.
class Mh07OrderCard extends StatelessWidget {
  const Mh07OrderCard({
    required this.summary,
    required this.onDetails,
    this.onCancel,
    this.onReturn,
    this.returnLabel,
    this.stale = false,
    super.key,
  });

  final OrderSummary summary;
  final VoidCallback onDetails;
  final VoidCallback? onCancel;
  final VoidCallback? onReturn;
  final String? returnLabel;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final order = summary.order;
    final large = MediaQuery.textScalerOf(context).scale(14) > 19;
    final id = Tooltip(
      message: order.id,
      child: Text(
        order.id,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 20,
          height: 1.3,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    final badge = Mh07StatusBadge(status: order.status);
    final date = Text(
      formatHanoiDateTime(order.placedAt),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 11,
        color: Color(0xff9e9ea0),
        height: 1.3,
      ),
    );
    final pending =
        order.status == OrderStatus.pendingConfirmation &&
        summary.capabilities.canCancelCustomer;
    final shipping = order.status == OrderStatus.delivering;
    final buttons = [
      if (pending) _button('Hủy đơn', onCancel),
      if (returnLabel != null) _button(returnLabel!, onReturn),
      _button('Xem chi tiết', onDetails, primary: !shipping),
      if (shipping)
        _button(
          'Theo dõi đơn',
          onDetails,
          primary: true,
          icon: Icons.location_on_outlined,
        ),
    ];
    return Semantics(
      label: 'Đơn hàng ${order.id}. ${orderStatusLabel(order.status)}',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: .06),
        child: InkWell(
          onTap: onDetails,
          borderRadius: BorderRadius.circular(32),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (large) ...[
                  id,
                  const SizedBox(height: 2),
                  date,
                  const SizedBox(height: 8),
                  badge,
                ] else
                  Row(
                    children: [
                      Expanded(child: id),
                      const SizedBox(width: 4),
                      Flexible(child: date),
                      const SizedBox(width: 8),
                      badge,
                    ],
                  ),
                const SizedBox(height: 16),
                if (summary.itemPreview.isEmpty)
                  const Text('Chưa có bản xem trước sản phẩm')
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Mh07ProductPlaceholder(),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              summary.itemPreview.first.productName,
                              maxLines: large ? 3 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 18 / 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              summary.itemPreview.first.variantLabel,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 20 / 14,
                                color: mh07Muted,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: mh07Cloud,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Số lượng: ${summary.itemQuantityTotal} sản phẩm',
                                style: const TextStyle(
                                  fontSize: 11,
                                  height: 14 / 11,
                                  color: Color(0xff4b4b4d),
                                ),
                              ),
                            ),
                            if (summary.itemLineCount > 1)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${summary.itemLineCount} dòng sản phẩm · xem đầy đủ trong chi tiết',
                                  maxLines: large ? null : 1,
                                  overflow: large
                                      ? TextOverflow.visible
                                      : TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: mh07Muted,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xfff4f3f5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final cod = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.local_shipping_outlined,
                            size: 16,
                            color: mh07Muted,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              summary.codSummary == null
                                  ? 'COD • Thanh toán khi nhận'
                                  : 'COD • ${codStatusLabel(summary.codSummary!.status)}',
                              style: const TextStyle(
                                fontSize: 11,
                                height: 14 / 11,
                                color: mh07Muted,
                              ),
                            ),
                          ),
                        ],
                      );
                      final total = Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Tổng thanh toán',
                            style: TextStyle(
                              fontSize: 11,
                              height: 14 / 11,
                              color: mh07Muted,
                            ),
                          ),
                          Text(
                            '₫${formatVnd(order.totalCodVnd).replaceAll(' ₫', '')}',
                            style: const TextStyle(
                              fontSize: 20,
                              height: 26 / 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      );
                      if (large || constraints.maxWidth < 265) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [cod, const SizedBox(height: 8), total],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: cod),
                          const SizedBox(width: 8),
                          total,
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                if (large)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final button in buttons)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: button,
                        ),
                    ],
                  )
                else
                  Row(
                    children: [
                      for (var i = 0; i < buttons.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(child: buttons[i]),
                      ],
                    ],
                  ),
                if (stale)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Dữ liệu có thể chưa cập nhật',
                      style: TextStyle(fontSize: 12, color: mh07Muted),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _button(
    String label,
    VoidCallback? action, {
    bool primary = false,
    IconData? icon,
  }) {
    return FilledButton(
      onPressed: action,
      style: FilledButton.styleFrom(
        backgroundColor: primary ? mh07Ink : mh07Cloud,
        foregroundColor: primary ? Colors.white : mh07Ink,
        disabledBackgroundColor: mh07Cloud,
        disabledForegroundColor: mh07Muted,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          height: 16 / 12,
          fontWeight: FontWeight.w600,
        ),
        shape: const StadiumBorder(),
      ),
      child: icon == null
          ? Text(label, textAlign: TextAlign.center)
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 6),
                Flexible(child: Text(label, textAlign: TextAlign.center)),
              ],
            ),
    );
  }
}

class Mh07ProductPlaceholder extends StatelessWidget {
  const Mh07ProductPlaceholder({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Không có ảnh sản phẩm',
    child: Container(
      width: 72,
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: mh07Cloud,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(
        Icons.image_not_supported_outlined,
        color: Color(0xff9e9ea0),
        size: 24,
      ),
    ),
  );
}

class Mh07StatusBadge extends StatelessWidget {
  const Mh07StatusBadge({required this.status, super.key});
  final OrderStatus status;
  @override
  Widget build(BuildContext context) {
    final shipping = status == OrderStatus.delivering;
    final delivered = status == OrderStatus.delivered;
    final color = shipping
        ? Colors.white
        : delivered
        ? const Color(0xff007d48)
        : mh07Ink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: shipping ? mh07Ink : mh07Cloud,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (delivered)
            Icon(Icons.check_circle_outline, size: 14, color: color)
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: shipping
                    ? const Color(0xff1eaa52)
                    : const Color(0xff9e9ea0),
              ),
            ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              orderStatusLabel(status),
              style: TextStyle(
                fontSize: 12,
                height: 16 / 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reference support surface; contact stays unavailable until Chat is wired.
class Mh07SupportPanel extends StatelessWidget {
  const Mh07SupportPanel({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: mh07Cloud,
      borderRadius: BorderRadius.circular(32),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CircleAvatar(
          radius: 20,
          backgroundColor: Colors.white,
          child: Icon(Icons.support_agent, size: 20, color: mh07Ink),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cần hỗ trợ về đơn hàng?',
                style: TextStyle(
                  fontSize: 12,
                  height: 16 / 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Thông tin giao hàng và đổi trả',
                style: TextStyle(
                  fontSize: 11,
                  height: 14 / 11,
                  color: mh07Muted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const Tooltip(
          message: 'Hỗ trợ chưa được tích hợp',
          child: SizedBox(
            width: 50,
            child: TextButton(
              onPressed: null,
              style: ButtonStyle(
                padding: WidgetStatePropertyAll(EdgeInsets.zero),
              ),
              child: Text(
                'LIÊN HỆ',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'BarlowCondensed',
                  fontSize: 14,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// A visual shell for the debug preview, never wired into the central router.
class Mh07PreviewNavigation extends StatelessWidget {
  const Mh07PreviewNavigation({super.key});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 3,
    shadowColor: Colors.black.withValues(alpha: .05),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            for (final item in const [
              (Icons.home_outlined, 'Trang chủ'),
              (Icons.search, 'Tìm kiếm'),
              (Icons.receipt_long_outlined, 'Đơn hàng'),
              (Icons.person_outline, 'Tài khoản'),
            ])
              Expanded(
                child: Semantics(
                  selected: item.$2 == 'Đơn hàng',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.$1,
                        size: 22,
                        color: item.$2 == 'Đơn hàng' ? mh07Ink : mh07Muted,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.$2,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          height: 14 / 11,
                          color: item.$2 == 'Đơn hàng' ? mh07Ink : mh07Muted,
                          fontWeight: item.$2 == 'Đơn hàng'
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
