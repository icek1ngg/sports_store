import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/delivery_task.dart';
import '../../domain/models/outbound_task_command.dart';
import '../view_models/outbound_task_actions_view_model.dart';

/// Manual confirmations for the production outbound custody/start RPCs.
class OutboundTaskActions extends ConsumerStatefulWidget {
  const OutboundTaskActions({super.key, required this.task});

  final DeliveryTaskSnapshot task;

  @override
  ConsumerState<OutboundTaskActions> createState() =>
      _OutboundTaskActionsState();
}

class _OutboundTaskActionsState extends ConsumerState<OutboundTaskActions> {
  DialogRoute<bool>? _dialog;
  bool _deciding = false;

  void _closeDialog() {
    final dialog = _dialog;
    _dialog = null;
    if (dialog == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (dialog.isActive) dialog.navigator?.removeRoute(dialog);
    });
  }

  @override
  void didUpdateWidget(covariant OutboundTaskActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task != widget.task) _closeDialog();
  }

  @override
  void dispose() {
    _closeDialog();
    super.dispose();
  }

  Future<void> _confirm(OutboundTaskAction action) async {
    if (_dialog != null || _deciding) return;
    final provider = outboundTaskActionsViewModelProvider(widget.task.taskId);
    final vm = ref.read(provider.notifier);
    final task = widget.task;
    if (!vm.canExecute(action, task)) return;
    final revision = vm.sessionRevisionForConfirmation;
    final accept = action == OutboundTaskAction.acceptGoods;
    var checked = false;
    var decided = false;
    _deciding = true;
    final dialog = DialogRoute<bool>(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (dialogContext, dialogRef, _) {
          dialogRef.watch(provider);
          if (!mounted ||
              widget.task != task ||
              revision != vm.sessionRevisionForConfirmation ||
              !vm.canExecute(action, task)) {
            _closeDialog();
            return const SizedBox.shrink();
          }
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text(accept ? 'Xác nhận nhận hàng' : 'Bắt đầu giao hàng'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      accept
                          ? 'Chỉ xác nhận khi bạn đã thực nhận đầy đủ hàng. Server sẽ kiểm tra và ghi nhận xuất kho/custody.'
                          : 'Chỉ bắt đầu khi bạn đang giữ đủ hàng và sẵn sàng vận chuyển. Server sẽ ghi nhận lần giao.',
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      key: const ValueKey('outbound-confirm-custody'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: checked,
                      onChanged: decided
                          ? null
                          : (value) =>
                                setDialogState(() => checked = value ?? false),
                      title: Text(
                        accept
                            ? 'Tôi đã thực nhận đủ hàng'
                            : 'Tôi đang giữ đủ hàng và bắt đầu giao',
                      ),
                    ),
                    const Text(
                      'Thao tác này không xác nhận giao thành công hoặc thu COD.',
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  key: const ValueKey('outbound-confirm-cancel'),
                  onPressed: decided
                      ? null
                      : () {
                          decided = true;
                          Navigator.of(dialogContext).pop(false);
                        },
                  child: const Text('Quay lại'),
                ),
                FilledButton(
                  key: const ValueKey('outbound-confirm-submit'),
                  onPressed: !checked || decided
                      ? null
                      : () {
                          if (decided) return;
                          decided = true;
                          Navigator.of(dialogContext).pop(true);
                        },
                  child: Text(accept ? 'Xác nhận nhận hàng' : 'Bắt đầu giao'),
                ),
              ],
            ),
          );
        },
      ),
    );
    _dialog = dialog;
    try {
      final result = await Navigator.of(context).push(dialog);
      _dialog = null;
      if (result != true ||
          !mounted ||
          widget.task != task ||
          vm.sessionRevisionForConfirmation != revision) {
        return;
      }
      await vm.submit(action, expectedTask: task, sessionRevision: revision);
    } finally {
      _deciding = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = outboundTaskActionsViewModelProvider(widget.task.taskId);
    final state = ref.watch(provider);
    final vm = ref.read(provider.notifier);
    final action = switch (widget.task.status) {
      DeliveryTaskStatus.assigned => OutboundTaskAction.acceptGoods,
      DeliveryTaskStatus.accepted => OutboundTaskAction.startDelivery,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (action != null && canExecuteOutboundAction(widget.task, action))
          OutlinedButton(
            key: ValueKey(
              action == OutboundTaskAction.acceptGoods
                  ? 'outbound-accept-goods'
                  : 'outbound-start-delivery',
            ),
            onPressed: vm.canExecute(action, widget.task)
                ? () => _confirm(action)
                : null,
            child: Text(
              action == OutboundTaskAction.acceptGoods
                  ? 'Nhận hàng'
                  : 'Bắt đầu giao hàng',
            ),
          ),
        if (state.busy) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(
            key: ValueKey('outbound-action-loading'),
          ),
          const Text('Đang xác minh với server…'),
        ],
        if (state.error != null) ...[
          const SizedBox(height: 8),
          Text(
            outboundActionErrorText(state.error!),
            key: const ValueKey('outbound-action-error'),
          ),
        ],
        if (!state.actionsDenied &&
            (state.pendingCommand != null || state.requiresReadRetry))
          TextButton(
            key: const ValueKey('outbound-action-retry'),
            onPressed: state.busy ? null : vm.retry,
            child: Text(
              state.pendingCommand != null
                  ? 'Thử lại cùng yêu cầu'
                  : 'Đọc lại dữ liệu',
            ),
          ),
      ],
    );
  }
}

String outboundActionErrorText(OutboundCommandFailure failure) {
  if (failure is OutboundBusinessFailure) return failure.message;
  if (failure is OutboundAcknowledgementFailure) {
    return 'Chưa xác minh được phản hồi. Thử lại cùng yêu cầu đang giữ.';
  }
  return switch (failure.code) {
    OutboundCommandFailureCode.timeout || OutboundCommandFailureCode.network =>
      'Chưa xác định kết quả. Thử lại cùng yêu cầu để tránh ghi lặp.',
    OutboundCommandFailureCode.permissionDenied =>
      'Bạn không có quyền thực hiện thao tác này.',
    OutboundCommandFailureCode.staleAssignment =>
      'Phân công đã thay đổi. Không thể tiếp tục.',
    OutboundCommandFailureCode.sessionExpired => 'Phiên đăng nhập đã hết hạn.',
    OutboundCommandFailureCode.staleState =>
      'Trạng thái đã thay đổi. Vui lòng đọc lại nhiệm vụ.',
    OutboundCommandFailureCode.dependencyUnavailable =>
      'Dịch vụ chưa sẵn sàng. Vui lòng thử lại sau.',
    OutboundCommandFailureCode.invalidData =>
      'Dữ liệu yêu cầu không hợp lệ. Vui lòng đọc lại nhiệm vụ.',
    OutboundCommandFailureCode.unexpected =>
      'Chưa xác minh được kết quả. Vui lòng thử lại theo yêu cầu đang giữ.',
  };
}
