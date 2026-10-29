import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/delivery_task.dart';
import '../../domain/models/outbound_failure_command.dart';
import '../../domain/models/outbound_task_command.dart';
import '../view_models/outbound_failure_view_model.dart';
import '../view_models/outbound_result_gate.dart';

const _labels = <OutboundFailureReason, String>{
  OutboundFailureReason.unreachable: 'Không liên hệ được',
  OutboundFailureReason.reschedule: 'Khách hẹn lại',
  OutboundFailureReason.badAddress: 'Sai địa chỉ',
  OutboundFailureReason.refusal: 'Khách từ chối nhận',
  OutboundFailureReason.other: 'Khác',
};

class OutboundFailureAction extends ConsumerStatefulWidget {
  const OutboundFailureAction({
    super.key,
    required this.taskId,
    this.allowSubmit = true,
  });
  final String taskId;
  final bool allowSubmit;
  @override
  ConsumerState<OutboundFailureAction> createState() =>
      _OutboundFailureActionState();
}

class _OutboundFailureActionState extends ConsumerState<OutboundFailureAction> {
  Route<_ReasonInput>? _dialog;
  bool _open = false;
  Future<void> _confirm(OutboundFailureState state) async {
    if (_open ||
        !state.canFail ||
        ref.read(outboundResultGateProvider(widget.taskId)) != null) {
      return;
    }
    final vm = ref.read(
      outboundFailureViewModelProvider(widget.taskId).notifier,
    );
    final revision = vm.sessionRevisionForConfirmation;
    final snapshot = state.details.requireValue.task;
    setState(() => _open = true);
    final route = DialogRoute<_ReasonInput>(
      context: context,
      builder: (_) => _FailureDialog(
        taskId: widget.taskId,
        snapshot: snapshot,
        revision: revision,
      ),
    );
    _dialog = route;
    try {
      final input = await Navigator.of(context).push(route);
      _dialog = null;
      if (!mounted || input == null) return;
      final latest = ref.read(outboundFailureViewModelProvider(widget.taskId));
      if (!latest.canFail ||
          latest.details.requireValue.task != snapshot ||
          revision != vm.sessionRevisionForConfirmation) {
        return;
      }
      await vm.submit(
        reason: input.reason,
        description: input.description,
        sessionRevision: revision,
      );
    } finally {
      _dialog = null;
      if (mounted) setState(() => _open = false);
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
    final state = ref.watch(outboundFailureViewModelProvider(widget.taskId));
    final gate = ref.watch(outboundResultGateProvider(widget.taskId));
    final vm = ref.read(
      outboundFailureViewModelProvider(widget.taskId).notifier,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.confirmed)
          Text(
            state.disposition == OutboundFailureDisposition.storeReturnPending
                ? 'Giao thất bại lần hai. Chờ hoàn về cửa hàng.'
                : 'Giao thất bại. Chờ quản lý quyết định.',
            key: const ValueKey('failure-confirmed'),
          ),
        if (state.busy) const Text('Đang gửi và xác minh kết quả…'),
        if (state.error != null)
          Text(
            state.error is OutboundBusinessFailure
                ? (state.error! as OutboundBusinessFailure).message
                : switch (state.error!.code) {
                    OutboundCommandFailureCode.permissionDenied ||
                    OutboundCommandFailureCode.staleAssignment ||
                    OutboundCommandFailureCode.sessionExpired =>
                      'Phiên làm việc hoặc quyền giao hàng đã thay đổi.',
                    OutboundCommandFailureCode.staleState =>
                      'Trạng thái nhiệm vụ đã thay đổi. Vui lòng đọc lại.',
                    _ => 'Chưa xác minh được kết quả. Vui lòng thử lại.',
                  },
            key: const ValueKey('failure-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (widget.allowSubmit && !state.confirmed && state.canFail)
          OutlinedButton(
            key: const ValueKey('failure-open'),
            onPressed: _open || gate != null ? null : () => _confirm(state),
            child: const Text('Báo giao thất bại'),
          ),
        if (state.pendingCommand != null || state.requiresReadRetry)
          OutlinedButton(
            key: const ValueKey('failure-retry'),
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

class _ReasonInput {
  const _ReasonInput(this.reason, this.description);
  final OutboundFailureReason reason;
  final String? description;
}

class _FailureDialog extends ConsumerStatefulWidget {
  const _FailureDialog({
    required this.taskId,
    required this.snapshot,
    required this.revision,
  });
  final String taskId;
  final DeliveryTaskSnapshot snapshot;
  final int revision;
  @override
  ConsumerState<_FailureDialog> createState() => _FailureDialogState();
}

class _FailureDialogState extends ConsumerState<_FailureDialog> {
  final _description = TextEditingController();
  OutboundFailureReason? _reason;
  bool _closed = false;
  void _decide(_ReasonInput? result) {
    if (_closed) return;
    _closed = true;
    Navigator.of(context).pop(result);
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(outboundFailureViewModelProvider(widget.taskId));
    final vm = ref.read(
      outboundFailureViewModelProvider(widget.taskId).notifier,
    );
    final gate = ref.watch(outboundResultGateProvider(widget.taskId));
    if (vm.sessionRevisionForConfirmation != widget.revision ||
        !state.canFail ||
        state.details.requireValue.task != widget.snapshot ||
        gate != null) {
      if (!_closed) {
        _closed = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
    }
    if (_closed) return const SizedBox.shrink();
    final valid =
        _reason != null &&
        (_reason != OutboundFailureReason.other ||
            _description.text.trim().isNotEmpty);
    return AlertDialog(
      title: const Text('Báo giao thất bại'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Không ghi nhận thu COD. Việc giao lại hoặc hoàn hàng do quản lý quyết định.',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<OutboundFailureReason>(
              key: const ValueKey('failure-reason'),
              decoration: const InputDecoration(labelText: 'Lý do'),
              isExpanded: true,
              items: _labels.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
              onChanged: (reason) => setState(() => _reason = reason),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('failure-description'),
              controller: _description,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: _reason == OutboundFailureReason.other
                    ? 'Mô tả (bắt buộc)'
                    : 'Mô tả (tùy chọn)',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('failure-cancel'),
          onPressed: () => _decide(null),
          child: const Text('Quay lại'),
        ),
        FilledButton(
          key: const ValueKey('failure-confirm'),
          onPressed: valid
              ? () => _decide(_ReasonInput(_reason!, _description.text.trim()))
              : null,
          child: const Text('Xác nhận thất bại'),
        ),
      ],
    );
  }
}
