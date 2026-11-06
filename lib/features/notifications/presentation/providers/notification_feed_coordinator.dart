import '../../domain/models/notification_item.dart';
import '../../domain/models/notification_page.dart';
import '../../domain/models/notification_query.dart';

/// Accumulates accepted rows after the caller has checked scope and freshness.
/// Revisions and request IDs order local inputs; they confer no permissions.
class NotificationFeedCoordinator {
  NotificationFeedCoordinator({
    required this._revision,
    this._filter = NotificationFilter.all,
  });

  int _revision;
  NotificationFilter _filter;
  List<NotificationItem> _items = const [];
  String? _nextCursor;
  String? _activeCursor;
  final Set<String> _issuedCursors = {};
  int? _lastRequestId;
  bool _hasAcceptedHead = false;
  bool _isLoadingMore = false;
  bool _needsLoadMoreRetry = false;

  int get revision => _revision;
  NotificationFilter get filter => _filter;
  List<NotificationItem> get items => _items;
  String? get nextCursor => _nextCursor;
  String? get activeCursor => _activeCursor;
  bool get hasAcceptedHead => _hasAcceptedHead;
  bool get hasMore => _nextCursor != null;
  bool get isLoadingMore => _isLoadingMore;
  bool get needsLoadMoreRetry => _needsLoadMoreRetry;

  /// Starts a new query/owner namespace, always discarding private rows.
  bool reset({required int revision, NotificationFilter? filter}) {
    if (revision <= _revision) return false;
    _revision = revision;
    _filter = filter ?? _filter;
    _items = const [];
    _clearPagination();
    return true;
  }

  /// Retains presentation rows only for a caller-validated same-owner refresh.
  bool refreshHead({required int revision}) {
    if (revision <= _revision) return false;
    _revision = revision;
    _clearPagination();
    return true;
  }

  bool acceptHead({required int revision, required NotificationPage page}) {
    if (revision != _revision || _hasAcceptedHead) return false;
    _items = _merge(const [], page.items);
    _nextCursor = page.nextCursor;
    _hasAcceptedHead = true;
    return true;
  }

  /// Returns the unchanged cursor for a new local intent, without issuing IO.
  String? beginLoadMore({required int revision, required int requestId}) {
    final cursor = _nextCursor;
    if (revision != _revision ||
        !_hasAcceptedHead ||
        _isLoadingMore ||
        _needsLoadMoreRetry ||
        cursor == null ||
        cursor == _activeCursor ||
        !_isNewRequest(requestId)) {
      return null;
    }
    _activeCursor = cursor;
    _issuedCursors.add(cursor);
    _startAttempt(requestId);
    return cursor;
  }

  bool acceptTail({
    required int revision,
    required int requestId,
    required NotificationPage page,
  }) {
    if (!_matchesPending(revision, requestId)) return false;
    _items = _merge(_items, page.items);
    final candidate = page.nextCursor;
    _nextCursor =
        candidate == null ||
            candidate == _activeCursor ||
            _issuedCursors.contains(candidate)
        ? null
        : candidate;
    _isLoadingMore = false;
    _needsLoadMoreRetry = false;
    return true;
  }

  bool recordLoadMoreFailure({required int revision, required int requestId}) {
    if (!_matchesPending(revision, requestId)) return false;
    _isLoadingMore = false;
    _needsLoadMoreRetry = true;
    return true;
  }

  String? retryLoadMore({required int revision, required int requestId}) {
    final cursor = _activeCursor;
    if (revision != _revision ||
        !_needsLoadMoreRetry ||
        _isLoadingMore ||
        cursor == null ||
        !_isNewRequest(requestId)) {
      return null;
    }
    _startAttempt(requestId);
    return cursor;
  }

  bool _isNewRequest(int requestId) =>
      _lastRequestId == null || requestId > _lastRequestId!;

  bool _matchesPending(int revision, int requestId) =>
      revision == _revision && _isLoadingMore && requestId == _lastRequestId;

  void _startAttempt(int requestId) {
    _lastRequestId = requestId;
    _isLoadingMore = true;
    _needsLoadMoreRetry = false;
  }

  void _clearPagination() {
    _nextCursor = null;
    _activeCursor = null;
    _issuedCursors.clear();
    _lastRequestId = null;
    _hasAcceptedHead = false;
    _isLoadingMore = false;
    _needsLoadMoreRetry = false;
  }

  // Insertion order preserves positions; the latest projection for an ID wins.
  static List<NotificationItem> _merge(
    List<NotificationItem> current,
    List<NotificationItem> incoming,
  ) {
    final byId = <String, NotificationItem>{
      for (final item in current) item.id: item,
    };
    for (final item in incoming) {
      byId[item.id] = item;
    }
    return List<NotificationItem>.unmodifiable(byId.values);
  }
}
