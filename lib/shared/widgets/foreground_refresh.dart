import 'dart:async';

import 'package:flutter/material.dart';

/// Foreground freshness policy; loaders/retries/cache remain in the ViewModel.
/// The caller refuses polling while a read or non-retryable failure is active.
class ForegroundRefresh extends StatefulWidget {
  const ForegroundRefresh({
    required this.child,
    required this.onRefresh,
    required this.canRefresh,
    this.enabled = true,
    this.interval = const Duration(seconds: 3),
    super.key,
  });
  final Widget child;
  final VoidCallback onRefresh;
  final bool Function() canRefresh;
  final bool enabled;
  final Duration interval;

  @override
  State<ForegroundRefresh> createState() => _ForegroundRefreshState();
}

class _ForegroundRefreshState extends State<ForegroundRefresh>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;
  bool? _wasCurrent;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _start();
  }

  @override
  void didUpdateWidget(ForegroundRefresh oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.interval != widget.interval) {
      _start();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (_wasCurrent == false && current) scheduleMicrotask(_refresh);
    _wasCurrent = current;
  }

  void _start() {
    _timer?.cancel();
    if (widget.enabled) {
      _timer = Timer.periodic(widget.interval, (_) => _refresh());
    }
  }

  void _refresh() {
    if (!mounted ||
        !widget.enabled ||
        !_foreground ||
        !_visible ||
        ModalRoute.of(context)?.isCurrent == false ||
        !widget.canRefresh()) {
      return;
    }
    widget.onRefresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
