import '../../../../core/errors/app_failure.dart';
import '../../../../core/state/epoch_cache.dart';
import '../../../../core/state/read_snapshot.dart';
import '../../../../core/state/session_scope.dart';
import '../../domain/models/notification_page.dart';
import '../../domain/models/notification_query.dart';

/// Stateless predicates over caller-supplied live inputs, not authorization.
/// Callers retain receipt/lifecycle ownership and must recheck after awaits.
abstract final class NotificationSnapshotProjection {
  static String queryKey(NotificationQuery query) =>
      '${query.filter.wireValue}/${query.limit}/${query.cursor ?? ''}';

  static String resourceKey(NotificationQuery query) =>
      'notifications/list/${query.filter.name}/${query.limit}/${query.cursor}';

  static bool isFirstPageResource(String resource) {
    const prefix = 'notifications/list/';
    if (!resource.startsWith(prefix)) return false;
    final parts = resource.substring(prefix.length).split('/');
    return parts.length >= 3 && (parts[2].isEmpty || parts[2] == 'null');
  }

  static bool canRender(SessionScope scope, EpochCache cache) =>
      scope == cache.scope && cache.canRead && scope.canReadPrivateData;

  /// Receipt inputs belong to the owner; this method never records acceptance.
  static bool receiptMatches({
    required SessionScope scope,
    required EpochCache cache,
    required SessionScope? acceptedScope,
    required EpochCache? acceptedCache,
    required NotificationQuery query,
    required String? acceptedQueryKey,
  }) =>
      canRender(scope, cache) &&
      identical(cache, acceptedCache) &&
      scope == acceptedScope &&
      queryKey(query) == acceptedQueryKey;

  /// Stale identity matches may support display; they do not enable actions.
  static bool matchesPage(
    EpochCache cache,
    NotificationQuery query,
    ReadSnapshot<NotificationPage> snapshot,
  ) {
    final cached = cache.read<NotificationPage>(resourceKey(query));
    return cached != null &&
        snapshot.data != null &&
        identical(cached.data, snapshot.data);
  }

  static bool matchesCount(EpochCache cache, ReadSnapshot<int> snapshot) {
    final cached = cache.read<int>('notifications/count');
    return cached != null &&
        snapshot.data != null &&
        cached.data == snapshot.data;
  }

  /// Mirrors the page's current interaction preflight, including fresh head.
  /// The VM still owns current-item, canonical-ack and typed-target validation.
  static bool canInteract({
    required bool isActive,
    required AppFailure? accessFailure,
    required SessionScope scope,
    required EpochCache cache,
    required NotificationQuery query,
    required SessionScope? acceptedScope,
    required EpochCache? acceptedCache,
    required String? acceptedQueryKey,
    required ReadSnapshot<NotificationPage>? snapshot,
  }) {
    if (!isActive || accessFailure != null) return false;
    final cached = cache.read<NotificationPage>(resourceKey(query));
    final head = cache.read<NotificationPage>(
      resourceKey(NotificationQuery(filter: query.filter, limit: query.limit)),
    );
    return receiptMatches(
          scope: scope,
          cache: cache,
          acceptedScope: acceptedScope,
          acceptedCache: acceptedCache,
          query: query,
          acceptedQueryKey: acceptedQueryKey,
        ) &&
        cached != null &&
        !cached.stale &&
        head != null &&
        !head.stale &&
        snapshot?.isFresh == true;
  }

  static bool isAccessFailure(AppFailure? failure) =>
      failure?.code == AppFailure.unauthenticated ||
      failure?.code == AppFailure.forbiddenOrUnavailable;
}
