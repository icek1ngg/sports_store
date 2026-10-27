import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/presentation_failure_message.dart';
import '../../../../core/state/read_snapshot.dart';
import '../../../../shared/widgets/async_content.dart';
import '../../domain/models/order_page.dart';
import '../../domain/models/order_status.dart';
import '../../domain/models/order_summary.dart';
import 'order_card.dart';

/// Converts the foundation provider's AsyncValue to the presentation
/// snapshot. The foundation deliberately keeps loading/error inside a
/// ReadSnapshot, but a provider can still be AsyncLoading while its notifier
/// is being constructed.
ReadSnapshot<OrderPage> orderPageSnapshot(
  AsyncValue<ReadSnapshot<OrderPage>> value,
) {
  return value.value ?? const ReadSnapshot(loading: true);
}

typedef OrderFeedActionPredicate = bool Function(
  OrderSummary summary,
  OrderOperation operation,
);
typedef OrderFeedReturnPredicate = bool Function(OrderSummary summary);

/// Shared paginated order list surface for MH07 and MH08.
///
/// The page owns query generations, cursor history and canonical snapshots;
/// this widget only renders those values. Keeping the cursor state above the
/// feed lets the same foundation provider family remain the sole read cache.
class OrderFeed extends StatelessWidget {
  const OrderFeed({
    required this.snapshot,
    required this.orders,
    this.onRefresh,
    this.onRetry,
    this.onLoadMore,
    this.onRetryMore,
    this.loadingMore = false,
    this.moreFailure,
    this.canLoadMore = false,
    this.showManagerContext = false,
    this.onOpenOrder,
    this.onCustomerCancel,
    this.onConfirm,
    this.onReject,
    this.onCreateReturn,
    this.onOpenReturn,
    this.actionPredicate,
    this.returnCreationPredicate,
    this.mutationOrderIds = const <String>{},
    this.emptyMessage = 'Chưa có dữ liệu',
    this.emptyActionLabel,
    this.onEmptyAction,
    this.scrollController,
    this.itemBuilder,
    this.listPadding,
    this.listFooter,
    super.key,
  });

  final ReadSnapshot<OrderPage> snapshot;
  final List<OrderSummary> orders;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onRetry;
  final VoidCallback? onLoadMore;
  final VoidCallback? onRetryMore;
  final bool loadingMore;
  final AppFailure? moreFailure;
  final bool canLoadMore;
  final bool showManagerContext;
  final ValueChanged<String>? onOpenOrder;
  final ValueChanged<String>? onCustomerCancel;
  final ValueChanged<String>? onConfirm;
  final ValueChanged<String>? onReject;
  final ValueChanged<String>? onCreateReturn;
  final ValueChanged<String>? onOpenReturn;
  final OrderFeedActionPredicate? actionPredicate;
  final OrderFeedReturnPredicate? returnCreationPredicate;
  final Set<String> mutationOrderIds;
  final String emptyMessage;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final ScrollController? scrollController;
  final Widget Function(BuildContext, OrderSummary)? itemBuilder;
  final EdgeInsets? listPadding;
  final Widget? listFooter;

  @override
  Widget build(BuildContext context) {
    final hasData = snapshot.data != null || orders.isNotEmpty;
    final acceptedEmpty = snapshot.data != null && orders.isEmpty;
    final isRefreshing = snapshot.loading && hasData;
    final isInitialLoading = snapshot.isInitialLoading && !hasData;

    return AsyncContent(
      hasData: hasData,
      isInitialLoading: isInitialLoading,
      isRefreshing: isRefreshing,
      isEmpty: acceptedEmpty,
      failure: snapshot.failure,
      errorMessage: snapshot.failure == null
          ? null
          : failureMessage(snapshot.failure),
      isStale: snapshot.stale,
      onRetry: onRetry,
      emptyMessage: emptyMessage,
      emptyActionLabel: emptyActionLabel,
      onEmptyAction: onEmptyAction,
      child: _OrderFeedList(
        orders: orders,
        showManagerContext: showManagerContext,
        onRefresh: onRefresh,
        onLoadMore: onLoadMore,
        onRetryMore: onRetryMore,
        loadingMore: loadingMore,
        moreFailure: moreFailure,
        canLoadMore: canLoadMore,
        onOpenOrder: onOpenOrder,
        onCustomerCancel: onCustomerCancel,
        onConfirm: onConfirm,
        onReject: onReject,
        onCreateReturn: onCreateReturn,
        onOpenReturn: onOpenReturn,
        actionPredicate: actionPredicate,
        returnCreationPredicate: returnCreationPredicate,
        mutationOrderIds: mutationOrderIds,
        isStale: snapshot.stale,
        scrollController: scrollController,
        itemBuilder: itemBuilder,
        listPadding: listPadding,
        listFooter: listFooter,
      ),
    );
  }
}

class _OrderFeedList extends StatelessWidget {
  const _OrderFeedList({
    required this.orders,
    required this.showManagerContext,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.loadingMore,
    required this.moreFailure,
    required this.canLoadMore,
    required this.onOpenOrder,
    required this.onCustomerCancel,
    required this.onConfirm,
    required this.onReject,
    required this.onCreateReturn,
    required this.onOpenReturn,
    required this.actionPredicate,
    required this.returnCreationPredicate,
    required this.mutationOrderIds,
    required this.isStale,
    required this.scrollController,
    required this.itemBuilder,
    required this.listPadding,
    required this.listFooter,
  });

  final List<OrderSummary> orders;
  final bool showManagerContext;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onLoadMore;
  final VoidCallback? onRetryMore;
  final bool loadingMore;
  final AppFailure? moreFailure;
  final bool canLoadMore;
  final ValueChanged<String>? onOpenOrder;
  final ValueChanged<String>? onCustomerCancel;
  final ValueChanged<String>? onConfirm;
  final ValueChanged<String>? onReject;
  final ValueChanged<String>? onCreateReturn;
  final ValueChanged<String>? onOpenReturn;
  final OrderFeedActionPredicate? actionPredicate;
  final OrderFeedReturnPredicate? returnCreationPredicate;
  final Set<String> mutationOrderIds;
  final bool isStale;
  final ScrollController? scrollController;
  final Widget Function(BuildContext, OrderSummary)? itemBuilder;
  final EdgeInsets? listPadding;
  final Widget? listFooter;

  @override
  Widget build(BuildContext context) {
    final footerCount = loadingMore || moreFailure != null || canLoadMore
        ? 1
        : 0;
    final itemCount =
        orders.length + footerCount + (listFooter == null ? 0 : 1);
    final list = ListView.builder(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: listPadding ?? const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (listFooter != null && index == itemCount - 1) return listFooter!;
        if (index >= orders.length) return _buildFooter(context);
        final summary = orders[index];
        return Padding(
          padding: EdgeInsets.only(bottom: itemBuilder == null ? 12 : 16),
          child:
              itemBuilder?.call(context, summary) ??
              _OrderFeedItem(
                summary: summary,
                showManagerContext: showManagerContext,
                isStale: isStale,
                mutationInProgress: mutationOrderIds.contains(summary.order.id),
                onOpenOrder: onOpenOrder,
                onCustomerCancel: onCustomerCancel,
                onConfirm: onConfirm,
                onReject: onReject,
                onCreateReturn: onCreateReturn,
                onOpenReturn: onOpenReturn,
                actionPredicate: actionPredicate,
                returnCreationPredicate: returnCreationPredicate,
              ),
        );
      },
    );

    if (onRefresh == null) return list;
    return RefreshIndicator(onRefresh: onRefresh!, child: list);
  }

  Widget _buildFooter(BuildContext context) {
    if (loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (moreFailure != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
        child: Column(
          children: [
            Text(failureMessage(moreFailure), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onRetryMore,
              child: const Text('Tải lại trang tiếp theo'),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      child: OutlinedButton(
        onPressed: onLoadMore,
        child: const Text('Tải thêm đơn hàng'),
      ),
    );
  }
}

class _OrderFeedItem extends StatelessWidget {
  const _OrderFeedItem({
    required this.summary,
    required this.showManagerContext,
    required this.isStale,
    required this.mutationInProgress,
    required this.onOpenOrder,
    required this.onCustomerCancel,
    required this.onConfirm,
    required this.onReject,
    required this.onCreateReturn,
    required this.onOpenReturn,
    required this.actionPredicate,
    required this.returnCreationPredicate,
  });

  final OrderSummary summary;
  final bool showManagerContext;
  final bool isStale;
  final bool mutationInProgress;
  final ValueChanged<String>? onOpenOrder;
  final ValueChanged<String>? onCustomerCancel;
  final ValueChanged<String>? onConfirm;
  final ValueChanged<String>? onReject;
  final ValueChanged<String>? onCreateReturn;
  final ValueChanged<String>? onOpenReturn;
  final OrderFeedActionPredicate? actionPredicate;
  final OrderFeedReturnPredicate? returnCreationPredicate;

  bool _allowed(OrderOperation operation, bool fallback) {
    if (isStale || mutationInProgress) return false;
    return actionPredicate?.call(summary, operation) ?? fallback;
  }

  @override
  Widget build(BuildContext context) {
    final id = summary.order.id;
    final actions = showManagerContext
        ? _managerActions(context, id)
        : _customerActions(context, id);
    final actionArea = actions.isEmpty
        ? null
        : Wrap(spacing: 8, runSpacing: 8, children: actions);
    final card = showManagerContext
        ? ManagerOrderCard(
            summary: summary,
            isStale: isStale,
            mutationInProgress: mutationInProgress,
            actions: actionArea,
            onTap: onOpenOrder == null ? null : () => onOpenOrder!(id),
          )
        : CustomerOrderCard(
            summary: summary,
            isStale: isStale,
            mutationInProgress: mutationInProgress,
            actions: actionArea,
            onTap: onOpenOrder == null ? null : () => onOpenOrder!(id),
          );

    return card;
  }

  List<Widget> _customerActions(BuildContext context, String id) {
    final actions = <Widget>[];
    actions.add(
      OutlinedButton(
        onPressed: mutationInProgress || onOpenOrder == null
            ? null
            : () => onOpenOrder!(id),
        child: const Text('Xem chi tiết'),
      ),
    );
    if (summary.order.status == OrderStatus.pendingConfirmation &&
        summary.capabilities.canCancelCustomer) {
      final enabled = _allowed(
        OrderOperation.customerCancel,
        summary.capabilities.canCancelCustomer,
      );
      actions.add(
        OutlinedButton.icon(
          onPressed: enabled && onCustomerCancel != null
              ? () => onCustomerCancel!(id)
              : null,
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('Hủy đơn'),
        ),
      );
    }

    final returnSummary = summary.returnSummary;
    if (returnSummary?.isActive == true) {
      final returnId = returnSummary!.returnId;
      actions.add(
        OutlinedButton.icon(
          onPressed: onOpenReturn == null
              ? null
              : () => onOpenReturn!(returnId),
          icon: const Icon(Icons.assignment_return_outlined),
          label: Text(
            onOpenReturn == null
                ? 'Yêu cầu trả hàng chưa khả dụng'
                : 'Xem yêu cầu trả hàng',
          ),
        ),
      );
    } else if (summary.order.status == OrderStatus.delivered) {
      final canCreate = isStale || mutationInProgress
          ? false
          : returnCreationPredicate?.call(summary) ??
                summary.capabilities.canOpenReturnCreation;
      actions.add(
        OutlinedButton.icon(
          onPressed: canCreate && onCreateReturn != null
              ? () => onCreateReturn!(id)
              : null,
          icon: const Icon(Icons.assignment_return_outlined),
          label: Text(
            canCreate && onCreateReturn != null
                ? 'Yêu cầu trả hàng'
                : 'Yêu cầu trả hàng chưa khả dụng',
          ),
        ),
      );
    }
    return actions;
  }

  List<Widget> _managerActions(BuildContext context, String id) {
    final actions = <Widget>[];
    if (summary.order.status == OrderStatus.pendingConfirmation) {
      final canConfirm = _allowed(
        OrderOperation.confirm,
        summary.capabilities.canConfirm,
      );
      final canReject = _allowed(
        OrderOperation.reject,
        summary.capabilities.canReject,
      );
      actions.add(
        FilledButton.icon(
          onPressed: canConfirm && onConfirm != null
              ? () => onConfirm!(id)
              : null,
          icon: const Icon(Icons.check),
          label: const Text('Xác nhận'),
        ),
      );
      actions.add(
        OutlinedButton.icon(
          onPressed: canReject && onReject != null ? () => onReject!(id) : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          icon: const Icon(Icons.block_outlined),
          label: const Text('Từ chối'),
        ),
      );
    }

    // MH08 is allowed to render a safe unavailable action when the central
    // router has not supplied its detail callback yet.
    actions.add(
      TextButton.icon(
        onPressed: onOpenOrder == null ? null : () => onOpenOrder!(id),
        icon: const Icon(Icons.open_in_new),
        label: Text(
          onOpenOrder == null ? 'Chi tiết chưa khả dụng' : 'Xem chi tiết',
        ),
      ),
    );
    return actions;
  }
}
