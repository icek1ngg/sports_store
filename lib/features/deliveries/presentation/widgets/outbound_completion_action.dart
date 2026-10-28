import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/delivery_task.dart';
import '../../domain/models/outbound_completion_failure.dart';
import '../../domain/models/outbound_task_command.dart';
import '../view_models/outbound_completion_view_model.dart';
import '../view_models/outbound_result_gate.dart';

class OutboundCompletionAction extends ConsumerStatefulWidget {
  const OutboundCompletionAction({
    super.key,
    required this.taskId,
    this.allowSubmit = true,
  });

  final String taskId;
  final bool allowSubmit;

  @override
  ConsumerState<OutboundCompletionAction> createState() =>
      _OutboundCompletionActionState();
}

class _OutboundCompletionActionState
    extends ConsumerState<OutboundCompletionAction> {
  bool _dialogOpen = false;
  bool _deciding = false;
  Route<bool>? _dialog;

  Future<void> _openConfirmation(OutboundCompletionState state) async {
    if (_dialogOpen ||
        !state.canComplete ||
        !state.details.hasValue ||
        ref.read(outboundResultGateProvider(widget.taskId)) != null) {
      return;
    }
    final vm = ref.read(
      outboundCompletionViewModelProvider(widget.taskId).notifier,
    );
    final revision = vm.sessionRevisionForConfirmation;
    final snapshot = state.details.requireValue.task;
    final amount = state.authoritativeAmountVnd;
    if (amount == null || amount <= 0) return;
    setState(() => _dialogOpen = true);
    final route = DialogRoute<bool>(
      context: context,
      builder: (_) => _CompletionConfirmationDialog(
        taskId: widget.taskId,
        snapshot: snapshot,
        revision: revision,
        amount: amount,
      ),
    );
    _dialog = route;
    try {
      final result = await Navigator.of(context).push<bool>(route);
      _dialog = null;
      if (result == true && mounted && !_deciding) {
        _deciding = true;
        final latest = ref.read(
          outboundCompletionViewModelProvider(widget.taskId),
        );
        if (!latest.details.hasValue ||
            snapshot != latest.details.requireValue.task ||
            vm.sessionRevisionForConfirmation != revision) {
          return;
        }
        await vm.submit(
          receivedAllItems: true,
          receivedFullCod: true,
          displayedAmountVnd: amount,
          sessionRevision: revision,
        );
      }
    } finally {
      _dialog = null;
      _deciding = false;
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  @override
  void dispose() {
    final dialog = _dialog;
    if (dialog != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (dialog.isActive) dialog.navigator?.removeRoute(dialog);
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(outboundCompletionViewModelProvider(widget.taskId));
    final gate = ref.watch(outboundResultGateProvider(widget.taskId));
    final amount = state.authoritativeAmountVnd;
    final error = state.error;
    final vm = ref.read(
      outboundCompletionViewModelProvider(widget.taskId).notifier,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (amount != null && widget.allowSubmit) Text(_formatVnd(amount)),
        if (state.confirmed)
          const Text(
            'Đã giao thành công theo trạng thái server.',
            key: ValueKey('completion-confirmed'),
          ),
        if (state.busy) const Text('Đang xác nhận và đọc lại dữ liệu…'),
        if (error != null)
          Text(
            _errorText(error),
            key: const ValueKey('completion-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (widget.allowSubmit && !state.confirmed && state.canComplete)
          FilledButton(
            key: const ValueKey('completion-open'),
            onPressed: state.busy || _dialogOpen || gate != null
                ? null
                : () => _openConfirmation(state),
            child: const Text('Giao thành công'),
          ),
        if (state.pendingCommand != null || state.requiresReadRetry)
          OutlinedButton(
            key: const ValueKey('completion-retry'),
            onPressed: state.busy || (gate != null && !identical(gate, vm))
                ? null
                : vm.retry,
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

class _CompletionConfirmationDialog extends ConsumerStatefulWidget {
  const _CompletionConfirmationDialog({
    required this.taskId,
    required this.snapshot,
    required this.revision,
    required this.amount,
  });

  final String taskId;
  final DeliveryTaskSnapshot snapshot;
  final int revision;
  final int amount;

  @override
  ConsumerState<_CompletionConfirmationDialog> createState() =>
      _CompletionConfirmationDialogState();
}

class _CompletionConfirmationDialogState
    extends ConsumerState<_CompletionConfirmationDialog> {
  var _goods = false;
  var _money = false;
  var _closed = false;

  void _decide(bool result) {
    if (_closed) return;
    _closed = true;
    Navigator.of(context).pop(result);
  }

  void _redactIfStale(OutboundCompletionState state) {
    final vm = ref.read(
      outboundCompletionViewModelProvider(widget.taskId).notifier,
    );
    final changed =
        ref.read(outboundResultGateProvider(widget.taskId)) != null ||
        vm.sessionRevisionForConfirmation != widget.revision ||
        state.actionsDenied ||
        !state.details.hasValue ||
        state.details.requireValue.task != widget.snapshot;
    if (changed && !_closed) {
      _closed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(outboundResultGateProvider(widget.taskId));
    final state = ref.watch(outboundCompletionViewModelProvider(widget.taskId));
    _redactIfStale(state);
    if (_closed) return const SizedBox.shrink();
    return AlertDialog(
      title: const Text('Xác nhận giao thành công'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatVnd(widget.amount),
              key: const ValueKey('completion-dialog-amount'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Số tiền do hệ thống tính, đã gồm phí giao hàng nếu áp dụng. Không thể chỉnh sửa.',
            ),
            CheckboxListTile(
              key: const ValueKey('completion-goods'),
              value: _goods,
              onChanged: (value) => setState(() => _goods = value ?? false),
              title: const Text('Khách đã nhận đủ toàn bộ hàng'),
            ),
            CheckboxListTile(
              key: const ValueKey('completion-money'),
              value: _money,
              onChanged: (value) => setState(() => _money = value ?? false),
              title: Text('Đã thu đủ ${_formatVnd(widget.amount)}'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('completion-cancel'),
          onPressed: () => _decide(false),
          child: const Text('Quay lại'),
        ),
        FilledButton(
          key: const ValueKey('completion-confirm'),
          onPressed: _goods && _money ? () => _decide(true) : null,
          child: const Text('Xác nhận'),
        ),
      ],
    );
  }
}

String _formatVnd(int value) {
  final digits = value.toString();
  final result = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) result.write('.');
    result.write(digits[i]);
  }
  return '$result đ';
}

String _errorText(OutboundCommandFailure failure) {
  if (failure is OutboundCompletionBusinessFailure) return failure.message;
  return switch (failure.code) {
    OutboundCommandFailureCode.timeout ||
    OutboundCommandFailureCode.network ||
    OutboundCommandFailureCode.unexpected =>
      'Chưa xác minh được kết quả. Thử lại cùng yêu cầu.',
    OutboundCommandFailureCode.permissionDenied ||
    OutboundCommandFailureCode.staleAssignment ||
    OutboundCommandFailureCode.sessionExpired =>
      'Phiên làm việc hoặc quyền giao hàng đã thay đổi.',
    OutboundCommandFailureCode.invalidData => 'Dữ liệu xác nhận không hợp lệ.',
    OutboundCommandFailureCode.staleState =>
      'Trạng thái nhiệm vụ đã thay đổi. Vui lòng đọc lại.',
    OutboundCommandFailureCode.dependencyUnavailable =>
      'Dịch vụ giao hàng chưa sẵn sàng. Vui lòng thử lại.',
  };
}
