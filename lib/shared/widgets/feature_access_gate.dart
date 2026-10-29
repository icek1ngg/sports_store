import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/epoch_cache.dart';
import '../../core/state/foundation_providers.dart';
import 'async_content.dart';

/// Presentation boundary only. Actual authorization belongs to Auth/backend.
/// Keying content by the trusted scope also discards local UI state on switch.
class FeatureAccessGate extends ConsumerStatefulWidget {
  const FeatureAccessGate({
    required this.roles,
    required this.child,
    super.key,
  });
  final Set<String> roles;
  final Widget child;

  @override
  ConsumerState<FeatureAccessGate> createState() => _FeatureAccessGateState();
}

class _FeatureAccessGateState extends ConsumerState<FeatureAccessGate> {
  EpochCache? _cache;
  void Function()? _cancel;

  @override
  void dispose() {
    _cancel?.call();
    super.dispose();
  }

  void _observe(EpochCache cache) {
    if (identical(_cache, cache)) return;
    _cancel?.call();
    _cache = cache;
    _cancel = cache.listen((_) {
      if (!cache.canRead) {
        scheduleMicrotask(() {
          if (mounted && identical(_cache, cache)) setState(() {});
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(featureSessionScopeProvider);
    final cache = ref.watch(epochCacheProvider);
    _observe(cache);
    if (!scope.roleResolved) {
      return const LoadingState(label: 'Đang xác nhận phiên đăng nhập');
    }
    if (scope.userId == null) return const SessionExpiredState();
    if (!scope.canReadPrivateData || !widget.roles.contains(scope.role)) {
      return const SessionUnavailableState();
    }
    if (!cache.canRead) return const SessionExpiredState();
    return KeyedSubtree(key: ValueKey(scope), child: widget.child);
  }
}
