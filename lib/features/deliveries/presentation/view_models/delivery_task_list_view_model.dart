import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/operational_providers.dart';
import '../../data/repositories/operational_read_access.dart';
import '../../domain/models/delivery_task.dart';
import '../../domain/models/delivery_task_query.dart';
import '../../domain/models/operational_failure.dart';
import '../../domain/repositories/delivery_repository.dart';
import 'delivery_providers.dart';

/// The state rendered by MH10.
///
/// [query] always contains the canonical filters for the list and has a null
/// cursor.  A cursor is only used for the single request that loads the next
/// page; keeping it out of the public state makes a filter change an explicit
/// first-page request.
final class DeliveryTaskListState {
  DeliveryTaskListState({
    required this.query,
    required List<DeliveryTaskSnapshot> items,
    required this.counts,
    required this.filteredTotal,
    required this.nextCursor,
    required this.asOf,
    required this.isLoading,
    required this.isLoadingMore,
    required this.error,
    required this.loadMoreError,
  }) : items = List.unmodifiable(items);

  factory DeliveryTaskListState.initial({
    DeliveryTaskQuery? query,
    bool isLoading = true,
    OperationalFailure? error,
  }) => DeliveryTaskListState(
    query: query ?? DeliveryTaskQuery(),
    items: const [],
    counts: null,
    filteredTotal: null,
    nextCursor: null,
    asOf: null,
    isLoading: isLoading,
    isLoadingMore: false,
    error: error,
    loadMoreError: null,
  );

  final DeliveryTaskQuery query;
  final List<DeliveryTaskSnapshot> items;
  final DeliveryTaskCounts? counts;
  final int? filteredTotal;
  final String? nextCursor;
  final DateTime? asOf;
  final bool isLoading;
  final bool isLoadingMore;
  final OperationalFailure? error;
  final OperationalFailure? loadMoreError;

  bool get hasMore => nextCursor != null;

  static const _unset = Object();

  DeliveryTaskListState copyWith({
    DeliveryTaskQuery? query,
    Object? items = _unset,
    Object? counts = _unset,
    Object? filteredTotal = _unset,
    Object? nextCursor = _unset,
    Object? asOf = _unset,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error = _unset,
    Object? loadMoreError = _unset,
  }) {
    return DeliveryTaskListState(
      query: query ?? this.query,
      items: identical(items, _unset)
          ? this.items
          : List<DeliveryTaskSnapshot>.from(items! as List),
      counts: identical(counts, _unset)
          ? this.counts
          : counts as DeliveryTaskCounts?,
      filteredTotal: identical(filteredTotal, _unset)
          ? this.filteredTotal
          : filteredTotal as int?,
      nextCursor: identical(nextCursor, _unset)
          ? this.nextCursor
          : nextCursor as String?,
      asOf: identical(asOf, _unset) ? this.asOf : asOf as DateTime?,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: identical(error, _unset)
          ? this.error
          : error as OperationalFailure?,
      loadMoreError: identical(loadMoreError, _unset)
          ? this.loadMoreError
          : loadMoreError as OperationalFailure?,
    );
  }
}

/// The long-lived provider for MH10.  Keeping this provider alive preserves
/// filters while navigating from the list to MH11 and back.  Its session
/// listener still clears all private rows whenever the operational epoch
/// changes.
final deliveryTaskListViewModelProvider =
    NotifierProvider<DeliveryTaskListViewModel, DeliveryTaskListState>(
      DeliveryTaskListViewModel.new,
    );

class DeliveryTaskListViewModel extends Notifier<DeliveryTaskListState> {
  static final _initialQuery = DeliveryTaskQuery();

  DeliveryRepository get _repository => ref.read(deliveryRepositoryProvider);

  OperationalSession? _activeSession;
  var _sessionEventVersion = 0;
  var _requestGeneration = 0;
  var _consistencyResetUsed = false;
  var _disposed = false;
  final _requestedCursors = <String>{};

  @override
  DeliveryTaskListState build() {
    ref.listen<AsyncValue<OperationalSession>>(
      operationalSessionProvider,
      (_, next) => _scheduleSession(next),
      fireImmediately: true,
    );
    ref.onDispose(() {
      _disposed = true;
      _requestGeneration++;
      _activeSession = null;
      _requestedCursors.clear();
    });
    return DeliveryTaskListState.initial(query: _initialQuery);
  }

  /// Search is submit-driven.  The page owns no local filtering; every call
  /// becomes a server query with the canonical P02.1 parameters.
  Future<void> setSearch(String value) => _setFilters(query: value);

  Future<void> setKind(DeliveryTaskKind? kind) => _setFilters(kind: kind);

  Future<void> setStateGroup(DeliveryTaskStateGroup? stateGroup) =>
      _setFilters(stateGroup: stateGroup);

  /// Clears all MH10 filters and loads one fresh first page atomically.
  Future<void> resetFilters() => _startFirstPage(_initialQuery);

  Future<void> refresh() => _startFirstPage(state.query);

  Future<void> _setFilters({
    Object? kind = _unset,
    Object? stateGroup = _unset,
    Object? query = _unset,
  }) async {
    try {
      final current = state.query;
      final next = DeliveryTaskQuery(
        kind: identical(kind, _unset)
            ? current.kind
            : kind as DeliveryTaskKind?,
        stateGroup: identical(stateGroup, _unset)
            ? current.stateGroup
            : stateGroup as DeliveryTaskStateGroup?,
        query: identical(query, _unset) ? current.query : query as String?,
        limit: current.limit,
      );
      if (next == current) return;
      await _startFirstPage(next);
    } on Object catch (error) {
      if (!_isMounted) return;
      _requestGeneration++;
      _requestedCursors.clear();
      state = state.copyWith(
        items: const <DeliveryTaskSnapshot>[],
        counts: null,
        filteredTotal: null,
        nextCursor: null,
        asOf: null,
        isLoading: false,
        isLoadingMore: false,
        error: mapOperationalFailure(error),
        loadMoreError: null,
      );
    }
  }

  Future<void> _startFirstPage(
    DeliveryTaskQuery filters, {
    bool resetConsistencyBudget = true,
  }) async {
    final query = DeliveryTaskQuery(
      kind: filters.kind,
      stateGroup: filters.stateGroup,
      query: filters.query,
      limit: filters.limit,
    );
    _requestGeneration++;
    final request = _requestGeneration;
    final session = _activeSession;
    _requestedCursors.clear();
    if (resetConsistencyBudget) _consistencyResetUsed = false;

    if (!_isSessionUsable(session)) {
      if (!_isMounted) return;
      final failure =
          session?.failure ??
          const OperationalFailure(OperationalFailureCode.sessionExpired);
      state = DeliveryTaskListState.initial(
        query: query,
        isLoading: false,
        error: failure,
      );
      return;
    }

    state = DeliveryTaskListState.initial(query: query, isLoading: true);
    await _fetchFirstPage(query, request: request, session: session!);
  }

  Future<void> _fetchFirstPage(
    DeliveryTaskQuery query, {
    required int request,
    required OperationalSession session,
  }) async {
    try {
      final page = await _repository.queryTasks(query);
      if (!_isCurrent(request, session)) return;
      _validatePage(page, query, firstPage: true);
      _requestedCursors.clear();
      state = state.copyWith(
        items: page.items,
        counts: page.counts,
        filteredTotal: page.filteredTotal,
        nextCursor: page.nextCursor,
        asOf: page.asOf,
        isLoading: false,
        isLoadingMore: false,
        error: null,
        loadMoreError: null,
      );
    } on Object catch (error) {
      if (!_isCurrent(request, session)) return;
      final failure = mapOperationalFailure(error);
      if (failure.code == OperationalFailureCode.sessionExpired ||
          failure.code == OperationalFailureCode.permissionDenied ||
          failure.code == OperationalFailureCode.staleAssignment) {
        _setFatal(failure);
      } else {
        state = state.copyWith(
          isLoading: false,
          isLoadingMore: false,
          error: failure,
          loadMoreError: null,
          nextCursor: null,
        );
      }
    }
  }

  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    final session = _activeSession;
    if (cursor == null || state.isLoading || state.isLoadingMore) return;
    if (!_isSessionUsable(session)) return;
    if (!_requestedCursors.add(cursor)) {
      await _handleConsistencyMismatch(session!);
      return;
    }

    final request = _requestGeneration;
    final query = DeliveryTaskQuery(
      kind: state.query.kind,
      stateGroup: state.query.stateGroup,
      query: state.query.query,
      limit: state.query.limit,
      cursor: cursor,
    );
    state = state.copyWith(isLoadingMore: true, loadMoreError: null);
    try {
      final page = await _repository.queryTasks(query);
      if (!_isCurrent(request, session!)) return;
      _validatePage(page, query, firstPage: false);
      if (_hasConsistencyMismatch(page, cursor)) {
        await _handleConsistencyMismatch(session);
        return;
      }
      final ids = state.items.map((item) => item.taskId.toLowerCase()).toSet();
      final pageIds = <String>{};
      for (final item in page.items) {
        final id = item.taskId.toLowerCase();
        if (!pageIds.add(id) || !ids.add(id)) {
          await _handleConsistencyMismatch(session);
          return;
        }
      }
      state = state.copyWith(
        items: <DeliveryTaskSnapshot>[...state.items, ...page.items],
        nextCursor: page.nextCursor,
        isLoadingMore: false,
        loadMoreError: null,
      );
    } on Object catch (error) {
      if (!_isCurrent(request, session!)) return;
      _requestedCursors.remove(cursor);
      final failure = mapOperationalFailure(error);
      if (failure.code == OperationalFailureCode.sessionExpired ||
          failure.code == OperationalFailureCode.permissionDenied ||
          failure.code == OperationalFailureCode.staleAssignment) {
        _setFatal(failure);
      } else {
        state = state.copyWith(isLoadingMore: false, loadMoreError: failure);
      }
    }
  }

  Future<void> _handleConsistencyMismatch(OperationalSession session) async {
    if (!_isCurrent(_requestGeneration, session)) return;
    if (_consistencyResetUsed) {
      _setFatal(const OperationalFailure(OperationalFailureCode.invalidData));
      return;
    }
    _consistencyResetUsed = true;
    await _startFirstPage(state.query, resetConsistencyBudget: false);
  }

  void _scheduleSession(AsyncValue<OperationalSession> next) {
    final version = ++_sessionEventVersion;
    scheduleMicrotask(() {
      if (!_isMounted || version != _sessionEventVersion) return;
      _handleSession(next);
    });
  }

  void _handleSession(AsyncValue<OperationalSession> next) {
    if (!_isMounted) return;
    if (next.isLoading) {
      _activeSession = null;
      _requestGeneration++;
      _requestedCursors.clear();
      state = DeliveryTaskListState.initial(query: _initialQuery);
      return;
    }
    if (next.hasError) {
      _activeSession = null;
      _requestGeneration++;
      _requestedCursors.clear();
      state = DeliveryTaskListState.initial(
        query: _initialQuery,
        isLoading: false,
        error: mapOperationalFailure(next.error!),
      );
      return;
    }
    final session = next.requireValue;
    if (identical(session, _activeSession)) return;
    _activeSession = session;
    unawaited(_startFirstPage(_initialQuery));
  }

  bool _isSessionUsable(OperationalSession? session) =>
      session != null && session.userId != null && session.failure == null;

  bool get _isMounted => !_disposed && ref.mounted;

  bool _isCurrent(int request, OperationalSession session) {
    return _isMounted &&
        request == _requestGeneration &&
        identical(session, _activeSession) &&
        _isSessionUsable(session);
  }

  void _setFatal(OperationalFailure failure) {
    if (!_isMounted) return;
    _requestGeneration++;
    _requestedCursors.clear();
    state = state.copyWith(
      query: failure.code == OperationalFailureCode.sessionExpired
          ? _initialQuery
          : state.query,
      items: const <DeliveryTaskSnapshot>[],
      counts: null,
      filteredTotal: null,
      nextCursor: null,
      asOf: null,
      isLoading: false,
      isLoadingMore: false,
      error: failure,
      loadMoreError: null,
    );
  }

  bool _hasConsistencyMismatch(DeliveryTaskPage page, String cursor) {
    if (page.nextCursor == cursor ||
        (page.nextCursor != null &&
            _requestedCursors.contains(page.nextCursor))) {
      return true;
    }
    final combinedCount = state.items.length + page.items.length;
    if (page.nextCursor == null && combinedCount != page.filteredTotal) {
      return true;
    }
    if (page.nextCursor != null && combinedCount >= page.filteredTotal) {
      return true;
    }
    return page.filteredTotal != state.filteredTotal ||
        page.counts != state.counts;
  }

  void _validatePage(
    DeliveryTaskPage page,
    DeliveryTaskQuery query, {
    required bool firstPage,
  }) {
    if (page.items.length > query.limit ||
        page.filteredTotal < page.items.length ||
        page.counts.total < page.filteredTotal) {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }
    final ids = <String>{};
    for (final item in page.items) {
      if (!ids.add(item.taskId.toLowerCase())) {
        throw const OperationalFailure(OperationalFailureCode.invalidData);
      }
    }
    if (firstPage && query.cursor == null) {
      final expectedLength = page.filteredTotal < query.limit
          ? page.filteredTotal
          : query.limit;
      if (page.items.length != expectedLength ||
          (page.nextCursor != null) !=
              (page.filteredTotal > page.items.length)) {
        throw const OperationalFailure(OperationalFailureCode.invalidData);
      }
    }
  }
}

// Kept local to this ViewModel so it cannot be confused with a task's business
// state or accidentally used as a server-side filter.
const _unset = Object();
