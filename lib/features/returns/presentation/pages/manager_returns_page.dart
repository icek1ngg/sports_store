import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/foreground_refresh.dart';
import '../../domain/models/return_request_failure.dart';
import '../view_models/manager_return_view_models.dart';
import '../widgets/manager_return_sections.dart';

/// Return management list (manager): search, status filter, open detail.
/// Opening a row never changes state.
class ManagerReturnsPage extends ConsumerWidget {
  const ManagerReturnsPage({required this.onOpen, super.key});

  /// Opens the detail; the list reloads when that route is popped.
  final Future<void> Function(String returnId) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(managerReturnListProvider);
    final viewModel = ref.read(managerReturnListProvider.notifier);
    final list = state.list;

    final Widget content;
    if (list == null) {
      content = state.loading
          ? const Center(
              child: CircularProgressIndicator(key: ValueKey('mh15-loading')),
            )
          : _Message(
              key: const ValueKey('mh15-list-error'),
              text: managerLoadMessage(state.failure),
              onRetry: viewModel.refresh,
            );
    } else if (list.items.isEmpty) {
      content = _Message(
        key: const ValueKey('mh15-empty'),
        text: state.query.trim().isNotEmpty
            ? 'Không có yêu cầu phù hợp với "${state.query.trim()}".'
            : state.status == null
            ? 'Chưa có yêu cầu trả hàng nào.'
            : 'Không có yêu cầu ở trạng thái "${managerStatusLabel(state.status!)}".',
      );
    } else {
      content = ListView.separated(
        key: const ValueKey('mh15-list'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: list.items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = list.items[index];
          return ManagerReturnCard(
            item: item,
            onOpen: () async {
              await onOpen(item.returnId);
              if (context.mounted) await viewModel.poll();
            },
          );
        },
      );
    }

    return AppTheme.notificationsScope(
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              ManagerReturnsHeader(
                onRefresh: state.loading ? null : viewModel.refresh,
              ),
              if (state.loading && list != null)
                const LinearProgressIndicator(minHeight: 2),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: ManagerReturnSearchField(
                  value: state.query,
                  onChanged: viewModel.setQuery,
                ),
              ),
              ManagerReturnFilterBar(
                selected: state.status,
                counts: list?.counts ?? const {},
                onSelected: viewModel.selectStatus,
              ),
              const SizedBox(height: 10),
              if (state.isStale)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    '${managerLoadMessage(state.failure)} Đang hiển thị dữ liệu đã tải trước đó.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.sale,
                    ),
                  ),
                ),
              Expanded(
                child: ForegroundRefresh(
                  enabled: list != null,
                  canRefresh: () => viewModel.canPoll,
                  onRefresh: viewModel.poll,
                  child: RefreshIndicator(
                    onRefresh: viewModel.refresh,
                    child: content,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String managerLoadMessage(ReturnRequestFailure? failure) =>
    switch (failure?.code) {
      ReturnRequestFailureCode.network => 'Không thể kết nối.',
      ReturnRequestFailureCode.permissionDenied =>
        'Tài khoản không có quyền quản lý trả hàng.',
      ReturnRequestFailureCode.returnNotFound =>
        'Không tìm thấy yêu cầu trả hàng.',
      ReturnRequestFailureCode.sessionExpired => 'Phiên đăng nhập đã hết hạn.',
      ReturnRequestFailureCode.backendUnavailable =>
        'Dịch vụ quản lý trả hàng chưa sẵn sàng trên máy chủ.',
      _ => 'Không tải được dữ liệu.',
    };

class _Message extends StatelessWidget {
  const _Message({required this.text, this.onRetry, super.key});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    // Scrollable so pull-to-refresh also works on empty/error states.
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            height: 1.45,
            color: AppColors.charcoal,
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.ink,
                shape: const StadiumBorder(),
              ),
              child: const Text('Thử lại'),
            ),
          ),
        ],
      ],
    );
  }
}
