import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../deliveries/data/repositories/operational_providers.dart';
import '../../../deliveries/data/repositories/operational_read_access.dart';
import '../../../deliveries/domain/models/operational_failure.dart';
import '../../domain/models/cod_collection.dart';
import '../../domain/models/cod_collection_page.dart';
import '../../domain/models/cod_collection_query.dart';
import '../../domain/repositories/cod_repository.dart';
import 'cod_providers.dart';

/// The two shipper-facing COD groups. Uncollected obligations are deliberately
/// excluded: they are not cash held by the shipper yet.
enum ShipperCodGroup {
  unreconciled,
  reconciled;

  CodStatus get status => switch (this) {
    ShipperCodGroup.unreconciled => CodStatus.collected,
    ShipperCodGroup.reconciled => CodStatus.received,
  };
}

final class ShipperCodState {
  const ShipperCodState({
    required this.group,
    required this.items,
    required this.counts,
    required this.heldTotalVnd,
    required this.filteredTotal,
    required this.nextCursor,
    required this.asOf,
    required this.isLoading,
    required this.isLoadingMore,
    required this.error,
    required this.loadMoreError,
  });

  factory ShipperCodState.initial({
    ShipperCodGroup group = ShipperCodGroup.unreconciled,
    bool isLoading = true,
    OperationalFailure? error,
  }) => ShipperCodState(
    group: group,
    items: const [],
    counts: null,
    heldTotalVnd: null,
    filteredTotal: null,
    nextCursor: null,
    asOf: null,
    isLoading: isLoading,
    isLoadingMore: false,
    error: error,
    loadMoreError: null,
  );

  final ShipperCodGroup group;
  final List<CodCollection> items;
  final CodCollectionCounts? counts;

  /// Server-computed collected-but-not-received total across the whole scope.
  final int? heldTotalVnd;
  final int? filteredTotal;
  final String? nextCursor;
  final DateTime? asOf;
  final bool isLoading;
  final bool isLoadingMore;
  final OperationalFailure? error;
  final OperationalFailure? loadMoreError;

  bool get hasMore => nextCursor != null;

  static const _unset = Object();

  ShipperCodState copyWith({
    ShipperCodGroup? group,
    Object? items = _unset,
    Object? counts = _unset,
    Object? heldTotalVnd = _unset,
    Object? filteredTotal = _unset,
    Object? nextCursor = _unset,
    Object? asOf = _unset,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error = _unset,
    Object? loadMoreError = _unset,
  }) => ShipperCodState(
    group: group ?? this.group,
    items: identical(items, _unset)
        ? this.items
        : List.unmodifiable(items! as List<CodCollection>),
    counts: identical(counts, _unset)
        ? this.counts
        : counts as CodCollectionCounts?,
    heldTotalVnd: identical(heldTotalVnd, _unset)
        ? this.heldTotalVnd
        : heldTotalVnd as int?,
    filteredTotal: identical(filteredTotal, _unset)
        ? this.filteredTotal
        : filteredTotal as int?,
    nextCursor: identical(nextCursor, _unset)
        ? this.nextCursor
        : nextCursor as String?,
    asOf: identical(asOf, _unset) ? this.asOf : asOf as DateTime?,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    error: identical(error, _unset) ? this.error : error as OperationalFailure?,
    loadMoreError: identical(loadMoreError, _unset)
        ? this.loadMoreError
        : loadMoreError as OperationalFailure?,
  );
}

/// Riverpod state for the shipper view of MH12. The nullable family argument
/// is the optional order filter from `/cod?orderId=...`.
final shipperCodViewModelProvider = NotifierProvider.autoDispose
    .family<ShipperCodViewModel, ShipperCodState, String?>(
      ShipperCodViewModel.new,
    );

class ShipperCodViewModel extends Notifier<ShipperCodState> {
  ShipperCodViewModel(this.orderId);

  final String? orderId;
  CodRepository get _repository => ref.read(codRepositoryProvider);

  OperationalSession? _activeSession;
  var _sessionEventVersion = 0;
  var _requestGeneration = 0;
  var _consistencyResetUsed = false;
  var _disposed = false;
  final _requestedCursors = <String>{};

  @override
  ShipperCodState build() {
    // Riverpod may rebuild an auto-dispose notifier in place after an
    // invalidation. Reset lifecycle state before installing the new listener;
    // generation changes keep requests from the previous build stale.
    _disposed = false;
    _activeSession = null;
    _sessionEventVersion++;
    _requestGeneration++;
    _consistencyResetUsed = false;
    _requestedCursors.clear();
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
    return ShipperCodState.initial();
  }

  Future<void> setGroup(ShipperCodGroup group) async {
    if (!_isMounted || group == state.group) return;
    state = state.copyWith(group: group);
    await refresh();
  }

  /// Refreshes from the first page. This is also the seam used after a
  /// successful delivery or manager reconciliation; it never fabricates data.
  Future<void> refresh() => _refresh(resetConsistencyBudget: true);

  Future<void> _refresh({required bool resetConsistencyBudget}) async {
    _requestGeneration++;
    final request = _requestGeneration;
    final session = _activeSession;
    _requestedCursors.clear();
    if (resetConsistencyBudget) _consistencyResetUsed = false;
    if (!_isMounted) return;

    if (!_isSessionUsable(session)) {
      state = ShipperCodState.initial(
        group: state.group,
        isLoading: false,
        error:
            session?.failure ??
            const OperationalFailure(OperationalFailureCode.sessionExpired),
      );
      return;
    }

    state = ShipperCodState.initial(group: state.group);
    await _fetchFirstPage(request, session!);
  }

  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    final session = _activeSession;
    if (cursor == null || state.isLoading || state.isLoadingMore) return;
    if (!_isSessionUsable(session)) return;
    if (!_requestedCursors.add(cursor)) {
      await _resetForConsistency(session!);
      return;
    }

    final request = _requestGeneration;
    final query = _query(session!, cursor: cursor);
    state = state.copyWith(isLoadingMore: true, loadMoreError: null);
    try {
      final page = await _repository.queryCollections(query);
      if (!_isCurrent(request, session)) return;
      _validatePage(page, query, firstPage: false, session: session);
      if (page.items.isNotEmpty &&
          state.items.isNotEmpty &&
          !_isBefore(page.items.first, state.items.last)) {
        throw const OperationalFailure(OperationalFailureCode.invalidData);
      }
      if (_hasConsistencyMismatch(page, cursor)) {
        await _resetForConsistency(session);
        return;
      }

      final ids = state.items.map((item) => item.orderId.toLowerCase()).toSet();
      for (final item in page.items) {
        if (!ids.add(item.orderId.toLowerCase())) {
          await _resetForConsistency(session);
          return;
        }
      }
      state = state.copyWith(
        items: <CodCollection>[...state.items, ...page.items],
        nextCursor: page.nextCursor,
        isLoadingMore: false,
        loadMoreError: null,
      );
    } on Object catch (error) {
      if (!_isCurrent(request, session)) return;
      _requestedCursors.remove(cursor);
      final failure = mapOperationalFailure(error);
      if (_isFatal(failure)) {
        _setFatal(failure);
      } else {
        state = state.copyWith(isLoadingMore: false, loadMoreError: failure);
      }
    }
  }

  Future<void> _fetchFirstPage(int request, OperationalSession session) async {
    try {
      final page = await _repository.queryCollections(_query(session));
      if (!_isCurrent(request, session)) return;
      _validatePage(page, _query(session), firstPage: true, session: session);
      state = state.copyWith(
        items: page.items,
        counts: page.counts,
        heldTotalVnd: page.outstandingVnd,
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
      if (_isFatal(failure)) {
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

  CodCollectionQuery _query(OperationalSession session, {String? cursor}) =>
      CodCollectionQuery(
        shipperId: session.userId,
        orderId: orderId,
        statuses: [state.group.status],
        limit: CodCollectionQuery.maxPageSize,
        cursor: cursor,
      );

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
      state = ShipperCodState.initial(group: state.group);
      return;
    }
    if (next.hasError) {
      _activeSession = null;
      _requestGeneration++;
      _requestedCursors.clear();
      state = ShipperCodState.initial(
        group: state.group,
        isLoading: false,
        error: mapOperationalFailure(next.error!),
      );
      return;
    }
    final session = next.requireValue;
    if (identical(session, _activeSession)) return;
    _activeSession = session;
    unawaited(refresh());
  }

  void _validatePage(
    CodCollectionPage page,
    CodCollectionQuery query, {
    required bool firstPage,
    required OperationalSession session,
  }) {
    final counts = page.counts;
    final countsTotal = counts.uncollected + counts.collected + counts.received;
    final selectedCount = query.statuses.isEmpty
        ? counts.all
        : query.statuses.fold<int>(
            0,
            (total, status) => total + counts[status],
          );
    if (page.filteredTotal < 0 ||
        page.outstandingVnd < 0 ||
        counts.all < 0 ||
        counts.uncollected < 0 ||
        counts.collected < 0 ||
        counts.received < 0 ||
        countsTotal != counts.all ||
        page.filteredTotal != selectedCount ||
        page.items.length > query.limit ||
        page.filteredTotal < page.items.length ||
        counts.all < page.filteredTotal) {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }
    final ids = <String>{};
    CodCollection? previous;
    for (final item in page.items) {
      if (!ids.add(item.orderId.toLowerCase()) ||
          item.shipperId?.toLowerCase() != session.userId!.toLowerCase() ||
          item.status != state.group.status) {
        throw const OperationalFailure(OperationalFailureCode.permissionDenied);
      }
      if ((query.orderId != null &&
              item.orderId.toLowerCase() != query.orderId!.toLowerCase()) ||
          item.outstandingAmountVnd < 0 ||
          (previous != null && !_isBefore(item, previous))) {
        throw const OperationalFailure(OperationalFailureCode.invalidData);
      }
      previous = item;
    }
    if (firstPage && query.cursor == null) {
      final expected = page.filteredTotal < query.limit
          ? page.filteredTotal
          : query.limit;
      if (page.items.length != expected ||
          (page.nextCursor != null) !=
              (page.filteredTotal > page.items.length)) {
        throw const OperationalFailure(OperationalFailureCode.invalidData);
      }
    } else if (!firstPage &&
        page.nextCursor != null &&
        page.items.length != query.limit) {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }
  }

  bool _hasConsistencyMismatch(CodCollectionPage page, String cursor) {
    final filteredTotal = state.filteredTotal;
    final cumulativeCount = state.items.length + page.items.length;
    final cumulativeMismatch =
        filteredTotal == null ||
        cumulativeCount > filteredTotal ||
        (page.nextCursor == null && cumulativeCount != filteredTotal) ||
        (page.nextCursor != null && cumulativeCount >= filteredTotal);
    return page.nextCursor == cursor ||
        cumulativeMismatch ||
        (page.filteredTotal != state.filteredTotal) ||
        !_sameCounts(page.counts, state.counts) ||
        (page.outstandingVnd != state.heldTotalVnd) ||
        (page.nextCursor != null &&
            _requestedCursors.contains(page.nextCursor));
  }

  Future<void> _resetForConsistency(OperationalSession session) async {
    if (!_isCurrent(_requestGeneration, session)) return;
    if (_consistencyResetUsed) {
      _setFatal(const OperationalFailure(OperationalFailureCode.invalidData));
      return;
    }
    _consistencyResetUsed = true;
    await _refresh(resetConsistencyBudget: false);
  }

  void _setFatal(OperationalFailure failure) {
    if (!_isMounted) return;
    _requestGeneration++;
    _requestedCursors.clear();
    state = ShipperCodState.initial(
      group: state.group,
      isLoading: false,
      error: failure,
    );
  }

  bool _isSessionUsable(OperationalSession? session) =>
      session != null && session.userId != null && session.failure == null;

  bool _isCurrent(int request, OperationalSession session) =>
      _isMounted &&
      request == _requestGeneration &&
      identical(session, _activeSession) &&
      _isSessionUsable(session);

  bool _isFatal(OperationalFailure failure) => switch (failure.code) {
    OperationalFailureCode.sessionExpired ||
    OperationalFailureCode.permissionDenied ||
    OperationalFailureCode.staleAssignment => true,
    _ => false,
  };

  bool _sameCounts(CodCollectionCounts? left, CodCollectionCounts? right) {
    if (left == null || right == null) return left == right;
    return left.all == right.all &&
        left.uncollected == right.uncollected &&
        left.collected == right.collected &&
        left.received == right.received;
  }

  static bool _isBefore(CodCollection candidate, CodCollection cursor) {
    final timestamp = candidate.createdAt.compareTo(cursor.createdAt);
    if (timestamp != 0) return timestamp < 0;
    return candidate.orderId.toLowerCase().compareTo(
          cursor.orderId.toLowerCase(),
        ) <
        0;
  }

  bool get _isMounted => !_disposed && ref.mounted;
}
