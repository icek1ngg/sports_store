import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Visual scope shared by the four assigned pages; AppTheme stays unchanged.
class OrderNotificationTheme extends StatelessWidget {
  const OrderNotificationTheme({required this.child, super.key});
  final Widget child;

  static const ink = Color(0xff111111);
  static const cloud = Color(0xfff5f5f5);
  static const muted = Color(0xff707072);
  static const success = Color(0xff007d48);
  static const sale = Color(0xffd30005);
  static bool _licensesRegistered = false;

  static void _registerFontLicenses() {
    if (_licensesRegistered) return;
    _licensesRegistered = true;
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks([
        'Inter',
      ], await rootBundle.loadString('assets/fonts/Inter-OFL.txt'));
      yield LicenseEntryWithLineBreaks([
        'Barlow Condensed',
      ], await rootBundle.loadString('assets/fonts/BarlowCondensed-OFL.txt'));
    });
  }

  static ThemeData data(ThemeData base) {
    final colors = base.colorScheme.copyWith(
      primary: ink,
      onPrimary: Colors.white,
      primaryContainer: ink,
      onPrimaryContainer: Colors.white,
      secondary: muted,
      onSecondary: Colors.white,
      secondaryContainer: cloud,
      onSecondaryContainer: ink,
      tertiary: success,
      tertiaryContainer: const Color(0xffeaf5ee),
      onTertiaryContainer: success,
      surface: Colors.white,
      onSurface: ink,
      onSurfaceVariant: muted,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: cloud,
      surfaceContainer: const Color(0xffeeedef),
      surfaceContainerHigh: const Color(0xffe9e8ea),
      surfaceContainerHighest: const Color(0xffe3e2e4),
      outline: const Color(0xffcacacb),
      outlineVariant: const Color(0xffe5e5e5),
      error: sale,
      onError: Colors.white,
    );
    final body = base.textTheme.apply(
      fontFamily: 'Inter',
      bodyColor: ink,
      displayColor: ink,
    );
    const headline = TextStyle(
      fontFamily: 'BarlowCondensed',
      fontFamilyFallback: ['Inter'],
      fontWeight: FontWeight.w700,
      color: ink,
    );
    final text = body.copyWith(
      headlineLarge: headline.copyWith(fontSize: 40, height: 1.1),
      headlineMedium: headline.copyWith(fontSize: 32, height: 1.125),
      headlineSmall: headline.copyWith(fontSize: 28, height: 1.15),
      titleLarge: headline.copyWith(fontSize: 24, height: 1.2),
      titleMedium: body.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: body.titleSmall?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: body.bodyMedium?.copyWith(fontSize: 14, height: 1.45),
      bodySmall: body.bodySmall?.copyWith(
        fontSize: 12,
        height: 1.35,
        color: muted,
      ),
      labelLarge: body.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: body.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
    final pill = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(999),
    );
    return base.copyWith(
      colorScheme: colors,
      textTheme: text,
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge,
        toolbarHeight: 64,
      ),
      cardTheme: CardThemeData(
        color: cloud,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: Colors.white,
          shape: pill,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: cloud,
          foregroundColor: ink,
          side: BorderSide.none,
          shape: pill,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(48, 48),
          textStyle: text.labelLarge,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: cloud,
        selectedColor: ink,
        showCheckmark: false,
        side: BorderSide.none,
        shape: pill,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        labelStyle: text.labelMedium?.copyWith(color: muted),
        secondaryLabelStyle: text.labelMedium?.copyWith(color: Colors.white),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cloud,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: const BorderSide(color: ink),
        ),
        hintStyle: text.bodyMedium?.copyWith(color: muted),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xffe5e5e5),
        thickness: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _registerFontLicenses();
    return Theme(
      data: data(Theme.of(context)),
      // Access gate fallbacks also need a painted surface and Material text style.
      child: Material(color: Colors.white, child: child),
    );
  }
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
