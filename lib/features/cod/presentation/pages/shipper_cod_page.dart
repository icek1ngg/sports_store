import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../domain/models/cod_collection.dart';
import '../view_models/shipper_cod_view_model.dart';
import '../widgets/cod_formatters.dart';

/// Read-only shipper MH12. Every amount/count comes from P06.1.
class ShipperCodPage extends ConsumerStatefulWidget {
  const ShipperCodPage({this.orderId, super.key});
  final String? orderId;

  @override
  ConsumerState<ShipperCodPage> createState() => _ShipperCodPageState();
}

class _ShipperCodPageState extends ConsumerState<ShipperCodPage>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // No Realtime publication or receipt write API is assumed. Poll only this
    // visible, foreground read page to observe changes made by a manager.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_foreground &&
          mounted &&
          (ModalRoute.of(context)?.isCurrent ?? true)) {
        final state = ref.read(shipperCodViewModelProvider(widget.orderId));
        if (!state.isLoading && !state.isLoadingMore && state.error == null) {
          unawaited(_refresh());
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() =>
      ref.read(shipperCodViewModelProvider(widget.orderId).notifier).refresh();

  @override
  Widget build(BuildContext context) {
    final provider = shipperCodViewModelProvider(widget.orderId);
    final state = ref.watch(provider);
    final vm = ref.read(provider.notifier);
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Text(
                  'NHÂN VIÊN GIAO HÀNG',
                  style: TextStyle(
                    color: AppColors.onPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Đối soát tiền mặt',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Theo dõi khoản COD bạn đã thu và bàn giao.',
            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.ash),
          ),
          if (widget.orderId != null) ...[
            const SizedBox(height: 8),
            Text(
              'Đang xem theo đơn ${widget.orderId}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 20),
          const _PolicyNotice(),
          const SizedBox(height: 16),
          if (!state.isLoading &&
              state.error == null &&
              state.heldTotalVnd != null)
            _HeldSummary(state: state, onRefresh: _refresh)
          else
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('cod-refresh'),
                onPressed: state.isLoading ? null : _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Làm mới'),
              ),
            ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final tabs = [
                for (final group in ShipperCodGroup.values)
                  _GroupTab(
                    group: group,
                    selected: state.group == group,
                    count: group == ShipperCodGroup.unreconciled
                        ? state.counts?.collected
                        : state.counts?.received,
                    onTap: () => vm.setGroup(group),
                  ),
              ];
              if (constraints.maxWidth < 370 ||
                  MediaQuery.textScalerOf(context).scale(14) > 20) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [tabs.first, const SizedBox(height: 8), tabs.last],
                );
              }
              return Row(
                children: [
                  Expanded(child: tabs.first),
                  const SizedBox(width: 8),
                  Expanded(child: tabs.last),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          if (state.isLoading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (state.error != null)
            _StatusPanel(
              key: const ValueKey('cod-error'),
              icon: Icons.cloud_off_outlined,
              text: state.error!.message,
              onRetry: _refresh,
            )
          else if (state.items.isEmpty)
            _StatusPanel(
              key: const ValueKey('cod-empty'),
              icon: Icons.receipt_long_outlined,
              text: state.group == ShipperCodGroup.unreconciled
                  ? 'Bạn chưa có khoản COD đã thu đang chờ đối soát.'
                  : 'Bạn chưa có khoản COD đã đối soát.',
            )
          else ...[
            Text(
              '${state.filteredTotal ?? '—'} khoản ${state.group == ShipperCodGroup.unreconciled ? 'chưa đối soát' : 'đã đối soát'}',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 12),
            for (final item in state.items) ...[
              _CodCard(collection: item),
              const SizedBox(height: 12),
            ],
          ],
          if (state.loadMoreError != null)
            _StatusPanel(
              icon: Icons.cloud_off_outlined,
              text: state.loadMoreError!.message,
              onRetry: vm.loadMore,
            ),
          if (state.hasMore)
            OutlinedButton.icon(
              key: const ValueKey('cod-load-more'),
              onPressed: state.isLoadingMore ? null : vm.loadMore,
              icon: state.isLoadingMore
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more),
              label: Text(state.isLoadingMore ? 'Đang tải…' : 'Tải thêm'),
            ),
          const SizedBox(height: 12),
          Text(
            'Khoản chưa thu không thuộc hai nhóm này và không được tính vào tiền đang giữ.',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mute),
          ),
          if (state.asOf != null &&
              state.error == null &&
              !state.isLoading) ...[
            const SizedBox(height: 8),
            Text(
              'Dữ liệu lúc ${formatCodTimestamp(state.asOf)}. Tự làm mới mỗi 30 giây khi đang xem.',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mute),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeldSummary extends StatelessWidget {
  const _HeldSummary({required this.state, required this.onRefresh});
  final ShipperCodState state;
  final VoidCallback onRefresh;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: AppColors.ink,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'TIỀN COD ĐANG GIỮ CHỜ NỘP',
          style: TextStyle(
            color: AppColors.hairline,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          formatCodVnd(state.heldTotalVnd!),
          key: const ValueKey('cod-held-total'),
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            color: AppColors.onPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${state.counts?.collected ?? '—'} khoản đã thu, chờ quản lý xác nhận nhận tiền',
          style: const TextStyle(color: AppColors.hairline),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const ValueKey('cod-refresh'),
            style: TextButton.styleFrom(foregroundColor: AppColors.onPrimary),
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Làm mới'),
          ),
        ),
        if (state.items.isEmpty &&
            state.filteredTotal == 0 &&
            state.heldTotalVnd! > 0)
          const Text(
            'Tổng đang giữ tính cả khoản thuộc nhóm Chưa đối soát.',
            style: TextStyle(color: AppColors.hairline),
          ),
      ],
    ),
  );
}

class _GroupTab extends StatelessWidget {
  const _GroupTab({
    required this.group,
    required this.selected,
    required this.count,
    required this.onTap,
  });
  final ShipperCodGroup group;
  final bool selected;
  final int? count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: OutlinedButton(
      key: ValueKey(
        group == ShipperCodGroup.unreconciled
            ? 'cod-unreconciled'
            : 'cod-reconciled',
      ),
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? AppColors.ink : AppColors.softCloud,
        foregroundColor: selected ? AppColors.onPrimary : AppColors.ink,
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      onPressed: onTap,
      child: Text(
        '${group == ShipperCodGroup.unreconciled ? 'Chưa đối soát' : 'Đã đối soát'}  ${count ?? '—'}',
        textAlign: TextAlign.center,
      ),
    ),
  );
}

class _PolicyNotice extends StatelessWidget {
  const _PolicyNotice();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.verified_user_outlined, size: 22),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Bàn giao đủ tiền từng đơn cho quản lý cửa hàng. Chỉ quản lý xác nhận cửa hàng đã nhận tiền.',
          ),
        ),
      ],
    ),
  );
}

class _CodCard extends StatelessWidget {
  const _CodCard({required this.collection});
  final CodCollection collection;
  @override
  Widget build(BuildContext context) {
    final received = collection.status == CodStatus.received;
    final theme = Theme.of(context);
    return Container(
      key: ValueKey('cod-record-${collection.orderId}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.softCloud,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            collection.orderCode ?? collection.orderId,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (collection.orderCodeSource == 'order_uuid')
            Text(
              'Mã tham chiếu đơn (UUID)',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mute),
            ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              avatar: Icon(
                received ? Icons.check_circle_outline : Icons.hourglass_top,
                size: 16,
                color: received ? AppColors.success : AppColors.ink,
              ),
              label: Text(received ? 'Đã đối soát' : 'Shipper đã thu'),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  received
                      ? 'COD cửa hàng đã nhận'
                      : 'Tiền mặt đã thu từ khách',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.mute,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatCodVnd(
                    received
                        ? collection.receivedAmountVnd
                        : collection.collectedAmountVnd,
                  ),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text('Thu tiền: ${formatCodTimestamp(collection.collectedAt)}'),
                if (received)
                  Text(
                    'Cửa hàng nhận: ${formatCodTimestamp(collection.receivedAt)}',
                  ),
              ],
            ),
          ),
          if (!received) ...[
            const SizedBox(height: 12),
            Text(
              'Chờ quản lý kiểm đếm và xác nhận. Bạn không thể tự xác nhận đã nộp.',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.ash),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    super.key,
    required this.icon,
    required this.text,
    this.onRetry,
  });
  final IconData icon;
  final String text;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      children: [
        Icon(icon, size: 36, color: AppColors.mute),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center),
        if (onRetry != null)
          TextButton(
            key: const ValueKey('cod-retry'),
            onPressed: onRetry,
            child: const Text('Thử lại'),
          ),
      ],
    ),
  );
}
