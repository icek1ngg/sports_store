import 'package:flutter/material.dart';

import 'storefront_theme.dart';

abstract final class AppTheme {
  /// Shared visual scope, including local Material surface and font licenses.
  static Widget notificationsScope({required Widget child}) =>
      StorefrontTheme(child: child);

  /// Preserve the existing storefront appearance without changing global defaults.
  static ThemeData notifications(ThemeData base) => StorefrontTheme.data(base);

  static final light = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
    useMaterial3: true,
  );
}
