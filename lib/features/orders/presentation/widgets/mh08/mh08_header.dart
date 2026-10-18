import 'package:flutter/material.dart';

import '../order_notification_theme.dart';

/// Compact MH08 header. The refresh action stays parent controlled so the
/// widget can expose an honest disabled state when a manager cannot refresh.
class Mh08Header extends StatelessWidget {
  const Mh08Header({this.title = 'ĐƠN HÀNG', this.onRefresh, super.key});

  final String title;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final brandStyle = theme.textTheme.labelMedium?.copyWith(
      color: OrderNotificationTheme.ink,
      fontFamily: 'BarlowCondensed',
      fontSize: 14,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.12,
      height: 1,
    );
    final titleStyle = theme.textTheme.titleLarge?.copyWith(
      color: OrderNotificationTheme.ink,
      fontFamily: 'BarlowCondensed',
      fontSize: 28,
      fontWeight: FontWeight.w700,
      height: 1.15,
    );

    return Material(
      color: Colors.white,
      child: Container(
        constraints: BoxConstraints(minHeight: stacked ? 112 : 64),
        padding: EdgeInsets.symmetric(
          horizontal: 20,
          vertical: stacked ? 8 : 0,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Color(0x0a111111),
              offset: Offset(0, 1),
              blurRadius: 8,
            ),
          ],
        ),
        child: stacked
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _brandAndRefresh(brandStyle),
                  const SizedBox(height: 4),
                  Text(title, textAlign: TextAlign.center, style: titleStyle),
                ],
              )
            : _compactHeader(brandStyle, titleStyle),
      ),
    );
  }

  Widget _brandAndRefresh(TextStyle? brandStyle) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'VN ATHLETICS',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: brandStyle,
          ),
        ),
        IconButton(
          tooltip: 'Làm mới đơn hàng',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }

  Widget _compactHeader(TextStyle? brandStyle, TextStyle? titleStyle) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Flexible(
          flex: 2,
          child: Text(
            'VN ATHLETICS',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: brandStyle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: titleStyle,
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Làm mới đơn hàng',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }
}
