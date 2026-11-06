import '../../../../../core/state/epoch_cache.dart';
import '../../../../../core/state/session_scope.dart';
import '../../../domain/models/notification_query.dart';
import '../../providers/notification_page_read_coordinator.dart';
import '../../providers/notification_snapshot_projection.dart';

/// Revocable display cell, not a canonical cache or authorization authority.
/// The opener validates its live lease/receipt before constructing this handle.
class NotificationContextHandle {
  NotificationContextHandle({
    required NotificationReadNamespace namespace,
    required this.recipientId,
    required this.query,
    required String title,
    required String body,
  }) : scope = namespace.scope,
       cache = namespace.cache,
       _content = (title: title, body: body) {
    _cancelCache = cache.listen((_) {
      if (!cache.canRead) revoke();
    });
    read(scope, cache);
  }

  final SessionScope scope;
  final EpochCache cache;
  final String recipientId;
  final NotificationQuery query;
  ({String title, String body})? _content;
  final _listeners = <void Function()>[];
  void Function()? _cancelCache;
  bool _released = false;
  bool get isRevoked => _content == null;

  ({String title, String body})? read(
    SessionScope liveScope,
    EpochCache liveCache,
  ) {
    if (_released ||
        liveScope != scope ||
        !identical(liveCache, cache) ||
        recipientId != liveScope.userId ||
        !NotificationSnapshotProjection.canRender(liveScope, liveCache)) {
      revoke();
    }
    return _content;
  }

  void Function() listen(void Function() listener) {
    if (_released) return () {};
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Irreversible: recovery needs a newly authorized display cell.
  void revoke() {
    if (_content == null) return;
    _content = null;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  /// Route completion/disposal owns release; host disposal alone need not pop it.
  void release() {
    if (_released) return;
    _released = true;
    _cancelCache?.call();
    _cancelCache = null;
    revoke();
    _listeners.clear();
  }
}
