import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../domain/models/cod_collection.dart';
import '../../domain/models/cod_collection_query.dart';
import '../../../deliveries/data/repositories/operational_providers.dart';
import '../view_models/cod_providers.dart';
import '../view_models/manager_cod_view_model.dart';
import 'cod_formatters.dart';

/// Manager presentation inside the same MH12 route/shell, never a new page.
class ManagerCodPanel extends ConsumerStatefulWidget {
  const ManagerCodPanel({this.orderId, super.key});
  final String? orderId;
  @override
  ConsumerState<ManagerCodPanel> createState() => _ManagerCodPanelState();
}

class _ManagerCodPanelState extends ConsumerState<ManagerCodPanel>
    with WidgetsBindingObserver {
  late final TextEditingController _order;
  late final TextEditingController _shipper;
  Timer? _timer;
  bool _foreground = true;
  bool _dialogOpen = false;
  String? _validation;
  DialogRoute<bool>? _dialogRoute;
  NavigatorState? _dialogNavigator;

  @override
  void initState() {
    super.initState();
    final state = ref.read(managerCodViewModelProvider(widget.orderId));
    _order = TextEditingController(text: state.orderId ?? '');
    _shipper = TextEditingController(text: state.shipperId ?? '');
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted &&
          _foreground &&
          !_dialogOpen &&
          (ModalRoute.of(context)?.isCurrent ?? true)) {
        final state = ref.read(managerCodViewModelProvider(widget.orderId));
        if (!_blocked(state) &&
            !state.isLoading &&
            !state.isLoadingMore &&
            state.error == null) {
          unawaited(_refresh());
        }
      }
    });
  }

  bool _blocked(ManagerCodState state) =>
      _dialogOpen ||
      state.isSubmitting ||
      state.pendingCommand != null ||
      state.requiresReadRetry;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
      unawaited(_refresh());
    }
  }

  @override
  void didUpdateWidget(covariant ManagerCodPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId != widget.orderId) {
      _order.text = widget.orderId ?? '';
      _shipper.clear();
      _validation = null;
    }
  }

  Future<void> _refresh() async {
    final state = ref.read(managerCodViewModelProvider(widget.orderId));
    if (_blocked(state)) return;
    await ref
        .read(managerCodViewModelProvider(widget.orderId).notifier)
        .refresh();
  }

  Future<void> _applyFilters({bool clear = false}) async {
    if (clear) {
      _order.clear();
      _shipper.clear();
    }
    final order = _order.text.trim();
    final shipper = _shipper.text.trim();
    try {
      CodCollectionQuery(
        orderId: order.isEmpty ? null : order,
        shipperId: shipper.isEmpty ? null : shipper,
      );
    } on ArgumentError {
      setState(
        () => _validation =
            'Nhập UUID đơn/shipper hợp lệ hoặc để trống để xem tất cả.',
      );
      return;
    }
    setState(() => _validation = null);
    await ref
        .read(managerCodViewModelProvider(widget.orderId).notifier)
        .setFilters(
          orderId: order.isEmpty ? null : order,
          shipperId: shipper.isEmpty ? null : shipper,
        );
  }

  Future<void> _confirm(CodCollection collection) async {
    final provider = managerCodViewModelProvider(widget.orderId);
    final state = ref.read(provider);
    if (_blocked(state) ||
        state.isLoading ||
        collection.status != CodStatus.collected) {
      return;
    }
    final vm = ref.read(provider.notifier);
    final revision = vm.sessionRevisionForConfirmation;
    final capturedSession = ref.read(operationalSessionProvider).asData?.value;
    final capturedRouteOrder = widget.orderId;
    final amount = collection.collectedAmountVnd;
    setState(() => _dialogOpen = true);
    var checked = false;
    try {
      final route = DialogRoute<bool>(
        context: context,
        builder: (context) => Consumer(
          builder: (context, dialogRef, _) {
            final role = dialogRef.watch(codScreenRoleProvider);
            final session = dialogRef.watch(operationalSessionProvider);
            if (!mounted ||
                widget.orderId != capturedRouteOrder ||
                role.isLoading ||
                role.asData?.value != 'manager' ||
                session.isLoading ||
                capturedSession == null ||
                !identical(capturedSession, session.asData?.value)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final route = _dialogRoute;
                final navigator = _dialogNavigator;
                if (route != null &&
                    route.isActive &&
                    navigator?.mounted == true) {
                  navigator!.removeRoute(route);
                }
              });
              return const SizedBox.shrink();
            }
            return StatefulBuilder(
              builder: (context, change) => AlertDialog(
                title: const Text('Xác nhận nhận đủ COD'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Đơn ${collection.orderCode ?? collection.orderId}'),
                      const SizedBox(height: 8),
                      Text(
                        'Shipper: ${collection.shipperId ?? 'Không có dữ liệu'}',
                      ),
                      const SizedBox(height: 16),
                      Text(
                        formatCodVnd(amount),
                        key: const ValueKey('manager-cod-confirm-amount'),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Nếu chưa nhận đủ tiền mặt thực tế, giữ nguyên Chưa đối soát. Không nhận một phần hoặc bù trừ hoàn tiền.',
                      ),
                      CheckboxListTile(
                        key: const ValueKey('manager-cod-received-full'),
                        contentPadding: EdgeInsets.zero,
                        value: checked,
                        onChanged: (value) =>
                            change(() => checked = value ?? false),
                        title: const Text(
                          'Tôi đã kiểm đếm và nhận đủ số tiền này.',
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    key: const ValueKey('manager-cod-cancel'),
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Chưa nhận đủ'),
                  ),
                  FilledButton(
                    key: const ValueKey('manager-cod-confirm'),
                    onPressed: checked
                        ? () => Navigator.pop(context, true)
                        : null,
                    child: const Text('Xác nhận'),
                  ),
                ],
              ),
            );
          },
        ),
      );
      _dialogRoute = route;
      _dialogNavigator = Navigator.of(context, rootNavigator: true);
      final accepted = await _dialogNavigator!.push(route);
      if (!mounted ||
          accepted != true ||
          vm.sessionRevisionForConfirmation != revision) {
        return;
      }
      await vm.confirmFullReceipt(
        collection: collection,
        receivedFullAmount: true,
        displayedAmountVnd: amount,
        sessionRevision: revision,
      );
    } finally {
      _dialogRoute = null;
      _dialogNavigator = null;
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  @override
  void dispose() {
    final route = _dialogRoute;
    final navigator = _dialogNavigator;
    if (route != null && route.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive && navigator?.mounted == true) {
          navigator!.removeRoute(route);
        }
      });
    }
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _order.dispose();
    _shipper.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = managerCodViewModelProvider(widget.orderId);
    final state = ref.watch(provider);
    final vm = ref.read(provider.notifier);
    final blocked = _blocked(state);
    final theme = Theme.of(context);
    ref.listen(operationalSessionProvider, (previous, next) {
      if (next.isLoading ||
          !identical(previous?.asData?.value, next.asData?.value)) {
        _order.text = widget.orderId ?? '';
        _shipper.clear();
        _validation = null;
      }
    });
    ref.listen(codScreenRoleProvider, (previous, next) {
      if (next.isLoading || next.asData?.value != 'manager') {
        _order.text = widget.orderId ?? '';
        _shipper.clear();
        _validation = null;
      }
    });
    ref.listen(provider, (previous, next) {
      // Session/role changes reset the provider's filters and private draft.
      if (previous != null &&
          previous.orderId != next.orderId &&
          next.orderId == null) {
        _order.clear();
      }
      if (previous != null &&
          previous.shipperId != next.shipperId &&
          next.shipperId == null) {
        _shipper.clear();
      }
    });
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        key: const ValueKey('manager-cod-panel'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'QUẢN LÝ CỬA HÀNG',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Đối soát COD',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          _Box(
            child: const Text(
              'COD độc lập với trả hàng/hoàn tiền. Kiểm đếm và xác nhận nhận đủ tiền từng đơn; không bù trừ nghĩa vụ COD.',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('manager-cod-order-filter'),
            controller: _order,
            enabled: !blocked,
            decoration: const InputDecoration(
              labelText: 'Mã tham chiếu đơn (UUID)',
              prefixIcon: Icon(Icons.search),
            ),
            onSubmitted: (_) => _applyFilters(),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('manager-cod-shipper-filter'),
            controller: _shipper,
            enabled: !blocked,
            decoration: const InputDecoration(
              labelText: 'UUID shipper',
              prefixIcon: Icon(Icons.person_search_outlined),
            ),
            onSubmitted: (_) => _applyFilters(),
          ),
          if (_validation != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _validation!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                key: const ValueKey('manager-cod-apply'),
                onPressed: blocked ? null : _applyFilters,
                icon: const Icon(Icons.search),
                label: const Text('Tìm kiếm'),
              ),
              TextButton(
                key: const ValueKey('manager-cod-clear'),
                onPressed: blocked ? null : () => _applyFilters(clear: true),
                child: const Text('Xóa bộ lọc'),
              ),
              TextButton.icon(
                key: const ValueKey('manager-cod-refresh'),
                onPressed: blocked || state.isLoading ? null : _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Làm mới'),
              ),
            ],
          ),
          if (state.error == null &&
              !state.isLoading &&
              state.heldTotalVnd != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'COD CÒN Ở SHIPPER',
                    style: TextStyle(color: AppColors.hairline),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formatCodVnd(state.heldTotalVnd!),
                    key: const ValueKey('manager-cod-held-total'),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: AppColors.onPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tổng theo bộ lọc đơn/shipper, gồm toàn bộ khoản đã thu chưa nhận.',
                    style: TextStyle(color: AppColors.hairline),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final group in ManagerCodGroup.values)
                ChoiceChip(
                  key: ValueKey(
                    group == ManagerCodGroup.unreconciled
                        ? 'manager-cod-unreconciled'
                        : 'manager-cod-reconciled',
                  ),
                  label: Text(
                    '${group == ManagerCodGroup.unreconciled ? 'Chưa đối soát' : 'Đã đối soát'}  ${(group == ManagerCodGroup.unreconciled ? state.counts?.collected : state.counts?.received) ?? '—'}',
                  ),
                  selected: state.group == group,
                  onSelected: blocked ? null : (_) => vm.setGroup(group),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (state.actionError != null) ...[
            _Box(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    state.actionError!.message,
                    key: const ValueKey('manager-cod-action-error'),
                  ),
                  if (state.pendingCommand != null && !state.requiresReadRetry)
                    const Text(
                      'Chưa xác định kết quả. Thử lại giữ nguyên request ID và số tiền đã xác nhận.',
                    ),
                  if (state.pendingCommand != null || state.requiresReadRetry)
                    TextButton(
                      key: const ValueKey('manager-cod-action-retry'),
                      onPressed: state.isSubmitting ? null : vm.retryReceipt,
                      child: Text(
                        state.requiresReadRetry
                            ? 'Đọc lại kết quả'
                            : 'Thử lại cùng yêu cầu',
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (state.isSubmitting)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Expanded(child: Text('Đang xác nhận và đọc lại dữ liệu…')),
                ],
              ),
            ),
          if (state.isLoading)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (state.error != null)
            _Box(
              child: Column(
                children: [
                  Text(state.error!.message),
                  TextButton(
                    key: const ValueKey('manager-cod-read-retry'),
                    onPressed: blocked ? null : _refresh,
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            )
          else if (state.items.isEmpty)
            const _Box(
              key: ValueKey('manager-cod-empty'),
              child: Text('Không có khoản COD trong nhóm và bộ lọc này.'),
            )
          else ...[
            Text(
              '${state.filteredTotal ?? '—'} khoản',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 10),
            for (final collection in state.items) ...[
              _ManagerCodRecord(
                collection: collection,
                onConfirm: blocked ? null : () => _confirm(collection),
              ),
              const SizedBox(height: 12),
            ],
          ],
          if (state.loadMoreError != null) Text(state.loadMoreError!.message),
          if (state.nextCursor != null)
            OutlinedButton(
              key: const ValueKey('manager-cod-load-more'),
              onPressed: blocked || state.isLoadingMore ? null : vm.loadMore,
              child: Text(state.isLoadingMore ? 'Đang tải…' : 'Tải thêm'),
            ),
          const SizedBox(height: 16),
          Text(
            'Khoản chưa thu không thuộc hai nhóm đối soát. Thời gian hiển thị UTC.',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mute),
          ),
        ],
      ),
    );
  }
}

class _ManagerCodRecord extends StatelessWidget {
  const _ManagerCodRecord({required this.collection, required this.onConfirm});
  final CodCollection collection;
  final VoidCallback? onConfirm;
  @override
  Widget build(BuildContext context) {
    final received = collection.status == CodStatus.received;
    return _Box(
      key: ValueKey('manager-cod-record-${collection.orderId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            collection.orderCode ?? collection.orderId,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (collection.orderCodeSource == 'order_uuid')
            const Text('Mã tham chiếu đơn (UUID)'),
          const SizedBox(height: 8),
          Text('Shipper: ${collection.shipperId ?? 'Chưa có dữ liệu'}'),
          const SizedBox(height: 8),
          Text(
            received
                ? 'Cửa hàng đã nhận tiền'
                : 'Shipper đã thu — Chờ nhận tại cửa hàng',
          ),
          const SizedBox(height: 12),
          Text(
            formatCodVnd(
              received
                  ? collection.receivedAmountVnd
                  : collection.collectedAmountVnd,
            ),
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          ExpansionTile(
            title: const Text('Chi tiết khoản thu'),
            tilePadding: EdgeInsets.zero,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'COD dự kiến: ${formatCodVnd(collection.expectedAmountVnd)}',
                    ),
                    Text(
                      'Đã thu: ${formatCodVnd(collection.collectedAmountVnd)}',
                    ),
                    Text(
                      'Thu tiền: ${formatCodTimestamp(collection.collectedAt)}',
                    ),
                    Text(
                      'Người thu: ${collection.collectedBy ?? 'Chưa có dữ liệu'}',
                    ),
                    if (received) ...[
                      Text(
                        'Người nhận: ${collection.receivedBy ?? 'Chưa có dữ liệu'}',
                      ),
                      Text(
                        'Cửa hàng nhận: ${formatCodTimestamp(collection.receivedAt)}',
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (!received && collection.status == CodStatus.collected)
            FilledButton.icon(
              key: ValueKey('manager-cod-open-${collection.orderId}'),
              onPressed: onConfirm,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Xác nhận nhận đủ tiền'),
            ),
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.softCloud,
    borderRadius: BorderRadius.circular(16),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}
