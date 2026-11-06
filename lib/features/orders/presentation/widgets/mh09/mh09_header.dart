import 'package:flutter/material.dart';

/// MH09 header. Navigation and refresh remain owned by the parent.
class Mh09Header extends StatelessWidget {
  const Mh09Header({
    required this.canPop,
    this.isRefreshing = false,
    this.onBack,
    this.onRefresh,
    super.key,
  });

  final bool canPop;
  final bool isRefreshing;
  final VoidCallback? onBack;
  final VoidCallback? onRefresh;

  static const _title = 'CHI TIẾT ĐƠN HÀNG';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.headlineSmall?.copyWith(
      fontFamily: 'BarlowCondensed',
      fontFamilyFallback: const ['Inter'],
      fontSize: 28,
      height: 32 / 28,
      fontWeight: FontWeight.w700,
    );
    return Material(
      color: theme.colorScheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Quay lại',
                constraints: const BoxConstraints.tightFor(
                  width: 48,
                  height: 48,
                ),
                onPressed: canPop ? onBack : null,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Semantics(
                  header: true,
                  label: _title,
                  excludeSemantics: true,
                  child: Text(
                    _title,
                    textAlign: TextAlign.center,
                    softWrap: true,
                    style: titleStyle,
                  ),
                ),
              ),
              IconButton(
                tooltip: isRefreshing ? 'Đang tải lại' : 'Tải lại',
                constraints: const BoxConstraints.tightFor(
                  width: 48,
                  height: 48,
                ),
                onPressed: isRefreshing ? null : onRefresh,
                icon: isRefreshing
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
