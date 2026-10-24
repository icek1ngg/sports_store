import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';

import '../../data/repositories/operational_providers.dart';
import '../../data/repositories/operational_read_access.dart';
import '../../domain/models/delivery_task.dart';
import '../../domain/models/delivery_task_query.dart';
import '../../domain/models/operational_failure.dart';
import '../view_models/delivery_task_list_view_model.dart';
import '../widgets/delivery_task_card.dart';

/// MH10 task list. Search, filters and pagination are delegated to the
/// server-backed ViewModel; this page never filters an already loaded page.
class DeliveryTaskListPage extends ConsumerStatefulWidget {
  const DeliveryTaskListPage({super.key});

  @override
  ConsumerState<DeliveryTaskListPage> createState() =>
      _DeliveryTaskListPageState();
}

class _DeliveryTaskListPageState extends ConsumerState<DeliveryTaskListPage> {
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;

  @override
  void initState() {
    super.initState();
    final previous = ref.read(deliveryTaskListViewModelProvider);
    _searchController = TextEditingController(text: previous.query.query ?? '');
    _searchController.addListener(_handleSearchTextChanged);
    _searchFocusNode = FocusNode();
    // A guard or a direct navigation may recreate MH10 instead of revealing
    // the page that awaited MH11. Keep filters, but revalidate cached rows.
    if (previous.counts != null || previous.error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(
            ref.read(deliveryTaskListViewModelProvider.notifier).refresh(),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchTextChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleSearchTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // The provider owns the session epoch. Clear an unsubmitted draft when
    // the account changes so text from account A cannot appear in account B.
    ref.listen<AsyncValue<OperationalSession>>(operationalSessionProvider, (
      previous,
      next,
    ) {
      final previousSession = previous?.asData?.value;
      final nextSession = next.asData?.value;
      final sameSession =
          previousSession != null &&
          nextSession != null &&
          identical(previousSession, nextSession);
      // A loading/error event is also a session boundary. Clear drafts on
      // sign-out and auth refresh, even when no replacement user exists.
      if (!sameSession && mounted) {
        _searchController.clear();
      }
    });

    ref.listen(deliveryTaskListViewModelProvider, (_, next) {
      // The backend can reject an expired JWT before an auth event arrives.
      if (next.error?.code == OperationalFailureCode.sessionExpired &&
          mounted) {
        _searchController.clear();
      }
    });
    final state = ref.watch(deliveryTaskListViewModelProvider);
    final notifier = ref.read(deliveryTaskListViewModelProvider.notifier);

    return LayoutBuilder(
      builder: (context, constraints) => RefreshIndicator(
        key: const ValueKey('task-refresh-indicator'),
        onRefresh: notifier.refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _Header(
                state: state,
                controller: _searchController,
                focusNode: _searchFocusNode,
                onSubmit: (value) => unawaited(notifier.setSearch(value)),
                onClear: () {
                  _searchController.clear();
                  unawaited(notifier.setSearch(''));
                },
                onRefresh: () => unawaited(notifier.refresh()),
              ),
            ),
            SliverToBoxAdapter(
              child: _FilterBar(
                state: state,
                onKind: (kind) => unawaited(notifier.setKind(kind)),
                onGroup: (group) => unawaited(notifier.setStateGroup(group)),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              sliver: _TaskResults(
                state: state,
                maxWidth: constraints.maxWidth,
                onTask: _openTask,
                onRetry: () => unawaited(notifier.refresh()),
                onLoadMore: () => unawaited(notifier.loadMore()),
                onReset: _resetFilters,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openTask(DeliveryTaskSnapshot task) async {
    await context.push<void>('/shipper/tasks/${task.taskId}');
    if (!mounted) return;
    // MH11 may have changed assignment/state. Requery the same server filters
    // after returning; the page never mutates cards locally.
    await ref.read(deliveryTaskListViewModelProvider.notifier).refresh();
  }

  Future<void> _resetFilters() async {
    final notifier = ref.read(deliveryTaskListViewModelProvider.notifier);
    _searchController.clear();
    await notifier.resetFilters();
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.state,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.onClear,
    required this.onRefresh,
  });

  final DeliveryTaskListState state;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmit;
  final VoidCallback onClear;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = state.filteredTotal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nhiệm vụ giao nhận',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      count == null
                          ? 'Đang kiểm tra nhiệm vụ được phân công'
                          : '$count nhiệm vụ theo bộ lọc hiện tại',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('task-refresh'),
                tooltip: 'Làm mới nhiệm vụ',
                onPressed: state.isLoading ? null : onRefresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('task-search-input'),
            controller: controller,
            focusNode: focusNode,
            textInputAction: TextInputAction.search,
            onSubmitted: onSubmit,
            decoration: InputDecoration(
              hintText: 'Tìm mã đơn hoặc người nhận',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: controller.text.isEmpty
                  ? IconButton(
                      key: const ValueKey('task-search-submit'),
                      tooltip: 'Tìm kiếm',
                      onPressed: () => onSubmit(controller.text),
                      icon: const Icon(Icons.arrow_forward),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: const ValueKey('task-search-clear'),
                          tooltip: 'Xóa tìm kiếm',
                          onPressed: onClear,
                          icon: const Icon(Icons.clear),
                        ),
                        IconButton(
                          key: const ValueKey('task-search-submit'),
                          tooltip: 'Tìm kiếm',
                          onPressed: () => onSubmit(controller.text),
                          icon: const Icon(Icons.arrow_forward),
                        ),
                      ],
                    ),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: AppColors.hairlineSoft),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: scheme.primary, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.state,
    required this.onKind,
    required this.onGroup,
  });

  final DeliveryTaskListState state;
  final ValueChanged<DeliveryTaskKind?> onKind;
  final ValueChanged<DeliveryTaskStateGroup?> onGroup;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GroupTabs(state: state, onSelected: onGroup),
          const SizedBox(height: 10),
          _KindChips(state: state, onSelected: onKind),
        ],
      ),
    );
  }
}

class _GroupTabs extends StatelessWidget {
  const _GroupTabs({required this.state, required this.onSelected});

  final DeliveryTaskListState state;
  final ValueChanged<DeliveryTaskStateGroup?> onSelected;

  @override
  Widget build(BuildContext context) {
    final groups = <DeliveryTaskStateGroup?>[
      null,
      DeliveryTaskStateGroup.waiting,
      DeliveryTaskStateGroup.inTransit,
      DeliveryTaskStateGroup.completed,
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final group in groups)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _FilterChoice(
                key: ValueKey('task-group-${group?.value ?? 'all'}'),
                label: _groupLabel(group),
                count: _groupCount(state.counts, group),
                selected: state.query.stateGroup == group,
                onPressed: () => onSelected(group),
              ),
            ),
        ],
      ),
    );
  }
}

class _KindChips extends StatelessWidget {
  const _KindChips({required this.state, required this.onSelected});

  final DeliveryTaskListState state;
  final ValueChanged<DeliveryTaskKind?> onSelected;

  @override
  Widget build(BuildContext context) {
    final kinds = <DeliveryTaskKind?>[
      null,
      DeliveryTaskKind.outbound,
      DeliveryTaskKind.returnPickup,
      DeliveryTaskKind.redelivery,
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final kind in kinds)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                key: ValueKey('task-kind-${kind?.value ?? 'all'}'),
                selected: state.query.kind == kind,
                label: Text(
                  _kindFilterLabel(kind),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: state.query.kind == kind
                        ? AppColors.onPrimary
                        : AppColors.ink,
                  ),
                ),
                onSelected: (_) => onSelected(kind),
                avatar: Icon(
                  _kindFilterIcon(kind),
                  size: 17,
                  color: state.query.kind == kind
                      ? AppColors.onPrimary
                      : AppColors.ash,
                ),
                showCheckmark: false,
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterChoice extends StatelessWidget {
  const _FilterChoice({
    required this.label,
    required this.count,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? scheme.primary : scheme.surface,
          foregroundColor: selected ? scheme.onPrimary : scheme.onSurface,
          side: BorderSide(
            color: selected ? scheme.primary : AppColors.hairlineSoft,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          shape: const StadiumBorder(),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                key: ValueKey('mh10-count-$label'),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: selected ? AppColors.charcoal : AppColors.softCloud,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('$count'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TaskResults extends StatelessWidget {
  const _TaskResults({
    required this.state,
    required this.maxWidth,
    required this.onTask,
    required this.onRetry,
    required this.onLoadMore,
    required this.onReset,
  });

  final DeliveryTaskListState state;
  final double maxWidth;
  final ValueChanged<DeliveryTaskSnapshot> onTask;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.items.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (state.error != null && state.items.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _StatusPanel(
          key: const ValueKey('mh10-error'),
          icon: Icons.cloud_off_outlined,
          title: 'Không thể tải nhiệm vụ',
          message: _failureMessage(state.error!),
          actionLabel: 'Thử lại',
          onAction: onRetry,
        ),
      );
    }

    if (!state.isLoading && state.items.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _StatusPanel(
          key: const ValueKey('mh10-empty'),
          icon: Icons.checklist_outlined,
          title: 'Không tìm thấy nhiệm vụ',
          message: 'Không có nhiệm vụ nào khớp với tìm kiếm hoặc bộ lọc.',
          actionLabel: 'Đặt lại bộ lọc',
          onAction: onReset,
        ),
      );
    }

    final children = <Widget>[
      if (state.isLoading)
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: LinearProgressIndicator(),
        ),
      for (final task in state.items)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: DeliveryTaskCard(task: task, onTap: () => onTask(task)),
        ),
      if (state.loadMoreError != null)
        _InlineLoadMoreError(
          failure: state.loadMoreError!,
          onRetry: onLoadMore,
        ),
      if (state.hasMore)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: OutlinedButton.icon(
            key: const ValueKey('task-load-more'),
            onPressed: state.isLoadingMore ? null : onLoadMore,
            icon: state.isLoadingMore
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.expand_more),
            label: Text(state.isLoadingMore ? 'Đang tải…' : 'Tải thêm'),
          ),
        ),
    ];
    return SliverToBoxAdapter(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth.clamp(0, 760)),
          child: Column(children: children),
        ),
      ),
    );
  }
}

class _InlineLoadMoreError extends StatelessWidget {
  const _InlineLoadMoreError({required this.failure, required this.onRetry});

  final OperationalFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _failureMessage(failure),
              style: TextStyle(color: scheme.error),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Thử lại')),
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.softCloud,
                foregroundColor: AppColors.ink,
                child: Icon(icon, size: 28),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}

String _failureMessage(OperationalFailure failure) => failure.message;

String _groupLabel(DeliveryTaskStateGroup? group) => switch (group) {
  null => 'Tất cả',
  DeliveryTaskStateGroup.waiting => 'Chờ',
  DeliveryTaskStateGroup.inTransit => 'Đang giao',
  DeliveryTaskStateGroup.completed => 'Hoàn tất',
};

int? _groupCount(DeliveryTaskCounts? counts, DeliveryTaskStateGroup? group) {
  if (counts == null) return null;
  return switch (group) {
    null => counts.total,
    DeliveryTaskStateGroup.waiting => counts.waiting,
    DeliveryTaskStateGroup.inTransit => counts.inTransit,
    DeliveryTaskStateGroup.completed => counts.completed,
  };
}

String _kindFilterLabel(DeliveryTaskKind? kind) => switch (kind) {
  null => 'Tất cả loại',
  DeliveryTaskKind.outbound => 'Giao hàng',
  DeliveryTaskKind.returnPickup => 'Thu hồi hàng',
  DeliveryTaskKind.redelivery => 'Giao lại',
};

IconData _kindFilterIcon(DeliveryTaskKind? kind) => switch (kind) {
  null => Icons.all_inclusive,
  DeliveryTaskKind.outbound => Icons.local_shipping_outlined,
  DeliveryTaskKind.returnPickup => Icons.assignment_return_outlined,
  DeliveryTaskKind.redelivery => Icons.swap_horizontal_circle_outlined,
};
