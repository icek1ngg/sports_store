import 'package:flutter/material.dart';

const ink = Color(0xFF151719);
const forest = Color(0xFF21895F);
const mint = Color(0xFFE4F3EA);
const lime = Color(0xFFC8EF78);
const paper = Color(0xFFF2F8FB);
const muted = Color(0xFF748079);
const line = Color(0xFFE3E7E9);
const orange = Color(0xFFFFA75E);

ThemeData buildPrmTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: paper,
  colorScheme: ColorScheme.fromSeed(
    seedColor: forest,
    primary: forest,
    surface: Colors.white,
  ),
  fontFamily: 'Roboto',
  appBarTheme: const AppBarTheme(
    backgroundColor: paper,
    foregroundColor: ink,
    elevation: 0,
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: Colors.white,
    indicatorColor: mint,
    height: 66,
    labelTextStyle: WidgetStateProperty.resolveWith(
      (states) => TextStyle(
        fontSize: 11,
        fontWeight: states.contains(WidgetState.selected)
            ? FontWeight.w700
            : FontWeight.w500,
        color: states.contains(WidgetState.selected) ? forest : muted,
      ),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    hintStyle: const TextStyle(color: Color(0xFF9AA49D), fontSize: 14),
    labelStyle: const TextStyle(color: muted),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: forest, width: 1.4),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
    ),
  ),
);

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.compact = false, this.light = false});
  final bool compact;
  final bool light;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.bolt_rounded,
        size: compact ? 27 : 32,
        color: light ? Colors.white : ink,
      ),
      const SizedBox(width: 2),
      Text(
        'STRIDE',
        style: TextStyle(
          fontSize: compact ? 17 : 20,
          fontWeight: FontWeight.w900,
          letterSpacing: .4,
          color: light ? Colors.white : ink,
          height: 1,
        ),
      ),
    ],
  );
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.label, {super.key, this.icon});
  final String label;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (icon != null) ...[
        Icon(icon, size: 14, color: forest),
        const SizedBox(width: 6),
      ],
      Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w800,
          color: forest,
        ),
      ),
    ],
  );
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 45,
    width: double.infinity,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: ink,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy)
            const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          else if (icon != null)
            Icon(icon, size: 16),
          if (busy || icon != null) const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 28,
          height: 1.12,
          letterSpacing: -0.7,
          fontWeight: FontWeight.w800,
          color: ink,
        ),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 7),
        Text(
          subtitle!,
          style: const TextStyle(fontSize: 13, height: 1.45, color: muted),
        ),
      ],
    ],
  );
}

class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF5E9),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFFE1C2)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.visibility_outlined,
          size: 16,
          color: Color(0xFFAA5C20),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF92521F),
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.active = true});
  final String label;
  final bool active;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: active ? mint : const Color(0xFFF0F1EF),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        height: 1.1,
        fontWeight: FontWeight.w700,
        color: active ? forest : muted,
      ),
    ),
  );
}

void showNotice(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}
