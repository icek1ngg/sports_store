import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/state/epoch_cache.dart';
import '../../../../core/state/foundation_providers.dart';
import '../../../../core/state/session_scope.dart';
import 'notification_snapshot_projection.dart';

/// Page-local signals only. A lease never replaces live permission checks.
class NotificationPageSessionBridge {
  NotificationPageSessionBridge({
    required void Function() onNamespaceChanged,
    required void Function(String) onResourceInvalidated,
  }) {
    _onNamespaceChanged = onNamespaceChanged;
    _onResourceInvalidated = onResourceInvalidated;
  }

  void Function()? _onNamespaceChanged;
  void Function(String)? _onResourceInvalidated;
  ProviderSubscription<SessionScope>? _scopeSubscription;
  ProviderSubscription<EpochCache>? _cacheSubscription;
  void Function()? _cancelCacheListener;
  SessionScope? _scope;
  EpochCache? _cache;
  Object _lease = Object();
  bool _readable = false;
  bool _attached = false;
  bool _disposed = false;

  /// Call in mounted initState, never build. Ref is used only for registration.
  void attach(WidgetRef ref) {
    if (_disposed || _attached) return;
    _attached = true;
    final scopeSubscription = ref.listenManual<SessionScope>(
      featureSessionScopeProvider,
      (previous, next) => _update(next, _cache),
      fireImmediately: true,
    );
    if (_disposed) {
      scopeSubscription.close();
      return;
    }
    _scopeSubscription = scopeSubscription;
    final cacheSubscription = ref.listenManual<EpochCache>(
      epochCacheProvider,
      (previous, next) => _update(_scope, next),
      fireImmediately: true,
    );
    if (_disposed) {
      cacheSubscription.close();
      return;
    }
    _cacheSubscription = cacheSubscription;
  }

  /// Required before private render, even when no cache event has been emitted.
  void synchronize(SessionScope liveScope, EpochCache liveCache) =>
      _update(liveScope, liveCache);

  Object? captureLease(SessionScope liveScope, EpochCache liveCache) {
    synchronize(liveScope, liveCache);
    return !_disposed && _readable ? _lease : null;
  }

  bool isCurrent(Object? lease, SessionScope liveScope, EpochCache liveCache) {
    synchronize(liveScope, liveCache);
    return !_disposed && _readable && identical(lease, _lease);
  }

  /// Invalidates captured callbacks; the owner still owns the denial latch.
  void revokeAccess() {
    if (_disposed) return;
    _lease = Object();
    _onNamespaceChanged?.call();
  }

  void _update(SessionScope? scope, EpochCache? cache) {
    if (_disposed) return;
    final readable =
        scope != null &&
        cache != null &&
        NotificationSnapshotProjection.canRender(scope, cache);
    final changed =
        scope != _scope || !identical(cache, _cache) || readable != _readable;
    if (!changed) return;
    if (!identical(cache, _cache)) {
      _cancelCacheListener?.call();
      _cancelCacheListener = cache?.listen(
        (resource) => _resourceInvalidated(cache, resource),
      );
    }
    _scope = scope;
    _cache = cache;
    _readable = readable;
    _lease = Object();
    _onNamespaceChanged?.call();
  }

  void _resourceInvalidated(EpochCache? cache, String resource) {
    if (_disposed || !identical(cache, _cache)) return;
    _update(_scope, cache);
    if (!_disposed && identical(cache, _cache)) {
      _onResourceInvalidated?.call(resource);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _scopeSubscription?.close();
    _cacheSubscription?.close();
    _cancelCacheListener?.call();
    _scopeSubscription = null;
    _cacheSubscription = null;
    _cancelCacheListener = null;
    _scope = null;
    _cache = null;
    _readable = false;
    _lease = Object();
    _onNamespaceChanged = null;
    _onResourceInvalidated = null;
  }
}
