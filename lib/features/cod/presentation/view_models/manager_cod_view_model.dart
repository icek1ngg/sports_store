import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../deliveries/data/repositories/operational_providers.dart';
import '../../../deliveries/data/repositories/operational_read_access.dart';
import '../../../deliveries/domain/models/operational_failure.dart';
import '../../domain/models/cod_collection.dart';
import '../../domain/models/cod_collection_page.dart';
import '../../domain/models/cod_collection_query.dart';
import '../../domain/models/cod_receipt.dart';
import '../../domain/repositories/cod_repository.dart';
import '../../domain/repositories/cod_receipt_repository.dart';
import '../view_models/cod_providers.dart';
import 'cod_read_refresh.dart';

/// The two manager-facing groups in MH12.
///
/// The server status filter is deliberately explicit.  In particular,
/// `unreconciled` means money collected by a shipper, not every status that
/// is not yet received.
enum ManagerCodGroup {
  unreconciled,
  reconciled;

  CodStatus get status => switch (this) {
    ManagerCodGroup.unreconciled => CodStatus.collected,
    ManagerCodGroup.reconciled => CodStatus.received,
  };
}

/// State for the manager branch of MH12.
///
/// All list totals are server totals for the current filter scope.  The
/// ViewModel never inserts an optimistic row after a receipt write: a receipt
/// is exposed only after the write ACK and a matching authoritative read.
final class ManagerCodState {
  const ManagerCodState({
    required this.shipperId,
    required this.orderId,
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
    required this.isSubmitting,
    required this.actionError,
    required this.pendingCommand,
    required this.requiresReadRetry,
    required this.lastReceipt,
  });

  factory ManagerCodState.initial({
    String? shipperId,
    String? orderId,
    ManagerCodGroup group = ManagerCodGroup.unreconciled,
    bool isLoading = true,
    OperationalFailure? error,
  }) => ManagerCodState(
    shipperId: shipperId,
    orderId: orderId,
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
    isSubmitting: false,
    actionError: null,
    pendingCommand: null,
    requiresReadRetry: false,
    lastReceipt: null,
  );

  final String? shipperId;
  final String? orderId;
  final ManagerCodGroup group;
  final List<CodCollection> items;
  final CodCollectionCounts? counts;

  /// Server-computed collected-but-not-received amount for the whole scope.
  final int? heldTotalVnd;
  final int? filteredTotal;
  final String? nextCursor;
  final DateTime? asOf;
  final bool isLoading;
  final bool isLoadingMore;
  final OperationalFailure? error;
  final OperationalFailure? loadMoreError;

  /// True while a receipt RPC or its authoritative read is in flight.
  final bool isSubmitting;
  final OperationalFailure? actionError;

  /// The frozen command used by the current/last uncertain write.  Keeping
  /// it in state makes timeout retries reuse the same request ID and amount.
  final CodReceiptCommand? pendingCommand;
  final bool requiresReadRetry;
  final CodReceipt? lastReceipt;

  bool get hasMore => nextCursor != null;

  static const _unset = Object();

  ManagerCodState copyWith({
    Object? shipperId = _unset,
    Object? orderId = _unset,
    ManagerCodGroup? group,
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
    bool? isSubmitting,
    Object? actionError = _unset,
    Object? pendingCommand = _unset,
    bool? requiresReadRetry,
    Object? lastReceipt = _unset,
  }) => ManagerCodState(
    shipperId: identical(shipperId, _unset)
        ? this.shipperId
        : shipperId as String?,
    orderId: identical(orderId, _unset) ? this.orderId : orderId as String?,
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
    isSubmitting: isSubmitting ?? this.isSubmitting,
    actionError: identical(actionError, _unset)
        ? this.actionError
        : actionError as OperationalFailure?,
    pendingCommand: identical(pendingCommand, _unset)
        ? this.pendingCommand
        : pendingCommand as CodReceiptCommand?,
    requiresReadRetry: requiresReadRetry ?? this.requiresReadRetry,
    lastReceipt: identical(lastReceipt, _unset)
        ? this.lastReceipt
        : lastReceipt as CodReceipt?,
  );
}

/// Manager state is normally auto-disposed with the route. A pending receipt
/// command opts into Riverpod keep-alive until its write/read retry protocol
/// is finished, so navigating away cannot create a second request ID.
final managerCodViewModelProvider = NotifierProvider.autoDispose
    .family<ManagerCodViewModel, ManagerCodState, String?>(
      ManagerCodViewModel.new,
    );

class ManagerCodViewModel extends Notifier<ManagerCodState> {
  ManagerCodViewModel(this.initialOrderId);

  final String? initialOrderId;

  CodRepository get _repository => ref.read(codRepositoryProvider);

  OperationalSession? _activeSession;
  String? _activeRole;
  var _sessionEventVersion = 0;
  var _roleEventVersion = 0;
  var _requestGeneration = 0;
  var _sessionRevision = 0;
  var _readyRevision = -1;
  var _consistencyResetUsed = false;
  var _disposed = false;
  var _isVisible = true;
  void Function()? _closePendingKeepAlive;
  void Function()? _closePendingObservers;
  var _deferredRead = false;
  final _requestedCursors = <String>{};
  CodReceipt? _acknowledgedReceipt;

  @override
  ManagerCodState build() {
    _disposed = false;
    _activeSession = null;
    _activeRole = null;
    _sessionEventVersion++;
    _roleEventVersion++;
    _requestGeneration++;
    _sessionRevision++;
    _readyRevision = -1;
    _consistencyResetUsed = false;
    _requestedCursors.clear();
    _acknowledgedReceipt = null;
    _isVisible = true;
    _closePendingKeepAlive = null;
    _closePendingObservers = null;
    _deferredRead = false;

    ref.listen<AsyncValue<OperationalSession>>(
      operationalSessionProvider,
      (_, next) => _scheduleSession(next),
      fireImmediately: true,
    );
    ref.listen<AsyncValue<String>>(
      codScreenRoleProvider,
      (_, next) => _scheduleRole(next),
      fireImmediately: true,
    );
    ref.onCancel(() {
      _isVisible = false;
      _requestGeneration++;
      // A normal list provider is allowed to auto-dispose. A pending
      // money-moving command is retained, but its read retry waits until the
      // screen is visible again.
      scheduleMicrotask(() {
        if (_isMounted && !_isVisible) _releasePendingOperationIfIdle();
      });
    });
    ref.onResume(() {
      _isVisible = true;
      scheduleMicrotask(() {
        if (_isMounted && _isVisible) _resumeVisibleWork();
      });
    });
    ref.onDispose(() {
      _disposed = true;
      _closePendingObservers?.call();
      _closePendingObservers = null;
      _requestGeneration++;
      _sessionRevision++;
      _activeSession = null;
      _activeRole = null;
      _requestedCursors.clear();
      _acknowledgedReceipt = null;
      _deferredRead = false;
    });
    return ManagerCodState.initial(orderId: initialOrderId);
  }

  /// The auth/role epoch captured by an action confirmation dialog.
  int get sessionRevisionForConfirmation => _sessionRevision;

  /// New submissions are blocked while the role/session is unknown, denied,
  /// or a previous command still needs write/read retry.
  bool get actionBlocked =>
      !_isMounted ||
      _activeRole != 'manager' ||
      !_isSessionUsable(_activeSession) ||
      state.isSubmitting ||
      state.pendingCommand != null;

  bool get isActionBlocked => actionBlocked;

  Future<void> setFilters({String? shipperId, String? orderId}) async {
    if (!_canChangeListScope) return;
    try {
      // Use the same constructor as the repository to validate exact UUID
      // filters before changing the active state.
      CodCollectionQuery(
        shipperId: shipperId,
        orderId: orderId,
        statuses: [state.group.status],
        limit: CodCollectionQuery.maxPageSize,
      );
    } on Object catch (error) {
      _setActionError(mapOperationalFailure(error));
      return;
    }
    state = state.copyWith(
      shipperId: shipperId?.trim(),
      orderId: orderId?.trim(),
    );
    await refresh();
  }

  Future<void> setGroup(ManagerCodGroup group) async {
    if (!_canChangeListScope || group == state.group) return;
    state = state.copyWith(group: group, lastReceipt: null, actionError: null);
    await refresh();
  }

  Future<void> refresh() => _refresh(resetConsistencyBudget: true);

  Future<void> _refresh({required bool resetConsistencyBudget}) async {
    _requestGeneration++;
    final request = _requestGeneration;
    final session = _activeSession;
    final revision = _sessionRevision;
    _requestedCursors.clear();
    if (resetConsistencyBudget) _consistencyResetUsed = false;
    if (!_isMounted) return;
    if (!_isVisible) return;

    final roleFailure = _roleFailure;
    if (roleFailure != null || !_isSessionUsable(session)) {
      state = ManagerCodState.initial(
        shipperId: state.shipperId,
        orderId: state.orderId,
        group: state.group,
        isLoading: false,
        error:
            roleFailure ??
            session?.failure ??
            const OperationalFailure(OperationalFailureCode.sessionExpired),
      );
      return;
    }
    if (_activeRole != 'manager') {
      state = ManagerCodState.initial(
        shipperId: state.shipperId,
        orderId: state.orderId,
        group: state.group,
        isLoading: false,
        error: const OperationalFailure(
          OperationalFailureCode.permissionDenied,
        ),
      );
      return;
    }

    state = ManagerCodState.initial(
      shipperId: state.shipperId,
      orderId: state.orderId,
      group: state.group,
    );
    await _fetchFirstPage(request, revision, session!);
  }

  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    final session = _activeSession;
    final revision = _sessionRevision;
    if (cursor == null ||
        state.isLoading ||
        state.isLoadingMore ||
        !_isVisible ||
        !_isSessionUsable(session) ||
        _activeRole != 'manager') {
      return;
    }
    if (!_requestedCursors.add(cursor)) {
      await _resetForConsistency(session!, revision);
      return;
    }

    final request = _requestGeneration;
    final query = _query(cursor: cursor);
    state = state.copyWith(isLoadingMore: true, loadMoreError: null);
    try {
      final page = await _repository.queryCollections(query);
      if (!_isCurrent(request, session, revision)) return;
      _validatePage(page, query, firstPage: false);
      if (page.items.isNotEmpty &&
          state.items.isNotEmpty &&
          !_isBefore(page.items.first, state.items.last)) {
        throw const OperationalFailure(OperationalFailureCode.invalidData);
      }
      if (_hasConsistencyMismatch(page, cursor)) {
        await _resetForConsistency(session!, revision);
        return;
      }

      final ids = state.items.map((item) => item.orderId.toLowerCase()).toSet();
      for (final item in page.items) {
        if (!ids.add(item.orderId.toLowerCase())) {
          await _resetForConsistency(session!, revision);
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
      if (!_isCurrent(request, session, revision)) return;
      _requestedCursors.remove(cursor);
      final failure = mapOperationalFailure(error);
      if (_isFatal(failure)) {
        _setFatal(failure);
      } else {
        state = state.copyWith(isLoadingMore: false, loadMoreError: failure);
      }
    }
  }

  /// Starts a manager receipt only after the dialog has confirmed the full,
  /// server-rendered amount.  Opening MH12 or selecting a row never calls this
  /// method implicitly.
  Future<void> confirmFullReceipt({
    required CodCollection collection,
    required bool receivedFullAmount,
    required int displayedAmountVnd,
    required int sessionRevision,
  }) async {
    if (actionBlocked) {
      if (state.isSubmitting || state.pendingCommand != null) return;
      _setActionError(
        _roleFailure ??
            const OperationalFailure(OperationalFailureCode.permissionDenied),
      );
      return;
    }
    if (!receivedFullAmount ||
        displayedAmountVnd <= 0 ||
        sessionRevision != _sessionRevision ||
        collection.status != CodStatus.collected ||
        collection.shipperId == null ||
        collection.collectedBy == null ||
        collection.collectedAt == null ||
        collection.receivedAmountVnd != 0 ||
        collection.expectedAmountVnd != collection.collectedAmountVnd ||
        displayedAmountVnd != collection.expectedAmountVnd) {
      _setActionError(
        const CodReceiptFailure(CodReceiptFailureCode.amountMismatch),
      );
      return;
    }
    final current = _findCurrentRow(collection.orderId);
    if (current == null || current != collection) {
      _setActionError(
        const OperationalFailure(OperationalFailureCode.staleAssignment),
      );
      return;
    }

    final session = _activeSession;
    if (!_isSessionUsable(session) || _activeRole != 'manager') {
      _setActionError(
        const OperationalFailure(OperationalFailureCode.permissionDenied),
      );
      return;
    }

    late final CodReceiptCommand command;
    try {
      final requestId = ref.read(codReceiptRequestIdProvider)();
      command = CodReceiptCommand(
        orderId: collection.orderId,
        receivedAmountVnd: collection.expectedAmountVnd,
        requestId: requestId,
      )..validate();
    } on Object catch (error) {
      _setActionError(mapOperationalFailure(error));
      return;
    }
    state = state.copyWith(
      isSubmitting: true,
      actionError: null,
      pendingCommand: command,
      requiresReadRetry: false,
      lastReceipt: null,
    );
    _retainPendingOperation();
    await _submitCommand(command, session!, sessionRevision);
  }

  /// Retries an uncertain write with the frozen request ID, or retries only
  /// the authoritative read after a confirmed RPC ACK.  It never generates a
  /// second request ID for the same user action.
  Future<void> retryReceipt() async {
    final command = state.pendingCommand;
    final session = _activeSession;
    final revision = _sessionRevision;
    if (command == null || state.isSubmitting || !_isVisible) return;
    if (!_isActionContextValid(session, revision)) {
      _clearForAuth(
        _roleFailure ??
            session?.failure ??
            const OperationalFailure(OperationalFailureCode.sessionExpired),
      );
      return;
    }
    if (state.requiresReadRetry) {
      final receipt = _acknowledgedReceipt;
      if (receipt == null) {
        _setActionError(
          const OperationalFailure(OperationalFailureCode.invalidData),
        );
        return;
      }
      await _readAuthoritativeReceipt(command, receipt, session!, revision);
      return;
    }
    state = state.copyWith(isSubmitting: true, actionError: null);
    await _submitCommand(command, session!, revision);
  }

  Future<void> _submitCommand(
    CodReceiptCommand command,
    OperationalSession session,
    int revision,
  ) async {
    try {
      final receipt = await _receiptRepository.confirmReceipt(command);
      if (!_isActionContextValid(session, revision)) return;
      _validateReceipt(receipt, command, managerId: session.userId!);
      _acknowledgedReceipt = receipt;
      await _readAuthoritativeReceipt(command, receipt, session, revision);
    } on Object catch (error) {
      if (!_isActionContextValid(session, revision)) return;
      final failure = mapOperationalFailure(error);
      if (_isFatal(failure)) {
        _clearForAuth(failure);
        return;
      }
      if (_isUncertainReceiptFailure(failure)) {
        // A malformed/undecodable acknowledgement may follow a committed
        // transaction. Retain the exact command and let the user retry that
        // request ID; never create a new money-moving request here.
        state = state.copyWith(
          isSubmitting: false,
          actionError: failure,
          pendingCommand: command,
          requiresReadRetry: false,
        );
        _retainPendingOperation();
        return;
      }
      final retryable = _isRetryableReceiptFailure(failure);
      if (retryable) {
        state = state.copyWith(
          isSubmitting: false,
          actionError: failure,
          pendingCommand: command,
          requiresReadRetry: false,
        );
      } else {
        // A business rejection can mean that the row changed on the server
        // between the dialog snapshot and the RPC.  Clear the command and
        // reload before allowing a new confirmation, so a stale collected
        // row cannot be submitted with a fresh request ID.
        state = state.copyWith(
          isSubmitting: false,
          actionError: failure,
          pendingCommand: null,
          requiresReadRetry: false,
        );
        await _refresh(resetConsistencyBudget: true);
        if (_isActionContextValid(session, revision)) {
          state = state.copyWith(actionError: failure);
        }
        _releasePendingOperationIfIdle();
      }
    }
  }

  Future<void> _readAuthoritativeReceipt(
    CodReceiptCommand command,
    CodReceipt receipt,
    OperationalSession session,
    int revision,
  ) async {
    if (!_isActionContextValid(session, revision)) return;
    if (!_isVisible) {
      _deferredRead = true;
      state = state.copyWith(
        isSubmitting: false,
        pendingCommand: command,
        requiresReadRetry: true,
      );
      _retainPendingOperation();
      return;
    }
    _deferredRead = false;
    state = state.copyWith(isSubmitting: true, actionError: null);
    try {
      final query = CodCollectionQuery(
        orderId: command.orderId,
        limit: CodCollectionQuery.maxPageSize,
      );
      final page = await _repository.queryCollections(query);
      if (!_isActionContextValid(session, revision)) return;
      _validatePage(page, query, firstPage: true);
      if (page.items.length != 1 ||
          page.filteredTotal != 1 ||
          page.nextCursor != null) {
        throw const OperationalFailure(OperationalFailureCode.invalidData);
      }
      final row = page.items.single;
      if (row.orderId.toLowerCase() != command.orderId.toLowerCase() ||
          row.status != CodStatus.received ||
          row.expectedAmountVnd != command.receivedAmountVnd ||
          row.collectedAmountVnd != command.receivedAmountVnd ||
          row.receivedAmountVnd != command.receivedAmountVnd ||
          row.receivedBy != receipt.receivedBy ||
          row.receivedAt == null ||
          row.handedOverAt == null ||
          !_sameInstant(row.receivedAt!, receipt.receivedAt) ||
          !_sameInstant(row.handedOverAt!, receipt.handedOverAt)) {
        throw const OperationalFailure(OperationalFailureCode.invalidData);
      }
      if (!_isVisible) {
        _deferredRead = true;
        state = state.copyWith(
          isSubmitting: false,
          pendingCommand: command,
          requiresReadRetry: true,
        );
        _retainPendingOperation();
        _acknowledgedReceipt = receipt;
        return;
      }

      // Keep the ACK command latched until the manager list itself has been
      // refreshed.  If that final read fails, retryReceipt() will perform a
      // read-only retry and can never submit the money-moving RPC again.
      state = state.copyWith(
        isSubmitting: false,
        actionError: null,
        pendingCommand: command,
        requiresReadRetry: true,
        lastReceipt: null,
      );
      _acknowledgedReceipt = receipt;
      // Invalidate legacy/shipper reads only after the ACK and exact read
      // agree, then reload this manager's filtered list from the server.
      refreshCodReadsAfterConfirmedWrite(ref);
      // Keep the pending operation alive during this reload, rather than
      // invalidating its notifier and losing the acknowledged request.
      await _refresh(resetConsistencyBudget: true);
      if (!_isActionContextValid(session, revision)) return;
      if (!_isVisible) {
        _deferredRead = true;
        state = state.copyWith(
          isSubmitting: false,
          pendingCommand: command,
          requiresReadRetry: true,
        );
        return;
      }
      if (state.error != null) {
        if (_isFatal(state.error!)) {
          _clearForAuth(state.error!);
          return;
        }
        state = state.copyWith(
          isSubmitting: false,
          pendingCommand: command,
          requiresReadRetry: true,
          actionError: state.error,
        );
        return;
      }
      state = state.copyWith(
        isSubmitting: false,
        actionError: null,
        pendingCommand: null,
        requiresReadRetry: false,
        lastReceipt: receipt,
      );
      _acknowledgedReceipt = null;
      _deferredRead = false;
      _releasePendingOperationIfIdle();
    } on Object catch (error) {
      if (!_isActionContextValid(session, revision)) return;
      final failure = mapOperationalFailure(error);
      if (_isFatal(failure)) {
        _clearForAuth(failure);
        return;
      }
      state = state.copyWith(
        isSubmitting: false,
        actionError: failure,
        // The RPC already ACKed.  Retry must read only, never write again.
        pendingCommand: command,
        requiresReadRetry: true,
      );
    }
  }

  Future<void> _fetchFirstPage(
    int request,
    int revision,
    OperationalSession session,
  ) async {
    late final CodCollectionQuery query;
    try {
      query = _query();
      final page = await _repository.queryCollections(query);
      if (!_isCurrent(request, session, revision)) return;
      _validatePage(page, query, firstPage: true);
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
      if (!_isCurrent(request, session, revision)) return;
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

  CodCollectionQuery _query({String? cursor}) => CodCollectionQuery(
    shipperId: state.shipperId,
    orderId: state.orderId,
    statuses: [state.group.status],
    limit: CodCollectionQuery.maxPageSize,
    cursor: cursor,
  );

  void _validatePage(
    CodCollectionPage page,
    CodCollectionQuery query, {
    required bool firstPage,
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
      if (!ids.add(item.orderId.toLowerCase())) {
        throw const OperationalFailure(OperationalFailureCode.invalidData);
      }
      if (query.shipperId != null &&
          item.shipperId?.toLowerCase() != query.shipperId!.toLowerCase()) {
        throw const OperationalFailure(OperationalFailureCode.permissionDenied);
      }
      if (query.orderId != null &&
          item.orderId.toLowerCase() != query.orderId!.toLowerCase()) {
        throw const OperationalFailure(OperationalFailureCode.invalidData);
      }
      if (query.statuses.isNotEmpty && !query.statuses.contains(item.status)) {
        throw const OperationalFailure(OperationalFailureCode.invalidData);
      }
      if (item.outstandingAmountVnd < 0 ||
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
        page.filteredTotal != state.filteredTotal ||
        !_sameCounts(page.counts, state.counts) ||
        page.outstandingVnd != state.heldTotalVnd ||
        (page.nextCursor != null &&
            _requestedCursors.contains(page.nextCursor));
  }

  Future<void> _resetForConsistency(
    OperationalSession session,
    int revision,
  ) async {
    if (!_isCurrent(_requestGeneration, session, revision)) return;
    if (_consistencyResetUsed) {
      _setFatal(const OperationalFailure(OperationalFailureCode.invalidData));
      return;
    }
    _consistencyResetUsed = true;
    await _refresh(resetConsistencyBudget: false);
  }

  void _scheduleSession(AsyncValue<OperationalSession> next) {
    final version = ++_sessionEventVersion;
    scheduleMicrotask(() {
      if (!_isMounted || version != _sessionEventVersion) return;
      _handleSession(next);
    });
  }

  void _scheduleRole(AsyncValue<String> next) {
    final version = ++_roleEventVersion;
    scheduleMicrotask(() {
      if (!_isMounted || version != _roleEventVersion) return;
      _handleRole(next);
    });
  }

  void _handleSession(AsyncValue<OperationalSession> next) {
    if (!_isMounted) return;
    if (next.isLoading) {
      _activeSession = null;
      _sessionRevision++;
      _requestGeneration++;
      _readyRevision = -1;
      _clearForAuth(
        const OperationalFailure(OperationalFailureCode.sessionExpired),
      );
      return;
    }
    if (next.hasError) {
      _activeSession = null;
      _sessionRevision++;
      _requestGeneration++;
      _readyRevision = -1;
      _clearForAuth(mapOperationalFailure(next.error!));
      return;
    }
    final session = next.requireValue;
    if (identical(session, _activeSession)) return;
    _activeSession = session;
    _sessionRevision++;
    _requestGeneration++;
    _readyRevision = -1;
    _clearForAuth(
      session.failure ??
          (!_isSessionUsable(session)
              ? const OperationalFailure(OperationalFailureCode.sessionExpired)
              : (_activeRole != null && _activeRole != 'manager'
                    ? const OperationalFailure(
                        OperationalFailureCode.permissionDenied,
                      )
                    : null)),
    );
    _maybeStartInitialLoad();
  }

  void _handleRole(AsyncValue<String> next) {
    if (!_isMounted) return;
    if (next.isLoading) {
      _activeRole = null;
      _sessionRevision++;
      _requestGeneration++;
      _readyRevision = -1;
      _clearForAuth(
        const OperationalFailure(OperationalFailureCode.sessionExpired),
      );
      return;
    }
    if (next.hasError) {
      _activeRole = null;
      _sessionRevision++;
      _requestGeneration++;
      _readyRevision = -1;
      _clearForAuth(mapOperationalFailure(next.error!));
      return;
    }
    final role = next.requireValue;
    final changed = role != _activeRole;
    _activeRole = role;
    if (changed) {
      _sessionRevision++;
      _requestGeneration++;
      _readyRevision = -1;
      if (role != 'manager') {
        _clearForAuth(
          const OperationalFailure(OperationalFailureCode.permissionDenied),
        );
      } else {
        _clearForAuth(
          _isSessionUsable(_activeSession)
              ? null
              : const OperationalFailure(OperationalFailureCode.sessionExpired),
        );
      }
    }
    _maybeStartInitialLoad();
  }

  void _maybeStartInitialLoad() {
    if (!_isMounted ||
        !_isVisible ||
        _readyRevision == _sessionRevision ||
        !_isSessionUsable(_activeSession) ||
        _activeRole != 'manager') {
      return;
    }
    _readyRevision = _sessionRevision;
    unawaited(refresh());
  }

  void _resumeVisibleWork() {
    if (!_isMounted || !_isVisible) return;
    final command = state.pendingCommand;
    final receipt = _acknowledgedReceipt;
    if (_deferredRead &&
        command != null &&
        receipt != null &&
        state.requiresReadRetry &&
        !state.isSubmitting &&
        _isActionContextValid(_activeSession, _sessionRevision)) {
      _deferredRead = false;
      unawaited(
        _readAuthoritativeReceipt(
          command,
          receipt,
          _activeSession!,
          _sessionRevision,
        ),
      );
      return;
    }
    if (state.pendingCommand == null &&
        !state.isSubmitting &&
        _activeRole == 'manager' &&
        _isSessionUsable(_activeSession) &&
        (state.isLoading || _readyRevision != _sessionRevision)) {
      _readyRevision = -1;
      _maybeStartInitialLoad();
    }
  }

  void _retainPendingOperation() {
    if (_closePendingKeepAlive == null) {
      final link = ref.keepAlive();
      _closePendingKeepAlive = link.close;
      // Pending financial commands must notice logout/role changes even while
      // this auto-dispose provider is paused with no visible screen listener.
      // These observers watch auth only; they never start hidden COD reads.
      final sessionObserver = ref.container
          .listen<AsyncValue<OperationalSession>>(
            operationalSessionProvider,
            (_, next) => _scheduleSession(next),
          );
      final roleObserver = ref.container.listen<AsyncValue<String>>(
        codScreenRoleProvider,
        (_, next) => _scheduleRole(next),
      );
      _closePendingObservers = () {
        sessionObserver.close();
        roleObserver.close();
      };
    }
  }

  void _releasePendingOperationIfIdle() {
    if (state.pendingCommand != null ||
        state.isSubmitting ||
        _acknowledgedReceipt != null ||
        _deferredRead) {
      return;
    }
    _closePendingObservers?.call();
    _closePendingObservers = null;
    _closePendingKeepAlive?.call();
    _closePendingKeepAlive = null;
  }

  void _clearForAuth(OperationalFailure? failure) {
    if (!_isMounted) return;
    _requestGeneration++;
    _requestedCursors.clear();
    _acknowledgedReceipt = null;
    _deferredRead = false;
    state = ManagerCodState.initial(
      // Filters are user-scoped drafts.  Never carry a shipper/order filter
      // from one account or role epoch into the next.  An order supplied by
      // the route is retained only as a new deep-link scope and is rechecked
      // by the server on the next read.
      shipperId: null,
      orderId: initialOrderId,
      group: state.group,
      isLoading: failure == null,
      error: failure,
    );
    _releasePendingOperationIfIdle();
  }

  void _setFatal(OperationalFailure failure) {
    _requestGeneration++;
    _requestedCursors.clear();
    _acknowledgedReceipt = null;
    state = ManagerCodState.initial(
      shipperId: state.shipperId,
      orderId: state.orderId,
      group: state.group,
      isLoading: false,
      error: failure,
    );
  }

  void _setActionError(OperationalFailure failure) {
    if (!_isMounted) return;
    state = state.copyWith(actionError: failure, isSubmitting: false);
  }

  CodCollection? _findCurrentRow(String orderId) {
    for (final row in state.items) {
      if (row.orderId.toLowerCase() == orderId.toLowerCase()) return row;
    }
    return null;
  }

  void _validateReceipt(
    CodReceipt receipt,
    CodReceiptCommand command, {
    required String managerId,
  }) {
    if (receipt.orderId.toLowerCase() != command.orderId.toLowerCase() ||
        receipt.status != CodReceiptStatus.received ||
        receipt.receivedAmountVnd != command.receivedAmountVnd ||
        receipt.receivedBy.toLowerCase() != managerId.toLowerCase() ||
        !_sameInstant(receipt.receivedAt, receipt.handedOverAt) ||
        receipt.eventId.trim().isEmpty ||
        receipt.notificationId.trim().isEmpty) {
      throw const CodReceiptAcknowledgementFailure();
    }
  }

  bool get _canChangeListScope =>
      _isMounted && !state.isSubmitting && state.pendingCommand == null;

  OperationalFailure? get _roleFailure {
    if (_activeRole == null) {
      return const OperationalFailure(OperationalFailureCode.sessionExpired);
    }
    if (_activeRole != 'manager') {
      return const OperationalFailure(OperationalFailureCode.permissionDenied);
    }
    return null;
  }

  CodReceiptRepository get _receiptRepository =>
      ref.read(codReceiptRepositoryProvider);

  bool _isSessionUsable(OperationalSession? session) =>
      session != null && session.userId != null && session.failure == null;

  bool _isActionContextValid(OperationalSession? session, int revision) =>
      _isMounted &&
      revision == _sessionRevision &&
      identical(session, _activeSession) &&
      _activeRole == 'manager' &&
      _isSessionUsable(session);

  bool _isCurrent(int request, OperationalSession? session, int revision) =>
      _isMounted &&
      request == _requestGeneration &&
      revision == _sessionRevision &&
      identical(session, _activeSession) &&
      _activeRole == 'manager' &&
      _isSessionUsable(session);

  bool _isFatal(OperationalFailure failure) => switch (failure.code) {
    OperationalFailureCode.sessionExpired ||
    OperationalFailureCode.permissionDenied ||
    OperationalFailureCode.staleAssignment => true,
    _ => false,
  };

  bool _isRetryableReceiptFailure(OperationalFailure failure) =>
      failure.code == OperationalFailureCode.network ||
      failure.code == OperationalFailureCode.backendUnavailable ||
      failure.code == OperationalFailureCode.unexpected;

  bool _isUncertainReceiptFailure(OperationalFailure failure) =>
      failure is CodReceiptAcknowledgementFailure;

  bool _sameCounts(CodCollectionCounts? left, CodCollectionCounts? right) {
    if (left == null || right == null) return left == right;
    return left.all == right.all &&
        left.uncollected == right.uncollected &&
        left.collected == right.collected &&
        left.received == right.received;
  }

  static bool _sameInstant(DateTime left, DateTime right) =>
      left.toUtc() == right.toUtc();

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
