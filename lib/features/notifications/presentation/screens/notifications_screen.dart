import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/presentation_failure_message.dart';
import '../../../../core/state/foundation_providers.dart';
import '../../../../core/state/read_snapshot.dart';
import '../../../../shared/widgets/feature_access_gate.dart';
import '../../../../shared/widgets/foreground_refresh.dart';
import '../../domain/models/notification_item.dart';
import '../../domain/models/notification_page.dart';
import '../../domain/models/notification_query.dart';
import '../../domain/models/notification_target.dart';
import '../providers/notification_interaction_view_model.dart';
import '../providers/notification_providers.dart';
import '../providers/notification_page_read_coordinator.dart';
import '../providers/notification_page_actions.dart';
import '../providers/notification_page_session_bridge.dart';
import '../providers/notification_snapshot_projection.dart';
import '../widgets/notifications_content.dart';
import '../widgets/mh17/notification_feed.dart';
import '../widgets/notifications_header.dart';
import '../widgets/mh17/notification_context_handle.dart';
import '../widgets/mh17/notification_context_modal.dart';

/// MH17 — the recipient-scoped in-app notification center.
///
/// Accepted cursor pages belong to the page-local read/feed owner. Foundation
/// remain the canonical query snapshots and continue to own their epoch and
/// session cache rules.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({
    this.onNavigate,
    this.enablePolling = true,
    super.key,
  });

  final Future<bool> Function(NotificationTargetDecision)? onNavigate;
  final bool enablePolling;

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  static const _pageSize = 20;

  late final NotificationPageSessionBridge _session;
  late final NotificationPageReadCoordinator _reads;
  late final NotificationPageActions _actions;
  NotificationReadNamespace? _namespace;
  NotificationReadIntent? _intent;
  bool _synchronizing = false;
  bool _building = false;
  NotificationFilter get _filter => _reads.filter;
  AppFailure? get _accessFailure => _reads.accessFailure;
  final _contextHandles = <NotificationContextHandle>{};

  @override
  void initState() {
    super.initState();
    _session = NotificationPageSessionBridge(
      onNamespaceChanged: () {
        if (_namespace != null) {
          _invalidateInteractions();
        } else {
          _revokeContexts();
        }
        // Revoke captured UI capabilities before choosing retain versus reset.
        _intent = null;
        if (!_synchronizing) _synchronizeNamespace();
      },
      onResourceInvalidated: _onCacheInvalidated,
    );
    _reads = NotificationPageReadCoordinator(session: _session);
    _actions = NotificationPageActions(session: _session, reads: _reads);
    _session.attach(ref);
  }

  @override
  void dispose() {
    // Routes own their handles; detach the Page's revocation links only.
    _contextHandles.clear();
    _actions.dispose();
    _reads.dispose();
    _session.dispose();
    super.dispose();
  }

  NotificationReadNamespace _synchronizeNamespace() {
    final scope = ref.read(featureSessionScopeProvider);
    final cache = ref.read(epochCacheProvider);
    final query = _currentQuery;
    final previous = _namespace;
    _synchronizing = true;
    try {
      final live = (
        scope: scope,
        cache: cache,
        lease: _session.captureLease(scope, cache),
      );
      final handoff =
          previous != null &&
          previous.scope == scope &&
          !identical(previous.cache, cache) &&
          NotificationSnapshotProjection.canRender(scope, cache);
      final synchronized = _reads.synchronize(
        live,
        preserveSameOwnerStaleDisplay: handoff,
        query: query,
      );
      _namespace = synchronized ? live : null;
      if (_intent?.namespace != live ||
          _intent?.revision != _reads.revision ||
          _intent?.cursor != _reads.cursor) {
        _intent = _reads.headIntent(live);
      }
      return live;
    } finally {
      _synchronizing = false;
    }
  }

  NotificationReadPorts get _ports => (
    current: _synchronizeNamespace,
    page: (query) =>
        ref.read(notificationPageFoundationProvider(query)).asData?.value,
    count: () => ref.read(unreadCountFoundationProvider).asData?.value,
    refreshPage: (query) {
      if (!mounted) return Future<void>.value();
      setState(() {
        _synchronizeNamespace();
      });
      return ref
          .read(notificationPageFoundationProvider(query).notifier)
          .refresh();
    },
    refreshCount: () =>
        ref.read(unreadCountFoundationProvider.notifier).refresh(),
    invalidateInteractions: _invalidateInteractions,
  );

  void _invalidateInteractions() {
    _revokeContexts();
    if (!_building) {
      ref.invalidate(notificationInteractionViewModelProvider);
      return;
    }
    // The read latch/lease revoke immediately. Provider scheduling must wait
    // until the build unwinds; an obsolete namespace must not invalidate a new VM.
    final scope = ref.read(featureSessionScopeProvider);
    final cache = ref.read(epochCacheProvider);
    scheduleMicrotask(() {
      if (mounted &&
          ref.read(featureSessionScopeProvider) == scope &&
          identical(ref.read(epochCacheProvider), cache)) {
        ref.invalidate(notificationInteractionViewModelProvider);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _building = true;
    try {
      final scope = ref.watch(featureSessionScopeProvider);
      final cache = ref.watch(epochCacheProvider);
      final live = _synchronizeNamespace();
      final query = _currentQuery;
      final intent = _intent;
      if (query.cursor != null) {
        ref.watch(notificationPageFoundationProvider(_reads.headQuery));
      }
      final pageAsync = ref.watch(notificationPageFoundationProvider(query));
      final countAsync = ref.watch(unreadCountFoundationProvider);
      final interaction = ref.watch(notificationInteractionViewModelProvider);
      final snapshot = pageAsync.asData?.value;
      final countSnapshot = countAsync.asData?.value;
      final renderDataAllowed = NotificationSnapshotProjection.canRender(
        scope,
        cache,
      );
      if (!renderDataAllowed) _revokeContexts();
      final snapshotBelongsToCurrentScope =
          renderDataAllowed &&
          snapshot != null &&
          NotificationSnapshotProjection.matchesPage(cache, query, snapshot);
      final countBelongsToCurrentScope =
          renderDataAllowed &&
          countSnapshot != null &&
          NotificationSnapshotProjection.matchesCount(cache, countSnapshot);
      // Bootstrap/adopt current canonical cache once; listeners use captured intents.
      if (countSnapshot != null) {
        _reads.observeCount(live, countSnapshot, _ports);
      }
      if (intent != null && snapshot != null) {
        _reads.acceptPage(intent, query, snapshot, _ports);
      }
      ref.listen<AsyncValue<ReadSnapshot<NotificationPage>>>(
        notificationPageFoundationProvider(query),
        (previous, next) {
          if (!mounted || intent == null) return;
          final nextSnapshot = next.asData?.value;
          if (nextSnapshot == null) return;
          setState(() {
            _reads.acceptPage(intent, query, nextSnapshot, _ports);
          });
        },
      );
      ref.listen<AsyncValue<ReadSnapshot<int>>>(unreadCountFoundationProvider, (
        previous,
        next,
      ) {
        if (!mounted) return;
        final nextSnapshot = next.asData?.value;
        if (nextSnapshot == null) return;
        setState(() {
          _reads.observeCount(live, nextSnapshot, _ports);
        });
      });
      final visibleItems = renderDataAllowed && _accessFailure == null
          ? _reads.items
          : const <NotificationItem>[];
      final page = snapshotBelongsToCurrentScope ? snapshot.data : null;
      final visibleNextCursor = _reads.nextCursor;
      final count = countBelongsToCurrentScope && _accessFailure == null
          ? countSnapshot.data
          : null;
      // Errors have no aggregate to match; the watched synchronous foundation
      // provider and captured live query still identify their current namespace.
      final pageFailure =
          _accessFailure ??
          (renderDataAllowed &&
                  intent?.namespace == live &&
                  query == _currentQuery
              ? snapshot?.failure
              : null);
      final countNeedsFreshnessNotice =
          countBelongsToCurrentScope &&
          (countSnapshot.stale || countSnapshot.failure != null);
      final actionsEnabled =
          query == _currentQuery && _reads.canInteract(_ports, query);
      final hasVisibleData =
          _accessFailure == null && (page != null || visibleItems.isNotEmpty);
      final canLoadMore = _reads.needsLoadMoreRetry
          ? renderDataAllowed && _accessFailure == null
          : actionsEnabled;
      return AppTheme.notificationsScope(
        child: FeatureAccessGate(
          roles: const {'customer', 'manager', 'shipper'},
          child: ForegroundRefresh(
            enabled: widget.enablePolling,
            canRefresh: () => _canPoll(query),
            onRefresh: () => _poll(query),
            child: Scaffold(
              appBar: notificationsHeader(unreadCount: count),
              body: NotificationsContent(
                filter: _filter,
                onFilterChanged: _setFilter,
                onRefresh: () => unawaited(_refreshFirstPage()),
                failure: pageFailure,
                feed: Mh17NotificationFeed(
                  items: visibleItems,
                  hasData: hasVisibleData,
                  filter: _filter,
                  isInitialLoading:
                      pageFailure == null &&
                      !hasVisibleData &&
                      (!snapshotBelongsToCurrentScope ||
                          snapshot.isInitialLoading ||
                          pageAsync.isLoading),
                  isRefreshing:
                      snapshotBelongsToCurrentScope &&
                      snapshot.loading &&
                      hasVisibleData,
                  errorMessage: pageFailure == null
                      ? null
                      : failureMessage(pageFailure),
                  isStale:
                      (snapshotBelongsToCurrentScope && snapshot.stale) ||
                      countNeedsFreshnessNotice,
                  onRetry: _refreshFirstPage,
                  onRefresh: _refreshFirstPage,
                  hasMore: visibleNextCursor != null,
                  isLoadingMore: _reads.isLoadingMore,
                  onLoadMore: !canLoadMore
                      ? null
                      : pageFailure != null
                      ? () => _retryLoadMore(query)
                      : _loadMore,
                  onOpen: actionsEnabled
                      ? (item) {
                          if (_canUseCaptured(intent, query)) {
                            unawaited(
                              _actions
                                  .open(item, live, _actionPorts)
                                  .whenComplete(_afterAction),
                            );
                          }
                        }
                      : null,
                  onMarkRead: actionsEnabled
                      ? (item) {
                          if (_canUseCaptured(intent, query)) {
                            unawaited(
                              _actions
                                  .markRead(item, live, _actionPorts)
                                  .whenComplete(_afterAction),
                            );
                          }
                        }
                      : null,
                  pendingReadIds: actionsEnabled
                      ? interaction.pendingReadIds
                      : const <String>{},
                ),
              ),
            ),
          ),
        ),
      );
    } finally {
      _building = false;
    }
  }

  bool _canPoll(NotificationQuery query) {
    if (!mounted || _accessFailure != null) return false;
    _synchronizeNamespace();
    if (query != _currentQuery) return false;
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
        NotificationSnapshotProjection.matchesPage(cache, query, page);
    final countCanRefresh =
        count != null &&
        count.data != null &&
        !count.loading &&
        count.failure == null &&
        NotificationSnapshotProjection.matchesCount(cache, count);
    return pageCanRefresh || countCanRefresh;
  }

  void _poll(NotificationQuery query) {
    if (!_canPoll(query)) return;
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
    final pageEligible =
        page != null &&
        page.data != null &&
        !page.loading &&
        page.failure == null &&
        NotificationSnapshotProjection.matchesPage(cache, query, page);
    final countEligible =
        count != null &&
        count.data != null &&
        !count.loading &&
        count.failure == null &&
        NotificationSnapshotProjection.matchesCount(cache, count);
    final ports = _ports;
    if (pageEligible) {
      // The owner arms the head. Polling may refresh only resources that were
      // eligible at dispatch; an unavailable count is not an implicit retry.
      unawaited(
        _reads.refresh((
          current: ports.current,
          page: ports.page,
          count: ports.count,
          refreshPage: ports.refreshPage,
          refreshCount: countEligible ? ports.refreshCount : () async {},
          invalidateInteractions: ports.invalidateInteractions,
        )),
      );
    } else if (countEligible && _canPoll(query)) {
      // Count-only polling belongs to foundation: do not arm/reset a feed round.
      unawaited(ports.refreshCount());
    }
  }

  void _setFilter(NotificationFilter filter) {
    if (filter == _filter) return;
    setState(() {
      final live = _synchronizeNamespace();
      _reads.setFilter(filter, live);
      _intent = _reads.headIntent(live);
    });
  }

  void _loadMore() {
    final intent = _reads.beginLoadMore(_ports, _currentQuery);
    if (intent != null) setState(() => _intent = intent);
  }

  void _retryLoadMore(NotificationQuery query) {
    final intent = _reads.beginLoadMore(_ports, query, retry: true);
    if (intent == null) return;
    setState(() => _intent = intent);
    unawaited(
      ref.read(notificationPageFoundationProvider(query).notifier).refresh(),
    );
  }

  NotificationQuery get _currentQuery => NotificationQuery(
    filter: _filter,
    limit: _pageSize,
    cursor: _reads.cursor,
  );

  Future<void> _refreshFirstPage() async {
    if (!mounted) return;
    _synchronizeNamespace();
    await _reads.refresh(_ports);
    if (mounted) {
      setState(() {
        _synchronizeNamespace();
      });
    }
  }

  bool _isAccessFailure(AppFailure? failure) =>
      NotificationSnapshotProjection.isAccessFailure(failure);

  void _onCacheInvalidated(String resource) {
    if (!mounted) return;
    _reads.onResourceInvalidated(resource, _ports);
    setState(() {
      _synchronizeNamespace();
    });
  }

  bool _canInteractNow() {
    if (!mounted) return false;
    _synchronizeNamespace();
    return _reads.canInteract(_ports, _currentQuery);
  }

  bool _canUseCaptured(
    NotificationReadIntent? intent,
    NotificationQuery query,
  ) {
    if (!mounted || intent == null) return false;
    final live = _synchronizeNamespace();
    return intent.namespace == live &&
        intent.revision == _reads.revision &&
        intent.cursor == _reads.cursor &&
        query == _currentQuery &&
        _reads.canInteract(_ports, query);
  }

  NotificationActionPorts get _actionPorts => (
    isActive: () => mounted,
    reads: _ports,
    query: () => _currentQuery,
    interaction: () =>
        ref.read(notificationInteractionViewModelProvider.notifier),
    state: () => ref.read(notificationInteractionViewModelProvider),
    navigation: () => widget.onNavigate,
    message: _showMessage,
    context: _showNotificationContext,
  );

  void _afterAction() {
    if (mounted) {
      setState(() {
        _synchronizeNamespace();
      });
    }
  }

  void _showNotificationContext(
    NotificationReadNamespace submitted,
    NotificationItem item,
  ) {
    if (!_canInteractNow() ||
        _synchronizeNamespace() != submitted ||
        item.recipientId != submitted.scope.userId ||
        item.subjectType != NotificationSubjectType.notificationOnly) {
      return;
    }
    final cache = submitted.cache;
    final query = _currentQuery;
    final snapshot = ref
        .read(notificationPageFoundationProvider(query))
        .asData
        ?.value;
    if (snapshot == null ||
        !NotificationSnapshotProjection.matchesPage(cache, query, snapshot) ||
        !_reads.items.any((row) => identical(row, item)) ||
        _isAccessFailure(
          ref.read(unreadCountFoundationProvider).asData?.value.failure,
        )) {
      return;
    }
    // The route must inherit a container above Navigator, not Page-local DI.
    if (!identical(
      ProviderScope.containerOf(context, listen: false),
      ProviderScope.containerOf(Navigator.of(context).context, listen: false),
    )) {
      return;
    }
    if (_synchronizeNamespace() != submitted || !_canInteractNow()) return;
    final handle = NotificationContextHandle(
      namespace: submitted,
      recipientId: item.recipientId,
      query: query,
      title: item.title,
      body: item.body,
    );
    _contextHandles.add(handle);
    _pushContext(context, handle, _contextHandles);
  }

  void _revokeContexts() {
    for (final handle in List.of(_contextHandles)) {
      handle.revoke();
    }
    _contextHandles.clear();
  }

  // Separate lexical scope: the builder captures only its revocable handle.
  static WidgetBuilder _contextBuilder(NotificationContextHandle handle) =>
      (_) => Mh17NotificationContextModal(handle: handle);

  static void _pushContext(
    BuildContext context,
    NotificationContextHandle handle,
    Set<NotificationContextHandle> links,
  ) {
    try {
      unawaited(
        showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: _contextBuilder(handle),
        ).whenComplete(() {
          links.remove(handle);
          handle.release();
        }),
      );
    } catch (_) {
      links.remove(handle);
      handle.release();
      rethrow;
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
