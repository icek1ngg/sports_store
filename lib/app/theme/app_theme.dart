import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'storefront_theme.dart';

abstract final class AppTheme {
  /// Shared visual scope, including local Material surface and font licenses.
  static Widget notificationsScope({required Widget child}) =>
      StorefrontTheme(child: child);

  /// Preserve the existing storefront appearance without changing global defaults.
  static ThemeData notifications(ThemeData base) => StorefrontTheme.data(base);

  static final light = ThemeData(
    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.onPrimaryContainer,
      inversePrimary: AppColors.inversePrimary,
      secondary: AppColors.secondary,
      onSecondary: AppColors.onSecondary,
      secondaryContainer: AppColors.secondaryContainer,
      onSecondaryContainer: AppColors.onSecondaryContainer,
      tertiary: AppColors.tertiary,
      onTertiary: AppColors.onTertiary,
      tertiaryContainer: AppColors.tertiaryContainer,
      onTertiaryContainer: AppColors.onTertiaryContainer,
      error: AppColors.error,
      onError: AppColors.onError,
      errorContainer: AppColors.errorContainer,
      onErrorContainer: AppColors.onErrorContainer,
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      surfaceDim: AppColors.surfaceDim,
      surfaceBright: AppColors.surfaceBright,
      surfaceContainerLowest: AppColors.surfaceContainerLowest,
      surfaceContainerLow: AppColors.surfaceContainerLow,
      surfaceContainer: AppColors.surfaceContainer,
      surfaceContainerHigh: AppColors.surfaceContainerHigh,
      surfaceContainerHighest: AppColors.surfaceContainerHighest,
      onSurfaceVariant: AppColors.onSurfaceVariant,
      inverseSurface: AppColors.inverseSurface,
      onInverseSurface: AppColors.inverseOnSurface,
      outline: AppColors.outline,
      outlineVariant: AppColors.outlineVariant,
      surfaceTint: AppColors.surfaceTint,
      primaryFixed: AppColors.primaryFixed,
      primaryFixedDim: AppColors.primaryFixedDim,
      onPrimaryFixed: AppColors.onPrimaryFixed,
      onPrimaryFixedVariant: AppColors.onPrimaryFixedVariant,
      secondaryFixed: AppColors.secondaryFixed,
      secondaryFixedDim: AppColors.secondaryFixedDim,
      onSecondaryFixed: AppColors.onSecondaryFixed,
      onSecondaryFixedVariant: AppColors.onSecondaryFixedVariant,
      tertiaryFixed: AppColors.tertiaryFixed,
      tertiaryFixedDim: AppColors.tertiaryFixedDim,
      onTertiaryFixed: AppColors.onTertiaryFixed,
      onTertiaryFixedVariant: AppColors.onTertiaryFixedVariant,
      shadow: AppColors.tertiary,
      scrim: AppColors.tertiary,
    ),
    canvasColor: AppColors.canvas,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.primary,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.onPrimary
              : AppColors.mute,
        ),
      ),
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(color: AppColors.ink),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.primary,
      side: const BorderSide(color: AppColors.hairlineSoft),
      labelStyle: TextStyle(
        color: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.onPrimary
              : AppColors.ink,
        ),
      ),
      color: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.primary
            : AppColors.surface,
      ),
    ),
    useMaterial3: true,
  );
}
