import 'package:flutter/material.dart';

import 'package:sports_store/features/orders/domain/models/order_capabilities.dart';
import 'package:sports_store/features/orders/domain/models/order_operation.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_notification_theme.dart';

class Mh09ActionFooter extends StatelessWidget {
  const Mh09ActionFooter({
    this.capabilities = const OrderCapabilities.none(),
    this.isActionStateFresh = false,
    this.canActInCurrentScope = false,
    this.isBusy = false,
    this.onAction,
    super.key,
  });

  final OrderCapabilities capabilities;
  final bool isActionStateFresh;
  final bool canActInCurrentScope;
  final bool isBusy;
  final ValueChanged<OrderOperation>? onAction;

  static const _labelStyle = TextStyle(
    fontFamily: 'BarlowCondensed',
    fontFamilyFallback: ['Inter'],
    fontSize: 14,
    height: 16 / 14,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.12,
  );
  bool get _hasFooterCapability =>
      capabilities.canReject ||
      capabilities.canConfirm ||
      capabilities.canCancelExceptional;
  bool _enabled(bool capability) =>
      capability &&
      isActionStateFresh &&
      canActInCurrentScope &&
      !isBusy &&
      onAction != null;
  VoidCallback? _dispatch(OrderOperation operation, bool enabled) {
    if (!enabled || onAction == null) return null;
    return () => onAction!(operation);
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasFooterCapability) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final stacked =
            width <= 320 ||
            textScale > 1.25 ||
            MediaQuery.sizeOf(context).height < 500;
        final main = <Widget>[
          if (capabilities.canReject)
            _rejectButton(context, _enabled(capabilities.canReject)),
          if (capabilities.canConfirm)
            _confirmButton(_enabled(capabilities.canConfirm)),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (main.isNotEmpty) _mainActions(main, stacked),
            if (main.isNotEmpty && capabilities.canCancelExceptional)
              const SizedBox(height: 12),
            if (capabilities.canCancelExceptional)
              _exceptionalCancel(
                context,
                _enabled(capabilities.canCancelExceptional),
              ),
          ],
        );
      },
    );
  }

  Widget _mainActions(List<Widget> actions, bool stacked) {
    if (actions.length == 1) return actions.single;
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [actions[0], const SizedBox(height: 8), actions[1]],
      );
    }
    return Row(
      children: [
        Expanded(flex: 3, child: actions[0]),
        const SizedBox(width: 8),
        Expanded(flex: 4, child: actions[1]),
      ],
    );
  }

  Widget _rejectButton(BuildContext context, bool enabled) {
    return OutlinedButton.icon(
      key: const ValueKey('mh09-action-reject'),
      onPressed: _dispatch(OrderOperation.reject, enabled),
      style: _outlineStyle(
        background: const Color(0xffffdad6),
        foreground: Theme.of(context).colorScheme.onErrorContainer,
      ),
      icon: const Icon(Icons.block),
      label: const Text('Từ chối đơn', textAlign: TextAlign.center),
    );
  }

  Widget _confirmButton(bool enabled) {
    return FilledButton.icon(
      key: const ValueKey('mh09-action-confirm'),
      onPressed: _dispatch(OrderOperation.confirm, enabled),
      style: FilledButton.styleFrom(
        backgroundColor: OrderNotificationTheme.ink,
        foregroundColor: Colors.white,
        disabledBackgroundColor: OrderNotificationTheme.cloud,
        disabledForegroundColor: OrderNotificationTheme.muted,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: const StadiumBorder(),
        textStyle: _labelStyle,
      ),
      icon: const Icon(Icons.check),
      label: const Text('Xác nhận đơn hàng', textAlign: TextAlign.center),
    );
  }

  Widget _exceptionalCancel(BuildContext context, bool enabled) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: OrderNotificationTheme.sale.withValues(alpha: .06),
        border: Border.all(
          color: OrderNotificationTheme.sale.withValues(alpha: .28),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'HÀNH ĐỘNG NGOẠI LỆ',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                color: OrderNotificationTheme.sale,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('mh09-action-manager-cancel'),
              onPressed: _dispatch(OrderOperation.managerCancel, enabled),
              style: _outlineStyle(),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Hủy ngoại lệ', textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }

  ButtonStyle _outlineStyle({Color? background, Color? foreground}) =>
      OutlinedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground ?? OrderNotificationTheme.sale,
        disabledBackgroundColor: OrderNotificationTheme.cloud,
        disabledForegroundColor: OrderNotificationTheme.muted,
        side: const BorderSide(color: OrderNotificationTheme.sale),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: const StadiumBorder(),
        textStyle: _labelStyle,
      );
}
