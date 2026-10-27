import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../domain/models/delivery_task.dart';
import '../../domain/models/delivery_task_details.dart';
import '../../domain/models/operational_failure.dart';
import '../view_models/delivery_task_detail_view_model.dart';
import '../widgets/outbound_task_actions.dart';
import '../widgets/delivery_call_action.dart';
import '../widgets/outbound_completion_action.dart';
import '../view_models/outbound_completion_view_model.dart';
import '../view_models/outbound_failure_view_model.dart';
import '../view_models/delivery_reporting_view_model.dart';
import '../widgets/outbound_failure_action.dart';
import '../widgets/delivery_reporting_action.dart';
import '../view_models/outbound_task_actions_view_model.dart';

/// MH11 detail view with server-backed outbound accept/start actions.
///
/// This page deliberately renders the server projection only. It does not
/// read an order, return request, catalog item, or Storage object directly,
/// and delegates writes to the feature ViewModel. The shared shipper shell owns the
/// Scaffold and AppBar around this page.
class DeliveryTaskDetailPage extends ConsumerStatefulWidget {
  const DeliveryTaskDetailPage({required this.taskId, super.key});

  final String taskId;

  @override
  ConsumerState<DeliveryTaskDetailPage> createState() =>
      _DeliveryTaskDetailPageState();
}

class _DeliveryTaskDetailPageState
    extends ConsumerState<DeliveryTaskDetailPage> {
  bool _completionControllerActive = false;
  bool _outboundControllerActive = false;
  bool _reportingControllerActive = false;
  DeliveryTaskSnapshot? _lastReportingSnapshot;
  var _reportingContextRefreshScheduled = false;
  Future<void> _refresh() async {
    await ref
        .read(deliveryTaskDetailViewModelProvider(widget.taskId).notifier)
        .refresh();
    if (!mounted || !_reportingControllerActive) return;
    await ref
        .read(deliveryReportingViewModelProvider(widget.taskId).notifier)
        .refreshContext();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deliveryTaskDetailViewModelProvider(widget.taskId));
    final task = state.asData?.value.task;
    if (task?.kind == DeliveryTaskKind.outbound &&
        task?.scope == DeliverySnapshotScope.current) {
      _outboundControllerActive = true;
    }
    // Reporting has its own restricted projection. Once this page has seen
    // any outbound task, keep its controller alive across detail refreshes so
    // an uncertain handover/incident command retains the same request key.
    if (task?.kind == DeliveryTaskKind.outbound) {
      _reportingControllerActive = true;
      if (_lastReportingSnapshot != null && _lastReportingSnapshot != task) {
        _scheduleReportingContextRefresh();
      }
      _lastReportingSnapshot = task;
    }
    if (_outboundControllerActive) {
      ref.watch(outboundTaskActionsViewModelProvider(widget.taskId));
    }
    if (task?.kind == DeliveryTaskKind.outbound &&
        task?.scope == DeliverySnapshotScope.current &&
        task?.status == DeliveryTaskStatus.inTransit) {
      _completionControllerActive = true;
    }
    // Keep the command controller visible while the read projection switches
    // to loading/history, so its acknowledged COD/list reconciliation finishes.
    if (_completionControllerActive) {
      ref.watch(outboundCompletionViewModelProvider(widget.taskId));
      ref.watch(outboundFailureViewModelProvider(widget.taskId));
    }
    if (_reportingControllerActive) {
      ref.watch(deliveryReportingViewModelProvider(widget.taskId));
    }

    return RefreshIndicator(
      key: const ValueKey('task-detail-refresh'),
      onRefresh: _refresh,
      color: Theme.of(context).colorScheme.primary,
      child: CustomScrollView(
        key: const ValueKey('task-detail-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [_content(state)],
      ),
    );
  }

  void _scheduleReportingContextRefresh() {
    if (_reportingContextRefreshScheduled) return;
    _reportingContextRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportingContextRefreshScheduled = false;
      if (!mounted || !_reportingControllerActive) return;
      unawaited(
        ref
            .read(deliveryReportingViewModelProvider(widget.taskId).notifier)
            .refreshContext(),
      );
    });
  }

  Widget _content(AsyncValue<DeliveryTaskDetails> state) {
    // A refresh must not keep rendering the previous recipient, address, COD,
    // or item data while the server revalidates access.
    if (state.isLoading || state.isRefreshing) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: _DetailLoading(),
      );
    }
    if (state.hasError) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _DetailError(
          error: state.error,
          onRetry: () => unawaited(
            ref
                .read(
                  deliveryTaskDetailViewModelProvider(widget.taskId).notifier,
                )
                .refresh(),
          ),
        ),
      );
    }
    final details = state.asData?.value;
    if (details == null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _DetailError(
          error: const OperationalFailure(OperationalFailureCode.unexpected),
          onRetry: () => unawaited(
            ref
                .read(
                  deliveryTaskDetailViewModelProvider(widget.taskId).notifier,
                )
                .refresh(),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      sliver: SliverList.list(
        children: [
          _DetailBody(
            details: details,
            onMapReturned: _refresh,
            showCompletionRecovery: _completionControllerActive,
            showReporting: _reportingControllerActive,
          ),
        ],
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.details,
    required this.onMapReturned,
    required this.showCompletionRecovery,
    required this.showReporting,
  });

  final DeliveryTaskDetails details;
  final Future<void> Function() onMapReturned;
  final bool showCompletionRecovery;
  final bool showReporting;

  @override
  Widget build(BuildContext context) {
    final task = details.task;
    final isCurrent = task.scope == DeliverySnapshotScope.current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DetailHero(task: task),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Điểm giao nhận',
          icon: Icons.location_on_outlined,
          child: _RecipientSection(task: task, onMapReturned: onMapReturned),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Ghi chú',
          icon: Icons.sticky_note_2_outlined,
          child: _NotesSection(details: details),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Danh sách hàng',
          icon: Icons.inventory_2_outlined,
          child: _ItemsSection(details: details),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'COD',
          icon: Icons.payments_outlined,
          child: _CodSection(task: task),
        ),
        if (isCurrent && task.kind == DeliveryTaskKind.outbound) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Thao tác tiếp theo',
            icon: Icons.task_alt_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutboundTaskActions(task: task),
                if (task.status == DeliveryTaskStatus.inTransit)
                  OutboundCompletionAction(taskId: task.taskId),
                if (task.status == DeliveryTaskStatus.inTransit)
                  OutboundFailureAction(taskId: task.taskId),
                if (isCurrent &&
                    task.status != DeliveryTaskStatus.assigned &&
                    task.status != DeliveryTaskStatus.accepted)
                  _ActionSection(task: task),
              ],
            ),
          ),
        ] else if (isCurrent) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Thao tác tiếp theo',
            icon: Icons.task_alt_outlined,
            child: _ActionSection(task: task),
          ),
        ],
        if (showCompletionRecovery &&
            task.kind == DeliveryTaskKind.outbound &&
            task.status != DeliveryTaskStatus.inTransit) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Kết quả xác nhận',
            icon: Icons.task_alt_outlined,
            child: Column(
              children: [
                OutboundCompletionAction(
                  taskId: task.taskId,
                  allowSubmit: false,
                ),
                OutboundFailureAction(taskId: task.taskId, allowSubmit: false),
              ],
            ),
          ),
        ],
        if (showReporting && task.kind == DeliveryTaskKind.outbound) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Báo cáo bàn giao / sự cố',
            icon: Icons.report_problem_outlined,
            child: DeliveryReportingAction(taskId: task.taskId),
          ),
        ],
        const SizedBox(height: 12),
        _ReadOnlyNotice(scope: task.scope),
      ],
    );
  }
}

class _DetailHero extends StatelessWidget {
  const _DetailHero({required this.task});

  final DeliveryTaskSnapshot task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColor = _statusColor(task.status, scheme);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Pill(
                label: _kindLabel(task.kind),
                foreground: AppColors.primary,
                background: AppColors.surface,
              ),
              _Pill(
                label: _statusLabel(task.status),
                foreground: AppColors.onPrimary,
                background: statusColor,
              ),
              if (task.scope != DeliverySnapshotScope.current)
                _Pill(
                  label: task.scope == DeliverySnapshotScope.history
                      ? 'Lịch sử'
                      : 'Giới hạn',
                  foreground: AppColors.onPrimary,
                  background: AppColors.charcoal,
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Chi tiết nhiệm vụ',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: AppColors.onPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Mã tham chiếu nhiệm vụ',
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColors.inverseOnSurface,
            ),
          ),
          const SizedBox(height: 3),
          SelectableText(
            task.taskId,
            maxLines: 2,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.onPrimary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.15,
            ),
          ),
          if (task.scope == DeliverySnapshotScope.current &&
              _shouldShowAttempt(task)) ...[
            const SizedBox(height: 16),
            Text(
              _attemptLabel(task),
              style: theme.textTheme.labelLarge?.copyWith(
                color: AppColors.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecipientSection extends StatelessWidget {
  const _RecipientSection({required this.task, required this.onMapReturned});

  final DeliveryTaskSnapshot task;
  final Future<void> Function() onMapReturned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final destination = task.destination;
    final isCurrent = task.scope == DeliverySnapshotScope.current;

    if (!isCurrent || destination == null) {
      return _RestrictedInfo(
        text: 'Thông tin người nhận và địa chỉ đã được giới hạn.',
        icon: Icons.lock_outline,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          destination.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        SelectableText(
          destination.phone,
          maxLines: 1,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.home_outlined, size: 19, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                destination.address,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DeliveryCallAction(task: task),
            if (_canOpenMap(task))
              OutlinedButton.icon(
                key: const ValueKey('task-detail-map'),
                onPressed: () => _openMap(context),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Mở bản đồ'),
              ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          'Gọi điện chỉ mở trình quay số; bạn quyết định thực hiện cuộc gọi.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Future<void> _openMap(BuildContext context) async {
    await context.push<void>('/shipper/tasks/${task.taskId}/map');
    if (!context.mounted) return;
    await onMapReturned();
  }
}

class _NotesSection extends StatelessWidget {
  const _NotesSection({required this.details});

  final DeliveryTaskDetails details;

  @override
  Widget build(BuildContext context) {
    final note = details.notes;
    final theme = Theme.of(context);
    final isCurrent = details.task.scope == DeliverySnapshotScope.current;
    final notesAreAvailable =
        details.notesSource != DeliveryNotesSource.unavailableSchema;
    if (!isCurrent ||
        !notesAreAvailable ||
        note == null ||
        note.trim().isEmpty) {
      return _RestrictedInfo(
        text: isCurrent ? 'Ghi chú chưa khả dụng.' : 'Ghi chú đã bị giới hạn.',
        icon: Icons.info_outline,
      );
    }
    return Text(note, style: theme.textTheme.bodyMedium);
  }
}

class _ItemsSection extends StatelessWidget {
  const _ItemsSection({required this.details});

  final DeliveryTaskDetails details;

  @override
  Widget build(BuildContext context) {
    final task = details.task;
    final theme = Theme.of(context);
    final isCurrent = task.scope == DeliverySnapshotScope.current;
    if (!isCurrent) {
      return _RestrictedInfo(
        text: 'Danh sách hàng không có trong phạm vi nhiệm vụ này.',
        icon: Icons.lock_outline,
      );
    }
    if (!details.itemsAvailable) {
      return _RestrictedInfo(
        text: task.itemSource == DeliveryItemSource.unavailableRedeliveryPlan
            ? 'Danh sách hàng giao lại chưa khả dụng.'
            : 'Danh sách hàng chưa khả dụng.',
        icon: Icons.inventory_2_outlined,
      );
    }
    if (details.items.isEmpty) {
      return Text(
        'Chưa có dòng hàng được cung cấp.',
        style: theme.textTheme.bodyMedium,
      );
    }

    return Column(
      children: [
        for (var index = 0; index < details.items.length; index++) ...[
          _ItemRow(item: details.items[index]),
          if (index < details.items.length - 1)
            const Divider(height: 24, thickness: 1),
        ],
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final DeliveryTaskItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final attributes = _attributeSummary(item.attributes);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: ValueKey('image-placeholder-${item.itemId}'),
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.softCloud,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.hairlineSoft),
          ),
          child: Icon(
            Icons.image_not_supported,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ảnh chưa được cung cấp',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                item.productName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (item.variantLabel != null) ...[
                const SizedBox(height: 3),
                Text(
                  item.variantLabel!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (attributes != null) ...[
                const SizedBox(height: 3),
                Text(
                  attributes,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 5),
              Text(
                'Số lượng: ${item.quantity}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (item.quantityCollected != null)
                Text(
                  'Đã nhận: ${item.quantityCollected}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CodSection extends StatelessWidget {
  const _CodSection({required this.task});

  final DeliveryTaskSnapshot task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (task.scope != DeliverySnapshotScope.current) {
      return _RestrictedInfo(
        text: 'Thông tin COD đã được giới hạn.',
        icon: Icons.lock_outline,
      );
    }

    final isOutbound = task.kind == DeliveryTaskKind.outbound;
    final amount = task.amountToCollectVnd;
    final amountLabel = switch ((isOutbound, amount)) {
      (true, final value?) => _formatVnd(value),
      (true, null) => 'Chưa có tổng COD',
      (false, _) => 'Không thu COD',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          amountLabel,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          isOutbound ? 'Tổng COD cần thu' : 'Nhiệm vụ này không thu COD',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (isOutbound) ...[
          const SizedBox(height: 10),
          Text(
            amount == null
                ? 'Tổng COD chưa khả dụng.'
                : 'Chưa có chi tiết tiền hàng và phí giao hàng.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _ActionSection extends StatelessWidget {
  const _ActionSection({required this.task});

  final DeliveryTaskSnapshot task;

  @override
  Widget build(BuildContext context) {
    final labels = _futureActionLabels(task);
    final theme = Theme.of(context);
    if (labels.isEmpty) {
      return Text(
        'Không có thao tác tiếp theo trong trạng thái này.',
        style: theme.textTheme.bodyMedium,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < labels.length; index++) ...[
          OutlinedButton(onPressed: null, child: Text(labels[index])),
          if (index < labels.length - 1) const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
        Text(
          'Các thao tác bị khóa sẽ được tích hợp ở phase tương ứng.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice({required this.scope});

  final DeliverySnapshotScope scope;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMasked = scope != DeliverySnapshotScope.current;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.softCloud,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairlineSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isMasked ? Icons.lock_outline : Icons.visibility_outlined,
            size: 19,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              isMasked
                  ? 'Đây là bản ghi lịch sử hoặc bị giới hạn; dữ liệu riêng tư không được hiển thị.'
                  : 'Các thao tác được xác minh theo nhiệm vụ trên server. Báo bàn giao chưa phải cửa hàng nhận, kiểm tra hoặc nhập lại tồn kho.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.hairlineSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _RestrictedInfo extends StatelessWidget {
  const _RestrictedInfo({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.softCloud,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 9),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: foreground, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _DetailLoading extends StatelessWidget {
  const _DetailLoading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(
            'Đang tải chi tiết nhiệm vụ…',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final failure = error is OperationalFailure
        ? error as OperationalFailure
        : const OperationalFailure(OperationalFailureCode.unexpected);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 42, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text(
            failure.message,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const ValueKey('task-detail-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    );
  }
}

bool _shouldShowAttempt(DeliveryTaskSnapshot task) {
  if (task.kind != DeliveryTaskKind.outbound) return true;
  return switch (task.status) {
    DeliveryTaskStatus.assigned || DeliveryTaskStatus.accepted => true,
    DeliveryTaskStatus.inTransit ||
    DeliveryTaskStatus.delivered ||
    DeliveryTaskStatus.failed ||
    DeliveryTaskStatus.returnedToStore => true,
    DeliveryTaskStatus.pendingAssignment ||
    DeliveryTaskStatus.cancelled ||
    DeliveryTaskStatus.managerActionRequired => false,
  };
}

String _attemptLabel(DeliveryTaskSnapshot task) {
  if (task.kind != DeliveryTaskKind.outbound) {
    return 'Không áp dụng hạn mức 2 lần giao đi';
  }
  final label =
      task.status == DeliveryTaskStatus.assigned ||
          task.status == DeliveryTaskStatus.accepted
      ? 'Lần dự kiến'
      : 'Lần giao';
  return '$label: ${task.attemptNumber} / 2';
}

List<String> _futureActionLabels(DeliveryTaskSnapshot task) {
  return switch ((task.kind, task.status)) {
    (DeliveryTaskKind.outbound, DeliveryTaskStatus.assigned) => ['Nhận hàng'],
    (DeliveryTaskKind.outbound, DeliveryTaskStatus.accepted) => [
      'Bắt đầu giao',
    ],
    (DeliveryTaskKind.outbound, DeliveryTaskStatus.inTransit) => [],
    (DeliveryTaskKind.returnPickup, DeliveryTaskStatus.assigned) => [
      'Xác nhận lấy hàng',
    ],
    (DeliveryTaskKind.returnPickup, DeliveryTaskStatus.accepted) => [
      'Bắt đầu vận chuyển',
    ],
    (DeliveryTaskKind.returnPickup, DeliveryTaskStatus.inTransit) => [
      'Báo bàn giao về kho',
    ],
    (DeliveryTaskKind.redelivery, DeliveryTaskStatus.assigned) => [
      'Nhận hàng giao lại',
    ],
    (DeliveryTaskKind.redelivery, DeliveryTaskStatus.accepted) => [
      'Bắt đầu giao lại',
    ],
    (DeliveryTaskKind.redelivery, DeliveryTaskStatus.inTransit) => [
      'Giao lại thành công',
      'Báo giao lại thất bại',
    ],
    _ => const [],
  };
}

String _kindLabel(DeliveryTaskKind kind) => switch (kind) {
  DeliveryTaskKind.outbound => 'Giao đơn hàng',
  DeliveryTaskKind.returnPickup => 'Lấy hàng hoàn',
  DeliveryTaskKind.redelivery => 'Giao lại',
};

String _statusLabel(DeliveryTaskStatus status) => switch (status) {
  DeliveryTaskStatus.pendingAssignment => 'Đang chờ phân công',
  DeliveryTaskStatus.assigned => 'Đã phân công',
  DeliveryTaskStatus.accepted => 'Đã nhận hàng',
  DeliveryTaskStatus.inTransit => 'Đang vận chuyển',
  DeliveryTaskStatus.delivered => 'Đã giao',
  DeliveryTaskStatus.failed => 'Giao thất bại',
  DeliveryTaskStatus.returnedToStore => 'Đã hoàn về cửa hàng',
  DeliveryTaskStatus.cancelled => 'Đã hủy',
  DeliveryTaskStatus.managerActionRequired => 'Chờ quản lý xử lý',
};

Color _statusColor(DeliveryTaskStatus status, ColorScheme scheme) {
  return switch (status) {
    DeliveryTaskStatus.delivered => AppColors.success,
    DeliveryTaskStatus.failed || DeliveryTaskStatus.cancelled => scheme.error,
    DeliveryTaskStatus.managerActionRequired => AppColors.sale,
    _ => AppColors.charcoal,
  };
}

bool _canOpenMap(DeliveryTaskSnapshot task) {
  final destination = task.destination;
  return task.scope == DeliverySnapshotScope.current &&
      destination != null &&
      _isUuid(task.taskId) &&
      destination.latitude.isFinite &&
      destination.longitude.isFinite &&
      destination.latitude >= -90 &&
      destination.latitude <= 90 &&
      destination.longitude >= -180 &&
      destination.longitude <= 180;
}

bool _isUuid(String value) {
  return RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
}

String? _attributeSummary(Map<String, dynamic>? attributes) {
  if (attributes == null || attributes.isEmpty) return null;
  final values = attributes.entries
      .take(3)
      .map((entry) => '${entry.key}: ${entry.value}')
      .join(' · ');
  return values.isEmpty ? null : values;
}

String _formatVnd(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
    buffer.write(digits[index]);
  }
  return '${buffer.toString()} đ';
}
