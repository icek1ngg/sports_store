import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/presentation_failure_message.dart';
import '../../../../core/state/epoch_cache.dart';
import '../../../../core/state/foundation_providers.dart';
import '../../../../core/state/read_snapshot.dart';
import '../../../../core/state/session_scope.dart';
import '../../../../shared/widgets/async_content.dart';
import '../../../../shared/widgets/feature_access_gate.dart';
import '../../../../shared/widgets/foreground_refresh.dart';
import '../../domain/models/notification_item.dart';
import '../../domain/models/notification_page.dart';
import '../../domain/models/notification_query.dart';
import '../../domain/models/notification_target.dart';
import '../../presentation/view_models/notification_interaction_view_model.dart';
import '../../presentation/view_models/notification_providers.dart';
import '../../presentation/widgets/notification_tile.dart';
import '../../presentation/widgets/unread_badge.dart';

/// MH17 — the recipient-scoped in-app notification center.
///
/// Cursor pages are combined only in this widget.  The foundation providers
/// remain the canonical query snapshots and continue to own their epoch and
/// session cache rules.
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({
    this.onNavigate,
    this.enablePolling = true,
    super.key,
  });

  final Future<bool> Function(NotificationTargetDecision)? onNavigate;
  final bool enablePolling;

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  static const _pageSize = 20;

  NotificationFilter _filter = NotificationFilter.all;
  String? _cursor;
  String? _acceptedQueryKey;
  String? _nextCursor;
  List<NotificationItem> _items = const <NotificationItem>[];
  final Set<String> _cursorHistory = <String>{};
  bool _loadingMore = false;
  bool _resetScheduled = false;
  VoidCallback? _cancelCacheListener;
  EpochCache? _observedCache;
  ProviderSubscription<SessionScope>? _sessionSubscription;
  ProviderSubscription<EpochCache>? _cacheSubscription;
  SessionScope? _renderScope;
  EpochCache? _pageSnapshotCache;
  SessionScope? _pageSnapshotScope;
  String? _pageSnapshotQueryKey;
  EpochCache? _countSnapshotCache;
  SessionScope? _countSnapshotScope;

  @override
  void initState() {
    super.initState();
    _cacheSubscription = ref.listenManual<EpochCache>(
      epochCacheProvider,
      (previous, next) => _observeCache(next),
      fireImmediately: true,
    );
    _sessionSubscription = ref.listenManual<SessionScope>(
      featureSessionScopeProvider,
      (previous, next) {
        if (previous == null || previous == next) return;
        _resetPagination();
      },
      fireImmediately: false,
    );
  }

  @override
  void dispose() {
    _sessionSubscription?.close();
    _cacheSubscription?.close();
    _cancelCacheListener?.call();
    super.dispose();
  }

  void _observeCache(EpochCache cache) {
    if (identical(_observedCache, cache)) return;
    _cancelCacheListener?.call();
    _observedCache = cache;
    _cancelCacheListener = cache.listen(_onCacheInvalidated);
  }

  @override
  Widget build(BuildContext context) {
    // Resolve the namespace before constructing the query.  A session change
    // must request the new account's first page; otherwise the old cursor can
    // briefly drive a second-page request while the stateful widget is
    // waiting for the keyed access gate to rebuild.
    final scope = ref.watch(featureSessionScopeProvider);
    final cache = ref.watch(epochCacheProvider);
    if (_renderScope != scope) {
      // The stateful page lives above FeatureAccessGate.  Clear local cursor
      // rows before rendering the first frame of a new account namespace.
      _renderScope = scope;
      _cursor = null;
      _acceptedQueryKey = null;
      _nextCursor = null;
      _items = const <NotificationItem>[];
      _loadingMore = false;
      _cursorHistory.clear();
      _pageSnapshotCache = null;
      _pageSnapshotScope = null;
      _pageSnapshotQueryKey = null;
      _countSnapshotCache = null;
      _countSnapshotScope = null;
    }

    final query = NotificationQuery(
      filter: _filter,
      limit: _pageSize,
      cursor: _cursor,
    );
    final queryKey = _queryKey(query);
    final pageAsync = ref.watch(notificationPageFoundationProvider(query));
    final countAsync = ref.watch(unreadCountFoundationProvider);
    final interaction = ref.watch(notificationInteractionViewModelProvider);
    final snapshot = pageAsync.asData?.value;
    final renderDataAllowed =
        scope == cache.scope && cache.canRead && scope.canReadPrivateData;
    final cachedPage = renderDataAllowed
        ? cache.read<NotificationPage>(_resourceKey(query))
        : null;
    if (cachedPage != null &&
        snapshot?.data != null &&
        identical(cachedPage.data, snapshot!.data)) {
      _pageSnapshotCache = cache;
      _pageSnapshotScope = scope;
      _pageSnapshotQueryKey = queryKey;
    }
    final snapshotBelongsToCurrentScope =
        renderDataAllowed &&
        identical(_pageSnapshotCache, cache) &&
        _pageSnapshotScope == scope &&
        _pageSnapshotQueryKey == queryKey;
    final page = snapshotBelongsToCurrentScope ? snapshot?.data : null;

    ref.listen<AsyncValue<ReadSnapshot<NotificationPage>>>(
      notificationPageFoundationProvider(query),
      (previous, next) {
        final nextSnapshot = next.asData?.value;
        final nextPage = nextSnapshot?.data;
        if (!mounted ||
            ref.read(featureSessionScopeProvider) != scope ||
            !identical(ref.read(epochCacheProvider), cache)) {
          return;
        }
        if (nextPage != null) {
          final cached = cache.read<NotificationPage>(_resourceKey(query));
          if (cached == null || !identical(cached.data, nextPage)) return;
        }
        _pageSnapshotCache = cache;
        _pageSnapshotScope = scope;
        _pageSnapshotQueryKey = queryKey;
        if (nextPage == null) {
          if (nextSnapshot?.failure != null &&
              query.cursor != null &&
              queryKey == _queryKey(_currentQuery) &&
              _loadingMore) {
            setState(() => _loadingMore = false);
          }
          return;
        }
        if (!nextSnapshot!.isFresh) return;
        _acceptPage(scope, cache, query, queryKey, nextPage);
      },
    );
    ref.listen<AsyncValue<ReadSnapshot<int>>>(
      unreadCountFoundationProvider,
      (previous, next) {
        if (!mounted ||
            ref.read(featureSessionScopeProvider) != scope ||
            !identical(ref.read(epochCacheProvider), cache)) {
          return;
        }
        final nextSnapshot = next.asData?.value;
        if (nextSnapshot?.data != null) {
          final cached = cache.read<int>('notifications/count');
          if (cached == null || cached.data != nextSnapshot!.data) return;
        }
        _countSnapshotCache = cache;
        _countSnapshotScope = scope;
      },
    );

    final visibleItems = _visibleItems(query, queryKey, page);
    final visibleNextCursor = _acceptedQueryKey == queryKey
        ? _nextCursor
        : query.cursor != null
        ? _nextCursor
        : page?.nextCursor;
    final countSnapshot = countAsync.asData?.value;
    final cachedCount = renderDataAllowed
        ? cache.read<int>('notifications/count')
        : null;
    if (cachedCount != null &&
        countSnapshot != null &&
        cachedCount.data == countSnapshot.data) {
      _countSnapshotCache = cache;
      _countSnapshotScope = scope;
    }
    final countBelongsToCurrentScope =
        renderDataAllowed &&
        identical(_countSnapshotCache, cache) &&
        _countSnapshotScope == scope;
    final count = countBelongsToCurrentScope ? countSnapshot?.data : null;
    final pageFailure = snapshotBelongsToCurrentScope
        ? snapshot?.failure
        : null;
    final countNeedsFreshnessNotice =
        countBelongsToCurrentScope &&
        (countSnapshot?.stale == true || countSnapshot?.failure != null);

    final actionsEnabled =
        snapshotBelongsToCurrentScope && snapshot?.isFresh == true;
    final hasVisibleData = page != null || visibleItems.isNotEmpty;
    return FeatureAccessGate(
      roles: const {'customer', 'manager', 'shipper'},
      child: ForegroundRefresh(
        enabled: widget.enablePolling,
        canRefresh: () => _canPoll(query),
        onRefresh: () => _poll(query),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Thông báo'),
            actions: [
              if (count != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 12),
                  child: UnreadBadge(count: count),
                ),
            ],
          ),
          body: Column(
            children: [
              _FilterBar(
                filter: _filter,
                onChanged: _setFilter,
                onRefresh: _refreshFirstPage,
              ),
              Expanded(
                child: AsyncContent(
                  hasData: hasVisibleData,
                  isInitialLoading:
                      !hasVisibleData &&
                      (!snapshotBelongsToCurrentScope ||
                          snapshot?.isInitialLoading == true ||
                          pageAsync.isLoading),
                  isRefreshing:
                      snapshotBelongsToCurrentScope &&
                      snapshot?.loading == true &&
                      hasVisibleData,
                  isEmpty: visibleItems.isEmpty &&
                      (snapshotBelongsToCurrentScope &&
                          (snapshot?.empty ?? false)),
                  failure: pageFailure,
                  errorMessage: pageFailure == null
                      ? null
                      : failureMessage(pageFailure),
                  isStale:
                      (snapshotBelongsToCurrentScope &&
                          (snapshot?.stale ?? false)) ||
                      countNeedsFreshnessNotice,
                  emptyMessage: _filter == NotificationFilter.unread
                      ? 'Không có thông báo chưa đọc'
                      : 'Chưa có thông báo',
                  onRetry: _refreshFirstPage,
                  child: RefreshIndicator(
                    onRefresh: _refreshFirstPage,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount:
                          visibleItems.length +
                          (visibleNextCursor == null ? 0 : 1),
                      itemBuilder: (context, index) {
                        if (index >= visibleItems.length) {
                          final canLoadMore = query.cursor != null
                              ? pageFailure != null ||
                                    (snapshotBelongsToCurrentScope &&
                                        snapshot?.isFresh == true)
                              : actionsEnabled;
                          return _LoadMoreButton(
                            loading: _loadingMore,
                            onPressed: !canLoadMore
                                ? null
                                : pageFailure != null
                                ? () => _retryLoadMore(query)
                                : () => _loadMore(visibleItems, queryKey),
                          );
                        }
                        final item = visibleItems[index];
                        return NotificationTile(
                          key: ValueKey(item.id),
                          notification: item,
                          isPendingRead:
                              actionsEnabled &&
                              interaction.isReadPending(item.id),
                          onMarkRead: actionsEnabled && !item.isRead
                              ? () => unawaited(_markRead(item))
                              : null,
                          onTap: () => unawaited(_open(item)),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _canPoll(NotificationQuery query) {
    if (!mounted) return false;
    final scope = ref.read(featureSessionScopeProvider);
    final cache = ref.read(epochCacheProvider);
    if (!scope.canReadPrivateData || !cache.canRead || cache.scope != scope) {
      return false;
    }
    final page = ref
        .read(notificationPageFoundationProvider(query))
        .asData
        ?.value;
    final count = ref.read(unreadCountFoundationProvider).asData?.value;
    final pageCanRefresh =
        page != null &&
        page.data != null &&
        !page.loading &&
        page.failure == null &&
        _snapshotMatchesCache(cache, query, page);
    final countCanRefresh =
        count != null &&
        count.data != null &&
        !count.loading &&
        count.failure == null &&
        _countSnapshotMatchesCache(cache, count);
    return pageCanRefresh || countCanRefresh;
  }

  void _poll(NotificationQuery query) {
    if (!mounted) return;
    final scope = ref.read(featureSessionScopeProvider);
    final cache = ref.read(epochCacheProvider);
    if (!scope.canReadPrivateData || !cache.canRead || cache.scope != scope) {
      return;
    }
    final page = ref
        .read(notificationPageFoundationProvider(query))
        .asData
        ?.value;
    final count = ref.read(unreadCountFoundationProvider).asData?.value;
    if (page != null &&
        page.data != null &&
        !page.loading &&
        page.failure == null &&
        _snapshotMatchesCache(cache, query, page)) {
      final headQuery = NotificationQuery(
        filter: query.filter,
        limit: query.limit,
      );
      if (query.cursor != null) _resetPagination(clearItems: false);
      unawaited(
        ref
            .read(notificationPageFoundationProvider(headQuery).notifier)
            .refresh(),
      );
    }
    if (count != null &&
        count.data != null &&
        !count.loading &&
        count.failure == null &&
        _countSnapshotMatchesCache(cache, count)) {
      unawaited(ref.read(unreadCountFoundationProvider.notifier).refresh());
    }
  }

  List<NotificationItem> _visibleItems(
    NotificationQuery query,
    String queryKey,
    NotificationPage? page,
  ) {
    if (_acceptedQueryKey == queryKey) return _items;
    if (query.cursor == null) return page?.items ?? _items;
    return _items.isEmpty
        ? (page?.items ?? const <NotificationItem>[])
        : _items;
  }

  void _acceptPage(
    SessionScope scope,
    EpochCache cache,
    NotificationQuery query,
    String queryKey,
    NotificationPage page,
  ) {
    if (!mounted ||
        ref.read(featureSessionScopeProvider) != scope ||
        !identical(ref.read(epochCacheProvider), cache) ||
        queryKey != _queryKey(_currentQuery)) {
      return;
    }
    final isFirstPage = query.cursor == null;
    if (isFirstPage) _cursorHistory.clear();
    final candidateCursor = page.nextCursor;
    final safeNextCursor = candidateCursor == null ||
            candidateCursor == query.cursor ||
            _cursorHistory.contains(candidateCursor)
        ? null
        : candidateCursor;
    final merged = isFirstPage
        ? _deduplicate(page.items)
        : _mergeItems(_items, page.items);
    setState(() {
      _items = merged;
      _acceptedQueryKey = queryKey;
      _nextCursor = safeNextCursor;
      _loadingMore = false;
    });
  }

  void _setFilter(NotificationFilter filter) {
    if (filter == _filter) return;
    _resetPagination();
    setState(() {
      _filter = filter;
    });
  }

  void _loadMore(List<NotificationItem> visibleItems, String queryKey) {
    if (_loadingMore || _nextCursor == null) return;
    final cursor = _nextCursor;
    if (cursor == null) return;
    if (cursor == _cursor) return;
    _cursorHistory.add(cursor);
    setState(() {
      _loadingMore = true;
      if (_acceptedQueryKey != queryKey) {
        _items = _deduplicate(visibleItems);
        _acceptedQueryKey = queryKey;
      }
      _cursor = cursor;
    });
  }

  void _retryLoadMore(NotificationQuery query) {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    unawaited(
      ref.read(notificationPageFoundationProvider(query).notifier).refresh(),
    );
  }

  NotificationQuery get _currentQuery =>
      NotificationQuery(filter: _filter, limit: _pageSize, cursor: _cursor);

  Future<void> _refreshFirstPage() async {
    if (!mounted) return;
    _resetPagination(clearItems: false);
    final query = NotificationQuery(filter: _filter, limit: _pageSize);
    final pageNotifier = ref.read(
      notificationPageFoundationProvider(query).notifier,
    );
    final countNotifier = ref.read(unreadCountFoundationProvider.notifier);
    await Future.wait<void>([pageNotifier.refresh(), countNotifier.refresh()]);
  }

  void _resetPagination({bool clearItems = true}) {
    if (!mounted) return;
    setState(() {
      _cursor = null;
      _acceptedQueryKey = null;
      _nextCursor = null;
      if (clearItems) _items = const <NotificationItem>[];
      _loadingMore = false;
      _cursorHistory.clear();
    });
  }

  void _onCacheInvalidated(String resource) {
    if (!_isFirstPageResource(resource)) return;
    if (_resetScheduled) return;
    _resetScheduled = true;
    final observedCache = _observedCache;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resetScheduled = false;
      if (mounted && identical(_observedCache, observedCache)) {
        _resetPagination(clearItems: !(observedCache?.canRead ?? false));
      }
    });
  }

  Future<void> _markRead(NotificationItem item) async {
    if (!mounted) return;
    final submittedScope = ref.read(featureSessionScopeProvider);
    final ok = await ref
        .read(notificationInteractionViewModelProvider.notifier)
        .markRead(item);
    if (ok && mounted && ref.read(featureSessionScopeProvider) == submittedScope) {
      _resetPagination(clearItems: false);
    }
    if (!mounted ||
        ok ||
        ref.read(featureSessionScopeProvider) != submittedScope) {
      return;
    }
    final failure = ref
        .read(notificationInteractionViewModelProvider)
        .failureFor(item.id);
    _showMessage(failureMessage(failure));
  }

  Future<void> _open(NotificationItem item) async {
    if (!mounted) return;
    final submittedScope = ref.read(featureSessionScopeProvider);
    final interaction =
        ref.read(notificationInteractionViewModelProvider.notifier);
    final readFuture = item.isRead
        ? Future<bool>.value(true)
        : interaction.markRead(item);
    unawaited(_resetAfterRead(readFuture, submittedScope));
    final rawType = item.subjectType.rawValue;
    if (rawType == NotificationSubjectType.notificationOnly.rawValue) {
      // The read action still runs, but there is no external target to fetch.
      unawaited(
        interaction.openNotification(item, onNavigate: widget.onNavigate),
      );
      if (mounted && ref.read(featureSessionScopeProvider) == submittedScope) {
        await _showNotificationContext(item, submittedScope);
      }
      return;
    }

    final navigated = await interaction.openNotification(
      item,
      onNavigate: widget.onNavigate,
    );
    if (!mounted ||
        navigated ||
        ref.read(featureSessionScopeProvider) != submittedScope) {
      return;
    }
    final state = ref.read(notificationInteractionViewModelProvider);
    final failure = state.failureFor(item.id);
    _showMessage(
      state.lastUnavailableMessageKey != null || failure == null
          ? 'Mục tiêu thông báo hiện chưa khả dụng.'
          : failureMessage(failure),
    );
  }

  Future<void> _resetAfterRead(
    Future<bool> readFuture,
    SessionScope submittedScope,
  ) async {
    if (!await readFuture ||
        !mounted ||
        ref.read(featureSessionScopeProvider) != submittedScope) {
      return;
    }
    _resetPagination(clearItems: false);
  }

  Future<void> _showNotificationContext(
    NotificationItem item,
    SessionScope submittedScope,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Consumer(
        builder: (context, modalRef, _) {
          final currentScope = modalRef.watch(featureSessionScopeProvider);
          if (currentScope != submittedScope ||
              !currentScope.canReadPrivateData) {
            return const SessionExpiredState();
          }
          return FeatureAccessGate(
            roles: const {'customer', 'manager', 'shipper'},
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(item.body),
                    const SizedBox(height: 20),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Đóng'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static String _baseKey(NotificationQuery query) =>
      '${query.filter.wireValue}/${query.limit}';

  static bool _isFirstPageResource(String resource) {
    const prefix = 'notifications/list/';
    if (!resource.startsWith(prefix)) return false;
    final parts = resource.substring(prefix.length).split('/');
    return parts.length >= 3 && (parts[2].isEmpty || parts[2] == 'null');
  }

  static String _queryKey(NotificationQuery query) =>
      '${_baseKey(query)}/${query.cursor ?? ''}';

  static String _resourceKey(NotificationQuery query) =>
      'notifications/list/${query.filter.name}/${query.limit}/${query.cursor}';

  static bool _snapshotMatchesCache(
    EpochCache cache,
    NotificationQuery query,
    ReadSnapshot<NotificationPage> snapshot,
  ) {
    final cached = cache.read<NotificationPage>(_resourceKey(query));
    return cached != null &&
        snapshot.data != null &&
        identical(cached.data, snapshot.data);
  }

  static bool _countSnapshotMatchesCache(
    EpochCache cache,
    ReadSnapshot<int> snapshot,
  ) {
    final cached = cache.read<int>('notifications/count');
    return cached != null &&
        snapshot.data != null &&
        cached.data == snapshot.data;
  }

  static List<NotificationItem> _deduplicate(List<NotificationItem> items) {
    final byId = <String, NotificationItem>{};
    for (final item in items) {
      byId[item.id] = item;
    }
    return byId.values.toList(growable: false);
  }

  static List<NotificationItem> _mergeItems(
    List<NotificationItem> current,
    List<NotificationItem> next,
  ) {
    final byId = <String, NotificationItem>{
      for (final item in current) item.id: item,
    };
    final order = current.map((item) => item.id).toList(growable: true);
    for (final item in next) {
      if (!byId.containsKey(item.id)) order.add(item.id);
      byId[item.id] = item;
    }
    return [for (final id in order) byId[id]!];
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.onChanged,
    required this.onRefresh,
  });

  final NotificationFilter filter;
  final ValueChanged<NotificationFilter> onChanged;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Tất cả'),
                    selected: filter == NotificationFilter.all,
                    onSelected: (_) => onChanged(NotificationFilter.all),
                  ),
                  ChoiceChip(
                    label: const Text('Chưa đọc'),
                    selected: filter == NotificationFilter.unread,
                    onSelected: (_) => onChanged(NotificationFilter.unread),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Làm mới',
              onPressed: () => unawaited(onRefresh()),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : OutlinedButton(
                onPressed: onPressed,
                child: const Text('Tải thêm'),
              ),
      ),
    );
  }
}
