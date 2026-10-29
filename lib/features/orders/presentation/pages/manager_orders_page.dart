import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/state/foundation_providers.dart';
import '../../../../core/state/read_snapshot.dart';
import '../../../../shared/widgets/feature_access_gate.dart';
import '../../../../shared/widgets/foreground_refresh.dart';
import '../../domain/models/order_page.dart';
import '../../domain/models/order_query.dart';
import '../../domain/models/order_status.dart';
import '../../domain/models/order_summary.dart';
import '../view_models/order_providers.dart';
import '../view_models/mh08/mh08_feed_coordinator.dart';
import '../view_models/mh08/mh08_query_coordinator.dart';
import '../widgets/order_action_dialog.dart';
import '../widgets/order_feed.dart';
import '../widgets/order_notification_theme.dart';
import 'mh08/mh08_read_subscriptions.dart';
import '../widgets/mh08/mh08_list_controls.dart';
import '../widgets/mh08/mh08_order_card.dart';
import '../widgets/mh08/mh08_page_layout.dart';

/// MH08 — manager order list and operational counts.
///
/// Opening MH09 is supplied by the central router owner. Until that callback
/// exists the feed shows a disabled, explicit unavailable detail action.
class ManagerOrdersPage extends StatelessWidget {
  const ManagerOrdersPage({
    this.onOpenOrder,
    this.enablePolling = true,
    super.key,
  });

  final ValueChanged<String>? onOpenOrder;
  final bool enablePolling;

  @override
  Widget build(BuildContext context) {
    return OrderNotificationTheme(
      child: FeatureAccessGate(
        roles: const {'manager'},
        child: _ManagerOrdersBody(
          onOpenOrder: onOpenOrder,
          enablePolling: enablePolling,
        ),
      ),
    );
  }
}

class _ManagerOrdersBody extends ConsumerStatefulWidget {
  const _ManagerOrdersBody({
    required this.onOpenOrder,
    required this.enablePolling,
  });

  final ValueChanged<String>? onOpenOrder;
  final bool enablePolling;

  @override
  ConsumerState<_ManagerOrdersBody> createState() => _ManagerOrdersBodyState();
}

class _ManagerOrdersBodyState extends ConsumerState<_ManagerOrdersBody> {
  final _scrollController = ScrollController();
  final _query = Mh08QueryCoordinator();
  final _feed = Mh08FeedCoordinator();
  bool _active = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void deactivate() {
    _active = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
  }

  @override
  void dispose() {
    _active = false;
    _query.dispose();
    _scrollController
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = watchMh08Reads(
      ref,
      feed: _feed,
      query: _query.query,
      canAccept: () => mounted && _active,
      onSessionChanged: () {
        _query.cancelPending();
        setState(() => _feed.reset(sessionChanged: true));
      },
      onCanonical: _consumeCanonical,
      onNext: _consumeNext,
    );
    final effectiveSnapshot = _feed.effectiveSnapshot(snapshot);
    final visibleRows = _feed.visibleRows(snapshot);
    final page = _feed.visiblePage(snapshot);

    return Mh08PageLayout(
      onRefresh: _canRead ? () => unawaited(_refreshCanonical()) : null,
      controls: Mh08ListControls(
        searchValue: _query.value,
        searchError: _query.error,
        onSearchChanged: _onSearchChanged,
        onClear: _clearSearch,
        onStatusSelected: _onStatusSelected,
        page: page,
        selectedStatus: _query.query.statuses.singleOrNull,
      ),
      feed: ForegroundRefresh(
        enabled: widget.enablePolling,
        onRefresh: () => unawaited(_refreshCanonical()),
        canRefresh: () =>
            _canRead &&
            effectiveSnapshot.data != null &&
            !effectiveSnapshot.loading &&
            effectiveSnapshot.failure == null,
        child: OrderFeed(
          snapshot: effectiveSnapshot,
          orders: visibleRows,
          scrollController: _scrollController,
          onRefresh: _refreshCanonical,
          onRetry: () => unawaited(_refreshCanonical()),
          onLoadMore: _requestLoadMore,
          onRetryMore: () => _requestLoadMore(force: true),
          loadingMore: _feed.loadingMore,
          moreFailure: _feed.moreFailure,
          canLoadMore: _feed.canLoadMore,
          emptyMessage: _query.emptyMessage,
          itemBuilder: (_, summary) => Mh08OrderCard(
            summary: summary,
            isFresh: _feed.canonicalFresh && effectiveSnapshot.isFresh,
            showDecisionActions:
                summary.order.status == OrderStatus.pendingConfirmation,
            enabled: _canRead,
            canConfirm: _isActionAllowed(summary, OrderOperation.confirm),
            canReject: _isActionAllowed(summary, OrderOperation.reject),
            onConfirm: () =>
                _showActionDialog(summary.order.id, OrderOperation.confirm),
            onReject: () =>
                _showActionDialog(summary.order.id, OrderOperation.reject),
            onOpenOrder: widget.onOpenOrder == null
                ? null
                : () => _openOrder(summary.order.id),
          ),
        ),
      ),
    );
  }

  bool get _canRead {
    if (!mounted || !_active) return false;
    final scope = ref.read(featureSessionScopeProvider);
    return scope.role == 'manager' &&
        scope.canReadPrivateData &&
        ref.read(epochCacheProvider).canRead;
  }

  void _onSearchChanged(String value) {
    setState(() => _query.edit(value, _setQuery));
  }

  void _clearSearch() {
    final query = _query.clear();
    _setQuery(query);
    setState(() {});
  }

  void _onStatusSelected(OrderStatus? status) =>
      _setQuery(_query.select(status));

  void _setQuery(OrderQuery query) {
    if (!mounted || !_active || !_query.apply(query)) return;
    setState(() => _feed.reset());
  }

  void _consumeCanonical(int generation, ReadSnapshot<OrderPage> snapshot) {
    if (!mounted || !_active) return;
    if (_feed.consumeCanonical(generation, snapshot)) {
      setState(() {});
    }
  }

  void _consumeNext(
    int generation,
    String cursor,
    ReadSnapshot<OrderPage> snapshot,
  ) {
    if (!mounted || !_active) return;
    final result = _feed.consumeNext(generation, cursor, snapshot);
    if (result != Mh08NextResult.ignored) {
      setState(() {});
    }
    if (result == Mh08NextResult.refreshHead) {
      unawaited(_refreshCanonical());
    }
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients ||
        _scrollController.position.maxScrollExtent <= 0) {
      return;
    }
    if (_scrollController.position.extentAfter < 360) {
      _requestLoadMore();
    }
  }

  void _requestLoadMore({bool force = false}) {
    if (!_feed.beginMore(canRead: _canRead, force: force)) return;
    setState(() {});
    if (force) {
      refreshMh08NextAfterBuild(
        ref,
        feed: _feed,
        query: _query.query,
        canAccept: () => _canRead,
      );
    }
  }

  Future<void> _refreshCanonical() async {
    if (!_canRead) return;
    setState(() => _feed.beginRefresh());
    await ref
        .read(orderListFoundationProvider(_query.query).notifier)
        .refresh();
  }

  bool _isActionAllowed(OrderSummary summary, OrderOperation operation) {
    if (!_canRead || !_feed.canonicalFresh || _feed.canonicalPage == null) {
      return false;
    }
    if (summary.order.status != OrderStatus.pendingConfirmation) return false;
    return switch (operation) {
      OrderOperation.confirm => summary.capabilities.canConfirm,
      OrderOperation.reject => summary.capabilities.canReject,
      _ => false,
    };
  }

  void _openOrder(String id) {
    if (_canRead && _feed.findSummary(id) != null) widget.onOpenOrder?.call(id);
  }

  Future<void> _showActionDialog(String id, OrderOperation operation) async {
    if (!_canRead) return;
    final summary = _feed.findSummary(id);
    if (summary == null || !_isActionAllowed(summary, operation)) return;
    final scope = ref.read(featureSessionScopeProvider);
    final cache = ref.read(epochCacheProvider);
    await showDialog<void>(
      context: context,
      builder: (_) => OrderActionDialog(
        orderId: id,
        operation: operation,
        submittedScope: scope,
        sourceCache: cache,
        isStillAllowed: () {
          if (!_canRead || ref.read(featureSessionScopeProvider) != scope) {
            return false;
          }
          final current = _feed.findSummary(id);
          return current != null && _isActionAllowed(current, operation);
        },
      ),
    );
  }
}
