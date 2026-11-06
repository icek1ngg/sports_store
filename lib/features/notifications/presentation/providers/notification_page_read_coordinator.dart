import 'dart:async';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/state/epoch_cache.dart';
import '../../../../core/state/read_snapshot.dart';
import '../../../../core/state/session_scope.dart';
import '../../domain/models/notification_item.dart';
import '../../domain/models/notification_page.dart';
import '../../domain/models/notification_query.dart';
import 'notification_feed_coordinator.dart';
import 'notification_page_session_bridge.dart';
import 'notification_snapshot_projection.dart';

typedef NotificationReadNamespace = ({
  SessionScope scope,
  EpochCache cache,
  Object? lease,
});
typedef NotificationReadIntent = ({
  NotificationReadNamespace namespace,
  int revision,
  int? requestId,
  String? cursor,
});
typedef NotificationReadPorts = ({
  NotificationReadNamespace Function() current,
  ReadSnapshot<NotificationPage>? Function(NotificationQuery) page,
  ReadSnapshot<int>? Function() count,
  Future<void> Function(NotificationQuery) refreshPage,
  Future<void> Function() refreshCount,
  void Function() invalidateInteractions,
});

/// Local ordering only. Foundation/interaction owners retain business authority.
class NotificationPageReadCoordinator {
  NotificationPageReadCoordinator({required this.session, this.pageSize = 20}) {
    NotificationQuery(limit: pageSize);
  }
  final NotificationPageSessionBridge session;
  final int pageSize;
  final _feed = NotificationFeedCoordinator(revision: 0);
  NotificationReadNamespace? _namespace;
  String? _receiptQuery;
  AppFailure? _accessFailure;
  (SessionScope, EpochCache)? _denialOwner;
  ({NotificationReadIntent intent, ReadSnapshot<NotificationPage> snapshot})?
  _recovery;
  int _requestId = 0, _selfRefresh = 0;
  bool _disposed = false;
  bool _handoffPending = false, _handoffCountObserved = false;
  int get revision => _feed.revision;
  NotificationFilter get filter => _feed.filter;
  List<NotificationItem> get items => _feed.items;
  String? get nextCursor => _feed.nextCursor;
  String? get cursor => _feed.activeCursor;
  bool get isLoadingMore => _feed.isLoadingMore;
  bool get needsLoadMoreRetry => _feed.needsLoadMoreRetry;
  AppFailure? get accessFailure => _accessFailure;
  NotificationQuery get headQuery =>
      NotificationQuery(filter: filter, limit: pageSize);

  /// Opt-in display transfer only; callers must supply their current query.
  /// A bridge callback that already reset this owner cannot restore old rows.
  bool synchronize(
    NotificationReadNamespace live, {
    bool preserveSameOwnerStaleDisplay = false,
    NotificationQuery? query,
  }) {
    if (_disposed) return false;
    if (!session.isCurrent(live.lease, live.scope, live.cache)) {
      if (_namespace != null) reset();
      return false;
    }
    final previous = _namespace;
    final compatible =
        previous != null &&
        previous.scope == live.scope &&
        query != null &&
        _queryMatches(_intent(), query) &&
        _accessFailure == null &&
        _denialOwner == null &&
        items.every((item) => item.recipientId == live.scope.userId);
    if (preserveSameOwnerStaleDisplay && !compatible) {
      reset();
      return false;
    }
    final preserve =
        preserveSameOwnerStaleDisplay &&
        compatible &&
        !identical(previous.cache, live.cache);
    // The denial belongs to a real owner/cache, never to a rotating UI lease.
    if (_denialOwner != null &&
        live.scope == live.cache.scope &&
        _denialOwner != (live.scope, live.cache)) {
      _denialOwner = null;
      _accessFailure = null;
    }
    if (_namespace != live) {
      _namespace = live;
      _arm(keepItems: preserve);
      _handoffPending = preserve;
    }
    return !_disposed;
  }

  void reset() {
    if (_disposed) return;
    _namespace = null;
    _arm(keepItems: false);
  }

  void _arm({bool keepItems = true}) {
    _recovery = null;
    _receiptQuery = null;
    _handoffCountObserved = false;
    if (!keepItems) _handoffPending = false;
    if (keepItems) {
      _feed.refreshHead(revision: revision + 1);
    } else {
      _feed.reset(revision: revision + 1);
    }
  }

  NotificationReadIntent _intent({int? requestId}) => (
    namespace: _namespace!,
    revision: revision,
    requestId: requestId,
    cursor: cursor,
  );
  NotificationReadIntent? headIntent(NotificationReadNamespace live) =>
      synchronize(live) && cursor == null ? _intent() : null;
  bool _prepare(NotificationReadPorts ports) =>
      !_disposed && synchronize(ports.current());
  bool _live(NotificationReadIntent intent, NotificationReadPorts ports) =>
      _prepare(ports) &&
      intent.namespace == _namespace &&
      intent.revision == revision &&
      intent.cursor == cursor &&
      (intent.requestId == null || intent.requestId == _requestId);
  bool _queryMatches(NotificationReadIntent intent, NotificationQuery query) =>
      query.filter == filter &&
      query.limit == pageSize &&
      query.cursor == intent.cursor;
  bool _fresh(
    EpochCache cache,
    NotificationQuery query,
    ReadSnapshot<NotificationPage>? snapshot,
  ) {
    final key = NotificationSnapshotProjection.resourceKey(query);
    return snapshot?.isFresh == true &&
        NotificationSnapshotProjection.matchesPage(cache, query, snapshot!) &&
        cache.read<NotificationPage>(key)?.stale == false;
  }

  bool acceptPage(
    NotificationReadIntent intent,
    NotificationQuery query,
    ReadSnapshot<NotificationPage> snapshot,
    NotificationReadPorts ports,
  ) {
    if (!_live(intent, ports) ||
        !_queryMatches(intent, query) ||
        !identical(ports.page(query), snapshot) ||
        _disposed) {
      return false;
    }
    if (NotificationSnapshotProjection.isAccessFailure(snapshot.failure)) {
      _deny(snapshot.failure!, ports);
      return false;
    }
    if (intent.requestId != null &&
        snapshot.failure?.code == AppFailure.invalidCursor) {
      _deferRecovery(intent, query, snapshot, ports);
      return false;
    }
    if (intent.requestId != null && snapshot.failure != null) {
      _feed.recordLoadMoreFailure(
        revision: intent.revision,
        requestId: intent.requestId!,
      );
      return false;
    }
    final cache = intent.namespace.cache;
    if (_accessFailure != null ||
        !_fresh(cache, query, snapshot) ||
        (intent.requestId != null &&
            !_fresh(cache, headQuery, ports.page(headQuery)))) {
      return false;
    }
    final accepted = intent.requestId == null
        ? _feed.acceptHead(revision: intent.revision, page: snapshot.data!)
        : _feed.acceptTail(
            revision: intent.revision,
            requestId: intent.requestId!,
            page: snapshot.data!,
          );
    if (accepted) {
      _receiptQuery = NotificationSnapshotProjection.queryKey(query);
    }
    return accepted;
  }

  void _deferRecovery(
    NotificationReadIntent intent,
    NotificationQuery query,
    ReadSnapshot<NotificationPage> snapshot,
    NotificationReadPorts ports,
  ) {
    final recovery = (intent: intent, snapshot: snapshot);
    if (_recovery == recovery || _accessFailure != null) return;
    _recovery = recovery;
    scheduleMicrotask(() {
      if (_recovery != recovery) return;
      _recovery = null;
      if (!_live(intent, ports) || _accessFailure != null) return;
      final current = ports.page(query);
      if (_live(intent, ports) &&
          identical(current, snapshot) &&
          current?.failure?.code == AppFailure.invalidCursor) {
        unawaited(refresh(ports));
      }
    });
  }

  bool observeCount(
    NotificationReadNamespace submitted,
    ReadSnapshot<int> snapshot,
    NotificationReadPorts ports,
  ) {
    if (!_prepare(ports) ||
        submitted != _namespace ||
        !identical(ports.count(), snapshot) ||
        _disposed) {
      return false;
    }
    if (NotificationSnapshotProjection.isAccessFailure(snapshot.failure)) {
      _deny(snapshot.failure!, ports);
    }
    final qualified =
        !_disposed &&
        _accessFailure == null &&
        NotificationSnapshotProjection.matchesCount(submitted.cache, snapshot);
    if (_handoffPending &&
        qualified &&
        _freshCount(submitted.cache, snapshot)) {
      _handoffCountObserved = true;
    }
    return qualified;
  }

  bool _freshCount(EpochCache cache, ReadSnapshot<int>? snapshot) =>
      snapshot?.isFresh == true &&
      NotificationSnapshotProjection.matchesCount(cache, snapshot!) &&
      cache.read<int>('notifications/count')?.stale == false;

  void _deny(AppFailure failure, NotificationReadPorts ports) {
    if (_disposed || _namespace == null) return;
    final alreadyDenied = _accessFailure != null;
    _accessFailure = failure;
    if (alreadyDenied) return;
    _denialOwner = (_namespace!.scope, _namespace!.cache);
    _arm(keepItems: false);
    ports.invalidateInteractions();
  }

  bool canInteract(NotificationReadPorts ports, NotificationQuery query) {
    if (!_prepare(ports) || query.cursor != cursor) {
      return false;
    }
    final intent = _intent();
    if (_handoffPending) {
      final count = ports.count();
      if (!_live(intent, ports) ||
          !_handoffCountObserved ||
          !_freshCount(intent.namespace.cache, count)) {
        return false;
      }
    }
    final allowed = NotificationSnapshotProjection.canInteract(
      isActive: !_disposed,
      accessFailure: _accessFailure,
      scope: _namespace!.scope,
      cache: _namespace!.cache,
      query: query,
      acceptedScope: _namespace!.scope,
      acceptedCache: _namespace!.cache,
      acceptedQueryKey: _receiptQuery,
      snapshot: ports.page(query),
    );
    if (!_live(intent, ports) || !allowed) return false;
    _handoffPending = false;
    return true;
  }

  NotificationReadIntent? beginLoadMore(
    NotificationReadPorts ports,
    NotificationQuery query, {
    bool retry = false,
  }) {
    if (!_prepare(ports) ||
        _accessFailure != null ||
        !_queryMatches(_intent(), query) ||
        !_fresh(_namespace!.cache, headQuery, ports.page(headQuery)) ||
        (!retry && !canInteract(ports, query))) {
      return null;
    }
    final requestId = _requestId + 1;
    final cursor = retry
        ? _feed.retryLoadMore(revision: revision, requestId: requestId)
        : _feed.beginLoadMore(revision: revision, requestId: requestId);
    if (cursor == null) return null;
    _requestId = requestId;
    return _disposed ? null : _intent(requestId: requestId);
  }

  void setFilter(NotificationFilter filter, NotificationReadNamespace live) {
    if (!synchronize(live) || filter == this.filter) return;
    _receiptQuery = null;
    _recovery = null;
    _handoffPending = false;
    _handoffCountObserved = false;
    _feed.reset(revision: revision + 1, filter: filter);
  }

  void onResourceInvalidated(String resource, NotificationReadPorts ports) {
    if (!_prepare(ports) ||
        _accessFailure != null ||
        _selfRefresh > 0 ||
        !NotificationSnapshotProjection.isFirstPageResource(resource) ||
        !_feed.hasAcceptedHead) {
      return;
    }
    _arm();
  }

  void afterCanonicalRead(
    bool acknowledged,
    int submittedRevision,
    NotificationReadPorts ports,
  ) {
    if (!acknowledged ||
        !_prepare(ports) ||
        _accessFailure != null ||
        submittedRevision != revision) {
      return;
    }
    if (cursor != null) _arm();
    final snapshot = ports.page(headQuery);
    if (snapshot != null) acceptPage(_intent(), headQuery, snapshot, ports);
  }

  Future<void> refresh(NotificationReadPorts ports) async {
    if (!_prepare(ports)) return;
    _arm(); // N01: armed before any refresh callback can publish immediately.
    final intent = _intent();
    if (!_live(intent, ports)) return;
    late Future<void> pageRead;
    _selfRefresh++;
    try {
      pageRead = ports.refreshPage(headQuery);
    } finally {
      _selfRefresh--;
    }
    if (!_live(intent, ports)) {
      await pageRead;
      return;
    }
    await Future.wait([pageRead, ports.refreshCount()]);
    if (!_live(intent, ports)) return;
    final page = ports.page(headQuery);
    if (_disposed) return;
    final count = ports.count();
    if (_disposed || page == null) return;
    final cache = intent.namespace.cache;
    if (_accessFailure != null &&
        _fresh(cache, headQuery, page) &&
        _freshCount(cache, count)) {
      _accessFailure =
          null; // Explicit recovery requires both canonical fresh reads.
      _denialOwner = null;
    }
    acceptPage(intent, headQuery, page, ports);
    if (_handoffPending && count != null) {
      observeCount(intent.namespace, count, ports);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _namespace = null;
    _accessFailure = null;
    _denialOwner = null;
    _arm(keepItems: false);
  }
}
