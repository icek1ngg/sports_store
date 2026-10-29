import 'package:flutter/material.dart';

import '../order_notification_theme.dart';

/// Parent supplies current eligibility; this widget never reads order state.
class Mh08CardActions extends StatelessWidget {
  const Mh08CardActions({
    required this.canConfirm,
    required this.canReject,
    required this.isFresh,
    this.enabled = true,
    this.isBusy = false,
    this.onConfirm,
    this.onReject,
    super.key,
  });

  final bool canConfirm;
  final bool canReject;
  final bool isFresh;
  final bool enabled;
  final bool isBusy;
  final VoidCallback? onConfirm;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final confirm = _button(context, confirm: true);
    final reject = _button(context, confirm: false);
    final buttons = LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 260 ||
            MediaQuery.textScalerOf(context).scale(14) > 21;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [reject, const SizedBox(height: 8), confirm],
          );
        }
        return Row(
          children: [
            Expanded(child: reject),
            const SizedBox(width: 8),
            Expanded(child: confirm),
          ],
        );
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isBusy)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              liveRegion: true,
              child: const Text('Đang xử lý đơn hàng'),
            ),
          ),
        buttons,
      ],
    );
  }

  Widget _button(BuildContext context, {required bool confirm}) {
    final callback = confirm ? onConfirm : onReject;
    final eligible = confirm ? canConfirm : canReject;
    final available =
        enabled && isFresh && !isBusy && eligible && callback != null;
    final label = confirm ? 'Xác nhận' : 'Từ chối';
    final reason = !enabled || !eligible
        ? 'Thao tác hiện không khả dụng'
        : !isFresh
        ? 'Dữ liệu chưa được xác thực lại'
        : isBusy
        ? 'Đang xử lý đơn hàng'
        : callback == null
        ? 'Thao tác hiện chưa khả dụng'
        : label;
    final style = FilledButton.styleFrom(
      backgroundColor: confirm
          ? OrderNotificationTheme.ink
          : OrderNotificationTheme.cloud,
      foregroundColor: confirm ? Colors.white : OrderNotificationTheme.sale,
      disabledBackgroundColor: OrderNotificationTheme.cloud,
      disabledForegroundColor: OrderNotificationTheme.muted,
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      shape: const StadiumBorder(),
      textStyle: Theme.of(context).textTheme.labelLarge
          ?.copyWith(fontSize: 14, height: 18 / 14),
    );
    return Tooltip(
      message: reason,
      child: FilledButton(
        key: ValueKey('mh08-${confirm ? 'confirm' : 'reject'}'),
        onPressed: available ? callback : null,
        style: style,
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}
