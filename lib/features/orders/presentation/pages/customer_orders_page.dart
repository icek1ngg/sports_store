import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/presentation_failure_message.dart';
import '../../../../core/state/epoch_cache.dart';
import '../../../../core/state/foundation_providers.dart';
import '../../../../core/state/read_snapshot.dart';
import '../../../../core/state/session_scope.dart';
import '../../../../core/utils/display_formatters.dart';
import '../../../../shared/widgets/async_content.dart';
import '../../../../shared/widgets/feature_access_gate.dart';
import '../../../../shared/widgets/foreground_refresh.dart';
import '../../domain/models/order_details.dart';
import '../../domain/models/order_page.dart';
import '../../domain/models/order_query.dart';
import '../../domain/models/order_status.dart';
import '../../domain/models/order_summary.dart';
import '../../domain/models/return_summary.dart';
import '../../presentation/view_models/order_providers.dart';
import '../widgets/order_action_dialog.dart';
import '../widgets/order_feed.dart';
import '../widgets/order_items_section.dart';
import '../widgets/order_payment_section.dart';
import '../widgets/order_recipient_section.dart';
import '../widgets/order_timeline.dart';
import '../widgets/order_notification_theme.dart';
import '../widgets/mh07_order_card.dart';

/// MH07 — the authenticated customer's order list.
///
/// The central router can place this page at its role route. Return callbacks
/// are intentionally optional because Returns owns those routes; an absent
/// callback leaves a visible, disabled unavailable action.
class CustomerOrdersPage extends StatelessWidget {
  const CustomerOrdersPage({
    this.onCreateReturn,
    this.onOpenReturn,
    this.onOpenCatalog,
    this.enablePolling = true,
    this.showPreviewNavigation = false,
    super.key,
  });

  final ValueChanged<String>? onCreateReturn;
  final ValueChanged<String>? onOpenReturn;
  final VoidCallback? onOpenCatalog;
  final bool enablePolling;
  final bool showPreviewNavigation;

  @override
  Widget build(BuildContext context) {
    return OrderNotificationTheme(
      child: FeatureAccessGate(
        roles: const {'customer'},
        child: _CustomerOrdersBody(
          onCreateReturn: onCreateReturn,
          onOpenReturn: onOpenReturn,
          onOpenCatalog: onOpenCatalog,
          enablePolling: enablePolling,
          showPreviewNavigation: showPreviewNavigation,
        ),
      ),
    );
  }
}

class _CustomerOrdersBody extends ConsumerStatefulWidget {
  const _CustomerOrdersBody({
    required this.onCreateReturn,
    required this.onOpenReturn,
    required this.onOpenCatalog,
    required this.enablePolling,
    required this.showPreviewNavigation,
  });

  final ValueChanged<String>? onCreateReturn;
  final ValueChanged<String>? onOpenReturn;
  final VoidCallback? onOpenCatalog;
  final bool enablePolling;
  final bool showPreviewNavigation;

  @override
  ConsumerState<_CustomerOrdersBody> createState() =>
      _CustomerOrdersBodyState();
}

class _CustomerOrdersBodyState extends ConsumerState<_CustomerOrdersBody> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _searchDebounce;

  OrderQuery _baseQuery = OrderQuery();
  OrderPage? _canonicalPage;
  final _rows = <OrderSummary>[];
  final _cursorHistory = <String>[];
  final _processedNextPages = <String, OrderPage>{};
  final _detailRequestedIds = <String>{};
  String? _nextCursor;
  AppFailure? _moreFailure;
  String? _searchError;
  bool _loadingMore = false;
  bool _canonicalFresh = false;
  bool _hideCanonicalSnapshot = false;
  AppFailure? _privateDataFailure;
  bool _privateRefreshRequested = false;
  var _queryGeneration = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(featureSessionScopeProvider);
    ref.listen<SessionScope>(featureSessionScopeProvider, (previous, next) {
      if (previous != next) _resetForSession(next);
    });

    final canonicalQuery = _baseQuery.copyWith(cursor: null);
    final generation = _queryGeneration;
    final canonicalProvider = orderListFoundationProvider(canonicalQuery);
    final canonicalValue = ref.watch(canonicalProvider);
    ref.listen<AsyncValue<ReadSnapshot<OrderPage>>>(canonicalProvider, (
      previous,
      next,
    ) {
      _consumeCanonical(generation, next);
    });

    final nextCursor = _nextCursor;
    AsyncValue<ReadSnapshot<OrderPage>>? nextValue;
    if ((_loadingMore || _moreFailure != null) && nextCursor != null) {
      final nextQuery = canonicalQuery.copyWith(cursor: nextCursor);
      final nextProvider = orderListFoundationProvider(nextQuery);
      nextValue = ref.watch(nextProvider);
      ref.listen<AsyncValue<ReadSnapshot<OrderPage>>>(nextProvider, (
        previous,
        next,
      ) {
        _consumeNext(generation, nextCursor, next);
      });
    }

    final snapshot = orderPageSnapshot(canonicalValue);
    if (_privateDataFailure == null &&
        !_hideCanonicalSnapshot &&
        _canonicalPage == null &&
        snapshot.data != null &&
        !snapshot.loading &&
        !snapshot.stale &&
        snapshot.failure == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_privateDataFailure == null &&
            !_hideCanonicalSnapshot &&
            _canonicalPage == null) {
          _consumeCanonical(generation, canonicalValue);
        }
      });
    }
    if (nextValue != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _consumeNextIfAlreadySettled(generation, nextCursor!, nextValue!);
      });
    }
    final privateFailure =
        _privateDataFailure ??
        (_isPrivateDataFailure(snapshot.failure) ? snapshot.failure : null);
    final effectiveSnapshot = privateFailure != null
        ? ReadSnapshot<OrderPage>(failure: privateFailure)
        : _hideCanonicalSnapshot
        ? const ReadSnapshot<OrderPage>(loading: true)
        : snapshot;
    final privateDataUnavailable =
        _hideCanonicalSnapshot || privateFailure != null;
    final visibleRows = privateDataUnavailable
        ? const <OrderSummary>[]
        : _rows.isEmpty && effectiveSnapshot.data != null
        ? effectiveSnapshot.data!.items
        : List<OrderSummary>.unmodifiable(_rows);
    final page = privateDataUnavailable
        ? null
        : _canonicalPage ?? effectiveSnapshot.data;

    return Scaffold(
      appBar: _mh07AppBar(context),
      bottomNavigationBar:
          widget.showPreviewNavigation &&
              MediaQuery.viewInsetsOf(context).bottom == 0
          ? const Mh07PreviewNavigation()
          : null,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Flexible(
              flex: 0,
              fit: FlexFit.loose,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight:
                      (MediaQuery.sizeOf(context).height -
                              MediaQuery.viewInsetsOf(context).bottom -
                              64)
                          .clamp(0.0, double.infinity) *
                      .55,
                ),
                child: SingleChildScrollView(
                  child: _CustomerListHeader(
                    compact: MediaQuery.viewInsetsOf(context).bottom > 0,
                    totalCount: page?.totalCount,
                    searchController: _searchController,
                    searchError: _searchError,
                    onSearchChanged: _onSearchChanged,
                    onClearSearch: _clearSearch,
                    statuses: _baseQuery.statuses,
                    counts: page?.statusCounts,
                    onStatusSelected: _onStatusSelected,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ForegroundRefresh(
                enabled: widget.enablePolling,
                onRefresh: () => unawaited(_refreshCanonical()),
                canRefresh: () =>
                    _canRead &&
                    effectiveSnapshot.data != null &&
                    !effectiveSnapshot.loading &&
                    effectiveSnapshot.failure == null,
                child: OrderFeed(
                  listPadding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  listFooter: const Mh07SupportPanel(),
                  itemBuilder: (context, row) {
                    final activeReturn = row.returnSummary?.isActive == true;
                    final delivered = row.order.status == OrderStatus.delivered;
                    final canReturn =
                        !effectiveSnapshot.stale &&
                        _isReturnCreationAllowed(row);
                    return Mh07OrderCard(
                      summary: row,
                      stale: effectiveSnapshot.stale,
                      onDetails: () => _openDetails(row.order.id),
                      onCancel:
                          !effectiveSnapshot.stale &&
                              _isActionAllowed(
                                row,
                                OrderOperation.customerCancel,
                              )
                          ? () => _showActionDialog(
                              row.order.id,
                              OrderOperation.customerCancel,
                            )
                          : null,
                      returnLabel: activeReturn
                          ? widget.onOpenReturn == null
                                ? 'Yêu cầu trả hàng chưa khả dụng'
                                : 'Xem yêu cầu trả hàng'
                          : delivered
                          ? canReturn && widget.onCreateReturn != null
                                ? 'Yêu cầu trả hàng'
                                : 'Yêu cầu trả hàng chưa khả dụng'
                          : null,
                      onReturn: activeReturn && widget.onOpenReturn != null
                          ? () => widget.onOpenReturn!(
                              row.returnSummary!.returnId,
                            )
                          : delivered &&
                                canReturn &&
                                widget.onCreateReturn != null
                          ? () => widget.onCreateReturn!(row.order.id)
                          : null,
                    );
                  },
                  snapshot: effectiveSnapshot,
                  orders: visibleRows,
                  scrollController: _scrollController,
                  onRefresh: _refreshCanonical,
                  onRetry: () => unawaited(_refreshCanonical()),
                  onLoadMore: _requestLoadMore,
                  onRetryMore: () => _requestLoadMore(force: true),
                  loadingMore: _loadingMore,
                  moreFailure: _moreFailure,
                  canLoadMore:
                      _canonicalFresh && _nextCursor != null && !_loadingMore,
                  onOpenOrder: _openDetails,
                  onCustomerCancel: (id) =>
                      _showActionDialog(id, OrderOperation.customerCancel),
                  onCreateReturn: widget.onCreateReturn,
                  onOpenReturn: widget.onOpenReturn,
                  actionPredicate: _isActionAllowed,
                  returnCreationPredicate: _isReturnCreationAllowed,
                  emptyMessage: _emptyMessage,
                  emptyActionLabel: _showCatalogAction ? 'Mở danh mục' : null,
                  onEmptyAction: _showCatalogAction
                      ? widget.onOpenCatalog
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  AppBar _mh07AppBar(BuildContext context) => AppBar(
    automaticallyImplyLeading: false,
    titleSpacing: 20,
    toolbarHeight: 64,
    title: Row(
      children: [
        if (MediaQuery.textScalerOf(context).scale(14) <= 21)
          Flexible(
            child: const Text(
              'VN ATHLETICS',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'BarlowCondensed',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'ĐƠN HÀNG',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'BarlowCondensed',
              fontSize: 28,
              fontWeight: FontWeight.w700,
              height: 32 / 28,
              letterSpacing: -.5,
            ),
          ),
        ),
      ],
    ),
    actions: [
      IconButton(
        tooltip: 'Làm mới đơn hàng',
        onPressed: _canRead ? () => unawaited(_refreshCanonical()) : null,
        icon: const Icon(Icons.refresh, size: 24),
      ),
      const Padding(
        padding: EdgeInsets.only(right: 20),
        child: CircleAvatar(
          radius: 16,
          backgroundColor: mh07Ink,
          child: Icon(Icons.person_outline, size: 18, color: Colors.white),
        ),
      ),
    ],
    elevation: 1,
    shadowColor: Colors.black.withValues(alpha: .04),
  );

  bool get _canRead {
    final scope = ref.read(featureSessionScopeProvider);
    return scope.role == 'customer' &&
        scope.canReadPrivateData &&
        ref.read(epochCacheProvider).canRead;
  }

  bool get _showCatalogAction =>
      _baseQuery.search == null && _baseQuery.statuses.isEmpty;

  String get _emptyMessage {
    if (_baseQuery.search != null || _baseQuery.statuses.isNotEmpty) {
      return 'Không tìm thấy đơn hàng phù hợp';
    }
    return 'Bạn chưa có đơn hàng';
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (value.runes.length > 200) {
      setState(() {
        _searchError = 'Từ khóa tìm kiếm tối đa 200 ký tự Unicode.';
      });
      return;
    }
    if (_searchError != null) {
      setState(() => _searchError = null);
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _setQuery(
        OrderQuery(
          search: value,
          statuses: _baseQuery.statuses,
          limit: _baseQuery.limit,
        ),
      );
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    if (_searchError != null) {
      setState(() => _searchError = null);
    }
    _setQuery(
      OrderQuery(statuses: _baseQuery.statuses, limit: _baseQuery.limit),
    );
  }

  void _onStatusSelected(OrderStatus? status) {
    _setQuery(
      OrderQuery(
        search: _baseQuery.search,
        statuses: status == null ? const [] : [status],
        limit: _baseQuery.limit,
      ),
    );
  }

  void _setQuery(OrderQuery query) {
    if (query == _baseQuery) return;
    setState(() {
      _baseQuery = query.copyWith(cursor: null);
      _queryGeneration++;
      _canonicalPage = null;
      _canonicalFresh = false;
      _hideCanonicalSnapshot = true;
      _privateRefreshRequested = false;
      _rows.clear();
      _detailRequestedIds.clear();
      _resetExtraCursors();
    });
  }

  void _resetForSession(SessionScope scope) {
    if (!mounted) return;
    setState(() {
      _queryGeneration++;
      _canonicalPage = null;
      _canonicalFresh = false;
      _hideCanonicalSnapshot = true;
      _privateDataFailure = null;
      _privateRefreshRequested = false;
      _rows.clear();
      _detailRequestedIds.clear();
      _resetExtraCursors();
    });
  }

  void _resetExtraCursors() {
    _nextCursor = null;
    _cursorHistory.clear();
    _processedNextPages.clear();
    _moreFailure = null;
    _loadingMore = false;
  }

  bool get _hasPrivateState =>
      !_hideCanonicalSnapshot ||
      _privateDataFailure == null ||
      _canonicalPage != null ||
      _rows.isNotEmpty ||
      _detailRequestedIds.isNotEmpty ||
      _canonicalFresh ||
      _nextCursor != null ||
      _cursorHistory.isNotEmpty ||
      _processedNextPages.isNotEmpty ||
      _moreFailure != null ||
      _loadingMore;

  bool _isPrivateDataFailure(AppFailure? failure) =>
      failure?.code == AppFailure.unauthenticated ||
      failure?.code == AppFailure.forbiddenOrUnavailable;

  void _clearPrivateData(AppFailure failure) {
    if (!mounted || !_hasPrivateState) return;
    setState(() {
      _canonicalPage = null;
      _canonicalFresh = false;
      _hideCanonicalSnapshot = true;
      _privateDataFailure = failure;
      _privateRefreshRequested = false;
      _rows.clear();
      _detailRequestedIds.clear();
      _resetExtraCursors();
    });
  }

  void _consumeCanonical(
    int generation,
    AsyncValue<ReadSnapshot<OrderPage>> value,
  ) {
    if (!mounted || generation != _queryGeneration) return;
    final snapshot = orderPageSnapshot(value);
    final page = snapshot.data;
    final failure = snapshot.failure;
    if (_isPrivateDataFailure(failure)) {
      _clearPrivateData(failure!);
      return;
    }
    if (_privateDataFailure != null && !_privateRefreshRequested) return;
    if (snapshot.loading || snapshot.stale || failure != null) {
      if (_canonicalFresh) setState(() => _canonicalFresh = false);
      return;
    }
    if (page == null || (_canonicalFresh && identical(page, _canonicalPage))) {
      return;
    }
    setState(() {
      _canonicalPage = page;
      _canonicalFresh = true;
      _hideCanonicalSnapshot = false;
      _privateDataFailure = null;
      _privateRefreshRequested = false;
      _detailRequestedIds.clear();
      _rows
        ..clear()
        ..addAll(page.items);
      _nextCursor = page.nextCursor;
      _cursorHistory.clear();
      _processedNextPages.clear();
      _moreFailure = null;
      _loadingMore = false;
    });
  }

  void _consumeNextIfAlreadySettled(
    int generation,
    String cursor,
    AsyncValue<ReadSnapshot<OrderPage>> value,
  ) {
    final snapshot = orderPageSnapshot(value);
    if (snapshot.loading) return;
    if (snapshot.failure != null) {
      _consumeNext(generation, cursor, value);
    } else if (!snapshot.stale && snapshot.data != null) {
      _consumeNext(generation, cursor, value);
    }
  }

  void _consumeNext(
    int generation,
    String cursor,
    AsyncValue<ReadSnapshot<OrderPage>> value,
  ) {
    if (!mounted || generation != _queryGeneration || cursor != _nextCursor) {
      return;
    }
    final snapshot = orderPageSnapshot(value);
    final page = snapshot.data;
    if (snapshot.failure != null) {
      if (_isPrivateDataFailure(snapshot.failure)) {
        _clearPrivateData(snapshot.failure!);
        return;
      }
      if (snapshot.failure!.code == AppFailure.invalidCursor) {
        setState(() {
          _canonicalFresh = false;
          _resetExtraCursors();
        });
        unawaited(_refreshCanonical());
        return;
      }
      if (!_loadingMore) return;
      setState(() {
        _loadingMore = false;
        _moreFailure = snapshot.failure;
      });
      return;
    }
    if (page == null ||
        snapshot.loading ||
        snapshot.stale ||
        identical(page, _processedNextPages[cursor])) {
      return;
    }
    setState(() {
      _processedNextPages[cursor] = page;
      final byId = <String, OrderSummary>{
        for (final row in _rows) row.order.id: row,
      };
      for (final row in page.items) {
        byId[row.order.id] = row;
      }
      _rows
        ..clear()
        ..addAll(byId.values);
      _nextCursor = page.nextCursor == cursor ? null : page.nextCursor;
      _loadingMore = false;
      _moreFailure = null;
    });
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients || _loadingMore || _nextCursor == null) {
      return;
    }
    if (_scrollController.position.maxScrollExtent <= 0) return;
    if (_scrollController.position.extentAfter < 360) _requestLoadMore();
  }

  void _requestLoadMore({bool force = false}) {
    if (!_canRead || !_canonicalFresh || _loadingMore) return;
    final cursor = _nextCursor;
    if (cursor == null) return;
    if (!force && _cursorHistory.contains(cursor)) return;
    setState(() {
      _cursorHistory.add(cursor);
      _moreFailure = null;
      _loadingMore = true;
    });
    if (force) _refreshNextPageAfterBuild(cursor);
  }

  void _refreshNextPageAfterBuild(String cursor) {
    final query = _baseQuery.copyWith(cursor: cursor);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_loadingMore || _nextCursor != cursor) return;
      unawaited(
        ref.read(orderListFoundationProvider(query).notifier).refresh(),
      );
    });
  }

  Future<void> _refreshCanonical() async {
    if (!_canRead) return;
    setState(() {
      _canonicalFresh = false;
      _privateRefreshRequested = true;
      _resetExtraCursors();
    });
    final query = _baseQuery.copyWith(cursor: null);
    await ref.read(orderListFoundationProvider(query).notifier).refresh();
  }

  bool _isActionAllowed(OrderSummary summary, OrderOperation operation) {
    if (!_canRead || !_canonicalFresh || _canonicalPage == null) return false;
    var status = summary.order.status;
    var capabilities = summary.capabilities;
    if (_detailRequestedIds.contains(summary.order.id)) {
      final cached = ref
          .read(epochCacheProvider)
          .read<OrderDetails>('orders/detail/${summary.order.id}');
      if (cached == null || cached.stale) return false;
      status = cached.data.order.status;
      capabilities = cached.data.capabilities;
    }
    return operation == OrderOperation.customerCancel
        ? status == OrderStatus.pendingConfirmation &&
              capabilities.canCancelCustomer
        : false;
  }

  bool _isReturnCreationAllowed(OrderSummary summary) {
    if (!_canRead || !_canonicalFresh || _canonicalPage == null) return false;
    var status = summary.order.status;
    var capabilities = summary.capabilities;
    if (_detailRequestedIds.contains(summary.order.id)) {
      final cached = ref
          .read(epochCacheProvider)
          .read<OrderDetails>('orders/detail/${summary.order.id}');
      if (cached == null || cached.stale) return false;
      status = cached.data.order.status;
      capabilities = cached.data.capabilities;
    }
    return status == OrderStatus.delivered &&
        capabilities.canOpenReturnCreation;
  }

  Future<void> _showActionDialog(
    String orderId,
    OrderOperation operation,
  ) async {
    if (!_canRead) return;
    final summary = _findSummary(orderId);
    if (summary == null || !_isActionAllowed(summary, operation)) return;
    final submittedScope = ref.read(featureSessionScopeProvider);
    await showDialog<void>(
      context: context,
      builder: (context) => OrderActionDialog(
        orderId: orderId,
        operation: operation,
        submittedScope: submittedScope,
        isStillAllowed: () {
          final current = _findSummary(orderId);
          return current != null && _isActionAllowed(current, operation);
        },
      ),
    );
  }

  OrderSummary? _findSummary(String orderId) {
    for (final item in _rows) {
      if (item.order.id == orderId) return item;
    }
    for (final item in _canonicalPage?.items ?? const <OrderSummary>[]) {
      if (item.order.id == orderId) return item;
    }
    return null;
  }

  Future<void> _openDetails(String orderId) async {
    if (!_canRead) return;
    final capturedScope = ref.read(featureSessionScopeProvider);
    _detailRequestedIds.add(orderId);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _CustomerOrderDetailsSheet(
        orderId: orderId,
        capturedScope: capturedScope,
        onCreateReturn: widget.onCreateReturn,
        onOpenReturn: widget.onOpenReturn,
        enablePolling: widget.enablePolling,
      ),
    );
    if (mounted && ref.read(featureSessionScopeProvider) == capturedScope) {
      await _refreshCanonical();
    }
  }
}

class _CustomerListHeader extends StatelessWidget {
  const _CustomerListHeader({
    required this.compact,
    required this.totalCount,
    required this.searchController,
    required this.searchError,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.statuses,
    required this.counts,
    required this.onStatusSelected,
  });

  final int? totalCount;
  final TextEditingController searchController;
  final bool compact;
  final String? searchError;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final List<OrderStatus> statuses;
  final Map<OrderStatus, int>? counts;
  final ValueChanged<OrderStatus?> onStatusSelected;

  @override
  Widget build(BuildContext context) {
    final selected = statuses.length == 1 ? statuses.single : null;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!compact) ...[
              const Text(
                'TÀI KHOẢN CÁ NHÂN',
                style: TextStyle(
                  fontFamily: 'BarlowCondensed',
                  fontSize: 14,
                  height: 16 / 14,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                  color: mh07Muted,
                ),
              ),
              const SizedBox(height: 2),
              LayoutBuilder(
                builder: (context, constraints) {
                  final title = const Text(
                    'ĐƠN HÀNG CỦA TÔI',
                    style: TextStyle(
                      fontFamily: 'BarlowCondensed',
                      fontSize: 32,
                      height: 36 / 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.5,
                    ),
                  );
                  final count = Text(
                    totalCount == null
                        ? 'Đang cập nhật số lượng đơn'
                        : '$totalCount đơn hàng',
                    style: const TextStyle(
                      fontSize: 11,
                      height: 16 / 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xff9e9ea0),
                    ),
                  );
                  if (MediaQuery.textScalerOf(context).scale(14) > 18 ||
                      constraints.maxWidth < 300) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, const SizedBox(height: 4), count],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: count,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              key: const ValueKey('customer-order-search'),
              controller: searchController,
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Tìm theo mã đơn hoặc sản phẩm...',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                errorText: searchError,
                prefixIcon: const Icon(
                  Icons.search,
                  size: 20,
                  color: Color(0xff9e9ea0),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 40,
                ),
                suffixIcon: searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Xóa tìm kiếm',
                        onPressed: onClearSearch,
                        icon: const Icon(Icons.clear),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            _StatusChips(
              selected: selected,
              counts: counts,
              onSelected: onStatusSelected,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChips extends StatelessWidget {
  const _StatusChips({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  final OrderStatus? selected;
  final Map<OrderStatus, int>? counts;
  final ValueChanged<OrderStatus?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _chip(
              context,
              label: 'Tất cả',
              selected: selected == null,
              count: counts?.values.fold<int>(0, (a, b) => a + b),
              onSelected: (_) => onSelected(null),
            ),
            ...OrderStatus.values.map(
              (status) => _chip(
                context,
                label: orderStatusLabel(status),
                selected: selected == status,
                count: counts?[status],
                onSelected: (_) =>
                    onSelected(selected == status ? null : status),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool selected,
    required int? count,
    required ValueChanged<bool> onSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: FilterChip(
        selected: selected,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        onSelected: onSelected,
        label: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : OrderNotificationTheme.muted,
          ),
        ),
      ),
    );
  }
}

class _CustomerOrderDetailsSheet extends ConsumerStatefulWidget {
  const _CustomerOrderDetailsSheet({
    required this.orderId,
    required this.capturedScope,
    required this.onCreateReturn,
    required this.onOpenReturn,
    required this.enablePolling,
  });

  final String orderId;
  final SessionScope capturedScope;
  final ValueChanged<String>? onCreateReturn;
  final ValueChanged<String>? onOpenReturn;
  final bool enablePolling;

  @override
  ConsumerState<_CustomerOrderDetailsSheet> createState() =>
      _CustomerOrderDetailsSheetState();
}

class _CustomerOrderDetailsSheetState
    extends ConsumerState<_CustomerOrderDetailsSheet> {
  late final EpochCache _capturedCache;
  ProviderSubscription<SessionScope>? _scopeSubscription;
  var _blockScheduled = false;

  @override
  void initState() {
    super.initState();
    _capturedCache = EpochCache(widget.capturedScope);
    _scopeSubscription = ref.listenManual<SessionScope>(
      featureSessionScopeProvider,
      (previous, next) {
        if (next != widget.capturedScope) {
          _capturedCache.blockSession();
        }
      },
    );
  }

  @override
  void dispose() {
    _scopeSubscription?.close();
    _capturedCache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(featureSessionScopeProvider);
    if (scope != widget.capturedScope ||
        scope.role != 'customer' ||
        !scope.canReadPrivateData ||
        !ref.watch(epochCacheProvider).canRead) {
      _scheduleCapturedBlock();
      return const SessionUnavailableState(
        message: 'Chi tiết đơn hàng hiện không khả dụng.',
      );
    }
    return ProviderScope(
      overrides: [
        featureSessionScopeProvider.overrideWithValue(widget.capturedScope),
        epochCacheProvider.overrideWithValue(_capturedCache),
        orderDetailsFoundationProvider(
          widget.orderId,
        ).overrideWith(() => OrderDetailsFoundationViewModel(widget.orderId)),
      ],
      child: FeatureAccessGate(
        roles: const {'customer'},
        child: _CustomerOrderDetailsContent(
          orderId: widget.orderId,
          capturedScope: widget.capturedScope,
          onCreateReturn: widget.onCreateReturn,
          onOpenReturn: widget.onOpenReturn,
          enablePolling: widget.enablePolling,
          canReadCaptured: () => _capturedScopeCanRead,
        ),
      ),
    );
  }

  void _scheduleCapturedBlock() {
    if (_blockScheduled || !_capturedCache.canRead) return;
    _blockScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _blockScheduled = false;
      if (mounted && _capturedCache.canRead) _capturedCache.blockSession();
    });
  }

  bool get _capturedScopeCanRead {
    final scope = ref.read(featureSessionScopeProvider);
    return scope == widget.capturedScope &&
        scope.role == 'customer' &&
        scope.canReadPrivateData &&
        ref.read(epochCacheProvider).canRead;
  }
}

class _CustomerOrderDetailsContent extends ConsumerWidget {
  const _CustomerOrderDetailsContent({
    required this.orderId,
    required this.capturedScope,
    required this.onCreateReturn,
    required this.onOpenReturn,
    required this.enablePolling,
    required this.canReadCaptured,
  });

  final String orderId;
  final SessionScope capturedScope;
  final ValueChanged<String>? onCreateReturn;
  final ValueChanged<String>? onOpenReturn;
  final bool enablePolling;
  final bool Function() canReadCaptured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(orderDetailsFoundationProvider(orderId));
    final snapshot =
        value.value ?? const ReadSnapshot<OrderDetails>(loading: true);
    final detail = snapshot.data;

    Future<void> refresh() async {
      if (!canReadCaptured() || !ref.read(epochCacheProvider).canRead) return;
      await ref
          .read(orderDetailsFoundationProvider(orderId).notifier)
          .refresh();
    }

    return ForegroundRefresh(
      enabled: enablePolling,
      onRefresh: () => unawaited(refresh()),
      canRefresh: () =>
          canReadCaptured() &&
          ref.read(epochCacheProvider).canRead &&
          snapshot.data != null &&
          !snapshot.loading &&
          snapshot.failure == null,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .9,
          child: AsyncContent(
            hasData: detail != null,
            isInitialLoading: snapshot.isInitialLoading,
            isRefreshing: snapshot.loading && detail != null,
            failure: snapshot.failure,
            errorMessage: snapshot.failure == null
                ? null
                : failureMessage(snapshot.failure),
            isStale: snapshot.stale,
            onRetry: () => unawaited(refresh()),
            child: detail == null
                ? const SizedBox.shrink()
                : _CustomerOrderDetailsBody(
                    detail: detail,
                    orderId: orderId,
                    onCreateReturn: onCreateReturn,
                    onOpenReturn: onOpenReturn,
                    onAction: (operation, detail) =>
                        _showAction(context, ref, operation, detail),
                    isStillAllowed: (operation, detail) =>
                        _isStillAllowed(ref, operation, detail),
                    isReturnCreationStillAllowed: (detail) =>
                        _isReturnCreationStillAllowed(ref, detail),
                  ),
          ),
        ),
      ),
    );
  }

  bool _isStillAllowed(
    WidgetRef ref,
    OrderOperation operation,
    OrderDetails detail,
  ) {
    final current = _freshOwnedDetail(ref);
    if (current == null) return false;
    if (operation == OrderOperation.customerCancel) {
      return current.order.status == OrderStatus.pendingConfirmation &&
          current.capabilities.canCancelCustomer;
    }
    return false;
  }

  bool _isReturnCreationStillAllowed(WidgetRef ref, OrderDetails detail) {
    final current = _freshOwnedDetail(ref);
    if (current == null) return false;
    return current.order.status == OrderStatus.delivered &&
        current.capabilities.canOpenReturnCreation;
  }

  OrderDetails? _freshOwnedDetail(WidgetRef ref) {
    final snapshot = ref.read(orderDetailsFoundationProvider(orderId)).value;
    final current = snapshot?.data;
    if (!canReadCaptured() ||
        !ref.read(epochCacheProvider).canRead ||
        current == null ||
        snapshot!.stale ||
        snapshot.loading ||
        snapshot.failure != null ||
        current.order.id != orderId ||
        current.order.customerId != capturedScope.userId) {
      return null;
    }
    return current;
  }

  Future<void> _showAction(
    BuildContext context,
    WidgetRef ref,
    OrderOperation operation,
    OrderDetails detail,
  ) async {
    if (!_isStillAllowed(ref, operation, detail)) return;
    final sourceCache = ref.read(epochCacheProvider);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => OrderActionDialog(
        orderId: orderId,
        operation: operation,
        submittedScope: capturedScope,
        sourceCache: sourceCache,
        isStillAllowed: () =>
            context.mounted && _isStillAllowed(ref, operation, detail),
      ),
    );
    if (!context.mounted) return;
    if (canReadCaptured() && ref.read(epochCacheProvider).canRead) {
      await ref
          .read(orderDetailsFoundationProvider(orderId).notifier)
          .refresh();
    }
  }
}

class _CustomerOrderDetailsBody extends StatelessWidget {
  const _CustomerOrderDetailsBody({
    required this.detail,
    required this.orderId,
    required this.onCreateReturn,
    required this.onOpenReturn,
    required this.onAction,
    required this.isStillAllowed,
    required this.isReturnCreationStillAllowed,
  });

  final OrderDetails detail;
  final String orderId;
  final ValueChanged<String>? onCreateReturn;
  final ValueChanged<String>? onOpenReturn;
  final Future<void> Function(OrderOperation operation, OrderDetails detail)
  onAction;
  final bool Function(OrderOperation operation, OrderDetails detail)
  isStillAllowed;
  final bool Function(OrderDetails detail) isReturnCreationStillAllowed;

  @override
  Widget build(BuildContext context) {
    ReturnSummary? returnSummary;
    for (final summary in detail.returnSummaries) {
      if (summary.isActive) {
        returnSummary = summary;
        break;
      }
    }
    final returnCreationAllowed =
        detail.order.status == OrderStatus.delivered &&
        detail.capabilities.canOpenReturnCreation &&
        onCreateReturn != null &&
        isReturnCreationStillAllowed(detail);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'Chi tiết đơn hàng',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton(
              tooltip: 'Đóng chi tiết',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          orderId,
          softWrap: true,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Mh07StatusBadge(status: detail.order.status),
        ),
        const SizedBox(height: 12),
        OrderRecipientSection(order: detail.order, buyer: detail.buyer),
        const SizedBox(height: 12),
        OrderItemsSection(items: detail.items),
        const SizedBox(height: 12),
        OrderPaymentSection(order: detail.order, codSummary: detail.codSummary),
        const SizedBox(height: 12),
        OrderTimeline(
          entries: detail.timeline,
          historyComplete: detail.historyComplete,
          title: 'Theo dõi đơn hàng',
        ),
        if (detail.order.status == OrderStatus.pendingConfirmation &&
            detail.capabilities.canCancelCustomer) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: isStillAllowed(OrderOperation.customerCancel, detail)
                ? () => onAction(OrderOperation.customerCancel, detail)
                : null,
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Hủy đơn hàng'),
          ),
        ],
        if (returnSummary != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onOpenReturn == null
                ? null
                : () {
                    Navigator.of(context).pop();
                    onOpenReturn!(returnSummary!.returnId);
                  },
            icon: const Icon(Icons.assignment_return_outlined),
            label: Text(
              onOpenReturn == null
                  ? 'Yêu cầu trả hàng chưa khả dụng'
                  : 'Xem yêu cầu trả hàng',
            ),
          ),
        ] else if (detail.order.status == OrderStatus.delivered) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: returnCreationAllowed
                ? () {
                    if (!isReturnCreationStillAllowed(detail)) return;
                    Navigator.of(context).pop();
                    onCreateReturn!(orderId);
                  }
                : null,
            icon: const Icon(Icons.assignment_return_outlined),
            label: Text(
              returnCreationAllowed
                  ? 'Yêu cầu trả hàng'
                  : 'Yêu cầu trả hàng chưa khả dụng',
            ),
          ),
        ],
      ],
    );
  }
}
