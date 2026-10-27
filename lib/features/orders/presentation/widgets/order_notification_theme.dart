import 'package:flutter/material.dart';

import '../../../../app/theme/storefront_theme.dart';

/// Compatibility scope; shared ThemeData now belongs to app/theme.
class OrderNotificationTheme extends StorefrontTheme {
  const OrderNotificationTheme({required super.child, super.key});
  static const ink = StorefrontTheme.ink;
  static const cloud = StorefrontTheme.cloud;
  static const muted = StorefrontTheme.muted;
  static const success = StorefrontTheme.success;
  static const sale = StorefrontTheme.sale;
  static ThemeData data(ThemeData base) => StorefrontTheme.data(base);
}

AppBar orderStoreAppBar(
  BuildContext context, {
  required VoidCallback? onRefresh,
  String title = 'ĐƠN HÀNG',
  bool showBack = false,
}) => AppBar(
  automaticallyImplyLeading: false,
  leading: showBack
      ? BackButton(
          onPressed: Navigator.of(context).canPop()
              ? () => Navigator.of(context).maybePop()
              : null,
        )
      : null,
  title: showBack
      ? Text(title)
      : Row(
          children: [
            Flexible(
              child: Text(
                'VN ATHLETICS',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontFamily: 'BarlowCondensed',
                  fontSize: 14,
                  letterSpacing: 1.4,
                  color: OrderNotificationTheme.ink,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
  actions: [
    IconButton(
      tooltip: 'Làm mới đơn hàng',
      onPressed: onRefresh,
      icon: const Icon(Icons.refresh),
    ),
  ],
  bottom: const PreferredSize(
    preferredSize: Size.fromHeight(1),
    child: Divider(height: 1),
  ),
);
