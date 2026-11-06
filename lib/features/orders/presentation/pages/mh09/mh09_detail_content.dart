import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/errors/app_failure.dart';
import '../../../../../core/errors/presentation_failure_message.dart';
import '../../../../../core/state/epoch_cache.dart';
import '../../../../../core/state/foundation_providers.dart';
import '../../../../../core/state/session_scope.dart';
import '../../../../../shared/widgets/async_content.dart';
import '../../../../../shared/widgets/foreground_refresh.dart';
import '../../../domain/models/order_details.dart';
import '../../../domain/models/order_operation.dart';
import '../../view_models/order_providers.dart';
import '../../widgets/mh09/mh09_header.dart';
import '../../widgets/mh09/mh09_action_footer.dart';
import '../../widgets/order_action_dialog.dart';
import 'mh09_detail_body.dart';
import 'mh09_page_layout.dart';

/// Canonical read and interaction owner; presentation widgets never receive ref.
class Mh09DetailContent extends ConsumerStatefulWidget {
  const Mh09DetailContent({
    required this.orderId,
    required this.enablePolling,
    this.onOpenCod,
    this.onOpenReturn,
    this.onOpenChat,
    this.onCallRecipient,
    super.key,
  });
  final String orderId;
  final bool enablePolling;
  final ValueChanged<String>? onOpenCod,
      onOpenReturn,
      onOpenChat,
      onCallRecipient;

  @override
  ConsumerState<Mh09DetailContent> createState() => _Mh09DetailContentState();
}

class _Mh09DetailContentState extends ConsumerState<Mh09DetailContent> {
  bool _active = true;
  bool _dialogOpen = false;
  int _generation = 0;
  ModalRoute<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void didUpdateWidget(covariant Mh09DetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId != widget.orderId) _revoke();
  }

  void _revoke() {
    _generation++;
    _dialogOpen = false;
  }

  @override
  void deactivate() {
    _active = false;
    _revoke();
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
    _revoke();
    super.dispose();
  }

  bool _owns(int ticket) =>
      _active && mounted && ticket == _generation && _route?.isActive != false;

  bool _authorized(int ticket, SessionScope scope, EpochCache cache) =>
      _owns(ticket) &&
      scope.role == 'manager' &&
      ref.read(featureSessionScopeProvider) == scope &&
      identical(ref.read(epochCacheProvider), cache) &&
      cache.canRead;

  OrderDetails? _current(int ticket, SessionScope scope, EpochCache cache) {
    if (!_authorized(ticket, scope, cache)) return null;
    final read = ref
        .read(orderDetailsFoundationProvider(widget.orderId))
        .asData
        ?.value;
    if (read?.isFresh != true || read!.data?.order.id != widget.orderId) {
      return null;
    }
    return read.data;
  }

  bool _allowed(
    OrderOperation operation,
    int ticket,
    SessionScope scope,
    EpochCache cache,
  ) {
    final details = _current(ticket, scope, cache);
    if (details == null) return false;
    return switch (operation) {
      OrderOperation.confirm => details.capabilities.canConfirm,
      OrderOperation.reject => details.capabilities.canReject,
      OrderOperation.managerCancel => details.capabilities.canCancelExceptional,
      _ => false,
    };
  }

  Future<void> _refresh(int ticket, SessionScope scope, EpochCache cache) {
    if (!_authorized(ticket, scope, cache)) return Future.value();
    final provider = orderDetailsFoundationProvider(widget.orderId);
    final state = ref.read(provider);
    if (state.isLoading || state.asData?.value.loading == true) {
      return Future.value();
    }
    return ref.read(provider.notifier).refresh();
  }

  void _forward(
    int ticket,
    SessionScope scope,
    EpochCache cache,
    void Function(OrderDetails) callback,
  ) {
    final current = _current(ticket, scope, cache);
    if (current != null && _route?.isCurrent != false) callback(current);
  }

  Future<void> _showAction(
    OrderOperation operation,
    int ticket,
    SessionScope scope,
    EpochCache cache,
  ) async {
    if (_dialogOpen ||
        _route?.isCurrent == false ||
        !_allowed(operation, ticket, scope, cache)) {
      return;
    }
    final sourceOrderId = widget.orderId;
    setState(() => _dialogOpen = true);
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => OrderActionDialog(
          orderId: sourceOrderId,
          operation: operation,
          submittedScope: scope,
          sourceCache: cache,
          isStillAllowed: () => _allowed(operation, ticket, scope, cache),
        ),
      );
    } finally {
      if (_owns(ticket)) setState(() => _dialogOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticket = _generation;
    final scope = ref.watch(featureSessionScopeProvider);
    final cache = ref.watch(epochCacheProvider);
    final state = ref.watch(orderDetailsFoundationProvider(widget.orderId));
    final read = state.asData?.value;
    final details = read?.data;
    final stateError = state.asError?.error;
    final failure =
        read?.failure ??
        (stateError is AppFailure ? stateError : null) ??
        (stateError == null && state.hasError
            ? const AppFailure(code: AppFailure.unsupportedData)
            : null);
    final loading =
        read?.loading == true || (state.isLoading && details == null);
    final fresh = _current(ticket, scope, cache) != null;
    Future<void> refresh() => _refresh(ticket, scope, cache);
    void action(OrderOperation operation) =>
        _showAction(operation, ticket, scope, cache);
    final hasActions =
        details != null &&
        (details.capabilities.canConfirm ||
            details.capabilities.canReject ||
            details.capabilities.canCancelExceptional);

    return ForegroundRefresh(
      enabled: widget.enablePolling,
      onRefresh: refresh,
      canRefresh: () => _current(ticket, scope, cache) != null,
      child: Mh09PageLayout(
        footer: !hasActions
            ? null
            : Mh09ActionFooter(
                capabilities: details.capabilities,
                isActionStateFresh: fresh,
                canActInCurrentScope: _authorized(ticket, scope, cache),
                isBusy: loading || _dialogOpen,
                onAction: action,
              ),
        header: Mh09Header(
          canPop: Navigator.of(context).canPop(),
          isRefreshing: loading && details != null,
          onBack: () {
            if (_authorized(ticket, scope, cache) &&
                _route?.isCurrent != false) {
              Navigator.of(context).maybePop();
            }
          },
          onRefresh: loading ? null : refresh,
        ),
        body: AsyncContent(
          hasData: details != null,
          isInitialLoading: loading,
          isRefreshing: loading && details != null,
          failure: failure,
          errorMessage: failure == null ? null : failureMessage(failure),
          isStale: read?.stale == true,
          onRetry: refresh,
          child: details == null
              ? const SizedBox.shrink()
              : Mh09DetailBody(
                  details: details,
                  onRefresh: refresh,
                  contactEnabled: fresh,
                  onCall: widget.onCallRecipient == null
                      ? null
                      : () => _forward(
                          ticket,
                          scope,
                          cache,
                          (d) => widget.onCallRecipient?.call(
                            d.order.recipientPhone,
                          ),
                        ),
                  onChat: widget.onOpenChat == null
                      ? null
                      : () => _forward(
                          ticket,
                          scope,
                          cache,
                          (d) => widget.onOpenChat?.call(d.order.customerId),
                        ),
                  onOpenCod: !fresh || widget.onOpenCod == null
                      ? null
                      : (id) => _forward(ticket, scope, cache, (d) {
                          if (d.codSummary?.orderId == id) {
                            widget.onOpenCod?.call(id);
                          }
                        }),
                  onOpenReturn: !fresh || widget.onOpenReturn == null
                      ? null
                      : (id) => _forward(ticket, scope, cache, (d) {
                          if (d.returnSummaries.any((r) => r.returnId == id)) {
                            widget.onOpenReturn?.call(id);
                          }
                        }),
                ),
        ),
      ),
    );
  }
}
