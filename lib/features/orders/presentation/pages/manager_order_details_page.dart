import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/presentation_failure_message.dart';
import '../../../../core/state/foundation_providers.dart';
import '../../../../core/utils/display_formatters.dart';
import '../../../../shared/widgets/async_content.dart';
import '../../../../shared/widgets/feature_access_gate.dart';
import '../../../../shared/widgets/foreground_refresh.dart';
import '../../domain/models/order.dart';
import '../../domain/models/order_details.dart';
import '../../domain/models/order_operation.dart';
import '../view_models/order_providers.dart';
import '../widgets/order_action_dialog.dart';
import '../widgets/order_items_section.dart';
import '../widgets/order_lifecycle_sections.dart';
import '../widgets/order_payment_section.dart';
import '../widgets/order_recipient_section.dart';
import '../widgets/order_status_badge.dart';
import '../widgets/order_timeline.dart';
import '../widgets/order_notification_theme.dart';

/// MH09 — manager order detail.
///
/// The page is a read projection plus dialogs for the three Orders commands.
/// Command transport remains unavailable in Phase 2. Delivery, COD, returns and
/// chat destinations are presented through explicit callbacks so this page
/// cannot invent a route or claim an unavailable external operation worked.
class ManagerOrderDetailsPage extends ConsumerWidget {
  const ManagerOrderDetailsPage({
    required this.orderId,
    this.onOpenCod,
    this.onOpenReturn,
    this.onOpenChat,
    this.onCallRecipient,
    this.enablePolling = true,
    super.key,
  });

  final String orderId;
  final ValueChanged<String>? onOpenCod;
  final ValueChanged<String>? onOpenReturn;
  final ValueChanged<String>? onOpenChat;
  final ValueChanged<String>? onCallRecipient;
  final bool enablePolling;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OrderNotificationTheme(
      child: FeatureAccessGate(
        roles: const {'manager'},
        child: ForegroundRefresh(
          enabled: enablePolling,
          onRefresh: () => ref
              .read(orderDetailsFoundationProvider(orderId).notifier)
              .refresh(),
          canRefresh: () {
            final read = ref
                .read(orderDetailsFoundationProvider(orderId))
                .asData
                ?.value;
            return read?.data != null && !read!.loading && read.failure == null;
          },
          child: _ManagerOrderDetailsContent(
            orderId: orderId,
            onOpenCod: onOpenCod,
            onOpenReturn: onOpenReturn,
            onOpenChat: onOpenChat,
            onCallRecipient: onCallRecipient,
          ),
        ),
      ),
    );
  }
}

class _ManagerOrderDetailsContent extends ConsumerWidget {
  const _ManagerOrderDetailsContent({
    required this.orderId,
    this.onOpenCod,
    this.onOpenReturn,
    this.onOpenChat,
    this.onCallRecipient,
  });

  final String orderId;
  final ValueChanged<String>? onOpenCod;
  final ValueChanged<String>? onOpenReturn;
  final ValueChanged<String>? onOpenChat;
  final ValueChanged<String>? onCallRecipient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = orderDetailsFoundationProvider(orderId);
    final state = ref.watch(provider);
    final read = state.asData?.value;
    final details = read?.data;
    final stateError = state.asError?.error;
    final failure =
        read?.failure ??
        (stateError is AppFailure ? stateError : null) ??
        (stateError == null && state.hasError
            ? const AppFailure(code: AppFailure.unsupportedData)
            : null);
    final isLoading =
        read?.loading == true || (state.isLoading && details == null);
    final isRefreshing = read?.loading == true && details != null;

    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop() ? const BackButton() : null,
        title: const Text('Chi tiết đơn hàng'),
        actions: [
          IconButton(
            tooltip: 'Tải lại',
            onPressed: isRefreshing
                ? null
                : () => ref.read(provider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      bottomNavigationBar:
          details == null ||
              !(details.capabilities.canConfirm ||
                  details.capabilities.canReject ||
                  details.capabilities.canCancelExceptional) ||
              failure?.code == AppFailure.unauthenticated ||
              failure?.code == AppFailure.forbiddenOrUnavailable
          ? null
          : SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .35,
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    child: _OrderActionFooter(
                      details: details,
                      orderCommandsOnly: true,
                      onShowAction: (operation) =>
                          _showActionDialog(context, ref, operation),
                      isStillAllowed: (operation) =>
                          _isStillAllowed(ref, operation),
                    ),
                  ),
                ),
              ),
            ),
      body: SafeArea(
        child: AsyncContent(
          hasData: details != null,
          isInitialLoading: isLoading,
          isRefreshing: isRefreshing,
          failure: failure,
          errorMessage: failure == null ? null : failureMessage(failure),
          isStale: read?.stale == true,
          onRetry: () => ref.read(provider.notifier).refresh(),
          child: details == null
              ? const SizedBox.shrink()
              : _DetailScrollView(
                  details: details,
                  onOpenCod: onOpenCod,
                  onOpenReturn: onOpenReturn,
                  onOpenChat: onOpenChat,
                  onCallRecipient: onCallRecipient,
                  onShowAction: (operation) =>
                      _showActionDialog(context, ref, operation),
                  isStillAllowed: (operation) =>
                      _isStillAllowed(ref, operation),
                  onRefresh: () => ref.read(provider.notifier).refresh(),
                ),
        ),
      ),
    );
  }

  Future<void> _showActionDialog(
    BuildContext context,
    WidgetRef ref,
    OrderOperation operation,
  ) async {
    final submittedScope = ref.read(featureSessionScopeProvider);
    await showDialog<void>(
      context: context,
      builder: (_) => OrderActionDialog(
        orderId: orderId,
        operation: operation,
        submittedScope: submittedScope,
        isStillAllowed: () => _isStillAllowed(ref, operation),
      ),
    );
  }

  bool _isStillAllowed(WidgetRef ref, OrderOperation operation) {
    final scope = ref.read(featureSessionScopeProvider);
    if (scope.role != 'manager' || !ref.read(epochCacheProvider).canRead) {
      return false;
    }
    final state = ref.read(orderDetailsFoundationProvider(orderId));
    final read = state.asData?.value;
    final details = read?.data;
    if (read == null || details == null || !read.isFresh) return false;
    return switch (operation) {
      OrderOperation.confirm => details.capabilities.canConfirm,
      OrderOperation.reject => details.capabilities.canReject,
      OrderOperation.managerCancel => details.capabilities.canCancelExceptional,
      _ => false,
    };
  }
}

class _DetailScrollView extends StatelessWidget {
  const _DetailScrollView({
    required this.details,
    required this.onShowAction,
    required this.isStillAllowed,
    required this.onRefresh,
    this.onOpenCod,
    this.onOpenReturn,
    this.onOpenChat,
    this.onCallRecipient,
  });

  final OrderDetails details;
  final void Function(OrderOperation operation) onShowAction;
  final bool Function(OrderOperation operation) isStillAllowed;
  final Future<void> Function() onRefresh;
  final ValueChanged<String>? onOpenCod;
  final ValueChanged<String>? onOpenReturn;
  final ValueChanged<String>? onOpenChat;
  final ValueChanged<String>? onCallRecipient;

  @override
  Widget build(BuildContext context) {
    final order = details.order;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OrderHeader(order: order),
            const SizedBox(height: 12),
            OrderRecipientSection(order: order, buyer: details.buyer),
            const SizedBox(height: 12),
            OrderItemsSection(items: details.items),
            const SizedBox(height: 12),
            OrderPaymentSection(order: order, codSummary: details.codSummary),
            const SizedBox(height: 12),
            OrderLifecycleSections(
              deliverySummary: details.deliverySummary,
              codSummary: details.codSummary,
              returnSummaries: details.returnSummaries,
              onOpenCod: onOpenCod,
              onOpenReturn: onOpenReturn,
            ),
            const SizedBox(height: 12),
            OrderTimeline(
              entries: details.timeline,
              historyComplete: details.historyComplete,
            ),
            const SizedBox(height: 12),
            _ContactActions(
              customerId: order.customerId,
              recipientPhone: order.recipientPhone,
              onOpenChat: onOpenChat,
              onCallRecipient: onCallRecipient,
            ),
            const SizedBox(height: 12),
            _OrderActionFooter(
              details: details,
              externalActionsOnly: true,
              onShowAction: onShowAction,
              isStillAllowed: isStillAllowed,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _OrderHeader extends StatelessWidget {
  const _OrderHeader({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Đơn hàng ${order.id}',
              softWrap: true,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OrderStatusBadge(status: order.status),
                Text('Đặt lúc ${formatHanoiDateTime(order.placedAt)}'),
              ],
            ),
            if (order.deliveryAttemptCount > 0) ...[
              const SizedBox(height: 8),
              Text('Số lần giao đã ghi nhận: ${order.deliveryAttemptCount}/2'),
            ],
          ],
        ),
      ),
    );
  }
}

class _ContactActions extends StatelessWidget {
  const _ContactActions({
    required this.customerId,
    required this.recipientPhone,
    this.onOpenChat,
    this.onCallRecipient,
  });

  final String customerId;
  final String recipientPhone;
  final ValueChanged<String>? onOpenChat;
  final ValueChanged<String>? onCallRecipient;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Liên hệ', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CallbackAction(
                  label: 'Gọi người nhận',
                  unavailableMessage: 'Tính năng gọi chưa khả dụng',
                  onPressed: onCallRecipient == null
                      ? null
                      : () => onCallRecipient!(recipientPhone),
                ),
                _CallbackAction(
                  label: 'Mở trao đổi với khách',
                  unavailableMessage: 'Điều hướng trò chuyện chưa khả dụng',
                  onPressed: onOpenChat == null
                      ? null
                      : () => onOpenChat!(customerId),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderActionFooter extends StatelessWidget {
  const _OrderActionFooter({
    required this.details,
    required this.onShowAction,
    required this.isStillAllowed,
    this.orderCommandsOnly = false,
    this.externalActionsOnly = false,
  });

  final OrderDetails details;
  final void Function(OrderOperation operation) onShowAction;
  final bool Function(OrderOperation operation) isStillAllowed;
  final bool orderCommandsOnly;
  final bool externalActionsOnly;

  @override
  Widget build(BuildContext context) {
    final capabilities = details.capabilities;
    final orderActions = <Widget>[];
    if (!externalActionsOnly && capabilities.canConfirm) {
      orderActions.add(
        FilledButton.icon(
          onPressed: isStillAllowed(OrderOperation.confirm)
              ? () => onShowAction(OrderOperation.confirm)
              : null,
          icon: const Icon(Icons.check),
          label: const Text('Xác nhận đơn'),
        ),
      );
    }
    if (!externalActionsOnly && capabilities.canReject) {
      orderActions.add(
        OutlinedButton.icon(
          onPressed: isStillAllowed(OrderOperation.reject)
              ? () => onShowAction(OrderOperation.reject)
              : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          icon: const Icon(Icons.block),
          label: const Text('Từ chối đơn'),
        ),
      );
    }
    if (!externalActionsOnly && capabilities.canCancelExceptional) {
      orderActions.add(
        OutlinedButton.icon(
          onPressed: isStillAllowed(OrderOperation.managerCancel)
              ? () => onShowAction(OrderOperation.managerCancel)
              : null,
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('Hủy ngoại lệ'),
        ),
      );
    }

    final externalActions = <Widget>[];
    if (!orderCommandsOnly && capabilities.canAssign) {
      externalActions.add(
        _UnavailableActionButton(
          label: 'Phân công',
          reason: 'Phân công chưa khả dụng do dịch vụ giao hàng chưa sẵn sàng',
        ),
      );
    }
    if (!orderCommandsOnly && capabilities.canReassign) {
      externalActions.add(
        _UnavailableActionButton(
          label: 'Phân công lại',
          reason:
              'Phân công lại chưa khả dụng do dịch vụ giao hàng chưa sẵn sàng',
        ),
      );
    }
    if (!orderCommandsOnly && capabilities.canArrangeSecondAttempt) {
      externalActions.add(
        _UnavailableActionButton(
          label: 'Giao lần hai',
          reason:
              'Giao lần hai chưa khả dụng do dịch vụ giao hàng chưa sẵn sàng',
        ),
      );
    }
    if (!orderCommandsOnly && capabilities.canRequestEarlyReturn) {
      externalActions.add(
        _UnavailableActionButton(
          label: 'Hoàn hàng sớm',
          reason:
              'Hoàn hàng sớm chưa khả dụng do dịch vụ giao hàng chưa sẵn sàng',
        ),
      );
    }
    if (!orderCommandsOnly && capabilities.canReceiveUndelivered) {
      externalActions.add(
        _UnavailableActionButton(
          label: 'Nhận và kiểm tra hàng',
          reason: 'Nhận và kiểm tra hàng chưa khả dụng do quy trình kho chưa sẵn sàng',
        ),
      );
    }

    if (orderActions.isEmpty && externalActions.isEmpty) {
      return const SizedBox.shrink();
    }
    if (orderCommandsOnly) {
      return Container(
        padding: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Wrap(spacing: 8, runSpacing: 8, children: orderActions),
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Thao tác quản lý',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (orderActions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: orderActions),
            ],
            if (externalActions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Các thao tác sau chưa khả dụng cho đến khi dịch vụ giao hàng và kho được tích hợp.',
                softWrap: true,
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: externalActions),
            ],
          ],
        ),
      ),
    );
  }
}

class _CallbackAction extends StatelessWidget {
  const _CallbackAction({
    required this.label,
    required this.unavailableMessage,
    required this.onPressed,
  });

  final String label;
  final String unavailableMessage;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (onPressed != null) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.open_in_new),
        label: Text(label),
      );
    }
    return Semantics(
      container: true,
      label: unavailableMessage,
      child: Text(unavailableMessage, softWrap: true),
    );
  }
}

class _UnavailableActionButton extends StatelessWidget {
  const _UnavailableActionButton({required this.label, required this.reason});

  final String label;
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: reason,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton(onPressed: null, child: Text(label)),
          const SizedBox(height: 2),
          Text(reason, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
