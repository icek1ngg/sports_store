// TEST-ONLY P04.2 interaction harness. Never import this into lib/ or routes.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';

import 'outbound_action_fixture.dart';

/// Test-only bridge. Production MH11 never watches this provider or panel.
class OutboundActionHarnessFixture extends ConsumerWidget {
  const OutboundActionHarnessFixture({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = fixtureOutboundActionViewModelProvider(taskId);
    final state = ref.watch(provider);
    final viewModel = ref.read(provider.notifier);
    return OutboundActionPanelFixture(
      task: state.details.asData?.value.task,
      canAccept: state.canAccept,
      canStart: state.canStart,
      busy: state.busy,
      errorMessage: state.error == null
          ? null
          : state.pendingCommand == null &&
                state.requiresReadRetry &&
                (state.error!.code == OutboundCommandFailureCode.network ||
                    state.error!.code == OutboundCommandFailureCode.timeout)
          ? 'Không thể tải lại trạng thái. Thử lại thao tác đọc.'
          : _failureMessage(state.error!.code),
      retryLabel: state.pendingCommand != null
          ? 'Thử lại yêu cầu'
          : 'Tải lại trạng thái',
      onRetry:
          !state.actionsDenied &&
              (state.error != null ||
                  state.pendingCommand != null ||
                  state.requiresReadRetry)
          ? viewModel.retry
          : null,
      onConfirmed: viewModel.submit,
    );
  }
}

String _failureMessage(OutboundCommandFailureCode code) => switch (code) {
  OutboundCommandFailureCode.timeout || OutboundCommandFailureCode.network =>
    'Chưa xác định kết quả. Thử lại cùng request ID.',
  OutboundCommandFailureCode.permissionDenied =>
    'Bạn không có quyền thực hiện.',
  OutboundCommandFailureCode.staleAssignment => 'Phân công đã thay đổi.',
  OutboundCommandFailureCode.staleState =>
    'Trạng thái đã thay đổi. Vui lòng tải lại.',
  OutboundCommandFailureCode.sessionExpired => 'Phiên đăng nhập đã hết hạn.',
  OutboundCommandFailureCode.dependencyUnavailable =>
    'API nhận/bắt đầu giao chưa sẵn sàng.',
  OutboundCommandFailureCode.invalidData => 'Dữ liệu yêu cầu không hợp lệ.',
  OutboundCommandFailureCode.unexpected => 'Không thể thực hiện yêu cầu.',
};

class OutboundActionPanelFixture extends StatelessWidget {
  const OutboundActionPanelFixture({
    super.key,
    required this.task,
    required this.canAccept,
    required this.canStart,
    required this.busy,
    required this.onConfirmed,
    this.errorMessage,
    this.retryLabel,
    this.onRetry,
  });

  final DeliveryTaskSnapshot? task;
  final bool canAccept;
  final bool canStart;
  final bool busy;
  final Future<void> Function(OutboundTaskAction action) onConfirmed;
  final String? errorMessage;
  final String? retryLabel;
  final Future<void> Function()? onRetry;

  Future<void> _confirm(BuildContext context, OutboundTaskAction action) async {
    final accepting = action == OutboundTaskAction.acceptGoods;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(accepting ? 'Xác nhận nhận hàng' : 'Xác nhận bắt đầu giao'),
        content: Text(
          accepting
              ? 'Bạn đã thực nhận đủ hàng tại cửa hàng? Đây là mô phỏng kiểm thử, không xuất kho live.'
              : 'Bạn đã nhận hàng và sẵn sàng bắt đầu giao? Đây là mô phỏng kiểm thử.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('fixture-confirm-cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Quay lại'),
          ),
          FilledButton(
            key: const ValueKey('fixture-confirm-submit'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) await onConfirmed(action);
  }

  @override
  Widget build(BuildContext context) {
    final current =
        task?.kind == DeliveryTaskKind.outbound &&
        task?.scope == DeliverySnapshotScope.current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('DEMO TEST-ONLY — chưa kết nối RPC live'),
        if (task != null)
          Text('Trạng thái từ read fixture: ${task!.status.value}'),
        if (busy) const Text('Đang chờ kết quả và đọc lại trạng thái…'),
        if (current && task!.status == DeliveryTaskStatus.assigned)
          FilledButton(
            key: const ValueKey('fixture-accept'),
            onPressed: !busy && canAccept
                ? () => _confirm(context, OutboundTaskAction.acceptGoods)
                : null,
            child: const Text('Nhận hàng'),
          ),
        if (current && task!.status == DeliveryTaskStatus.accepted)
          FilledButton(
            key: const ValueKey('fixture-start'),
            onPressed: !busy && canStart
                ? () => _confirm(context, OutboundTaskAction.startDelivery)
                : null,
            child: const Text('Bắt đầu giao'),
          ),
        if (errorMessage != null)
          Text(
            errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (onRetry != null)
          OutlinedButton(
            key: const ValueKey('fixture-action-retry'),
            onPressed: busy ? null : onRetry,
            child: Text(retryLabel ?? 'Thử lại yêu cầu'),
          ),
      ],
    );
  }
}
