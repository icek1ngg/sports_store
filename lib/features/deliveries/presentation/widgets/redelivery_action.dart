import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/delivery_task.dart';
import '../../domain/models/outbound_failure_command.dart';
import '../../domain/models/outbound_task_command.dart';
import '../../domain/models/redelivery_command.dart';
import '../view_models/outbound_result_gate.dart';
import '../view_models/redelivery_view_model.dart';

/// Manual, server-backed actions for a redelivery task in MH11.
class RedeliveryAction extends ConsumerStatefulWidget {
  const RedeliveryAction({
    required this.taskId,
    this.task,
    this.allowSubmit = true,
    super.key,
  });

  final String taskId;

  /// The page's already-authorized snapshot. It is used only to render a
  /// disabled label while the command VM revalidates; no write is enabled
  /// from this fallback.
  final DeliveryTaskSnapshot? task;
  final bool allowSubmit;

  @override
  ConsumerState<RedeliveryAction> createState() => _RedeliveryActionState();
}

class _RedeliveryActionState extends ConsumerState<RedeliveryAction> {
  DialogRoute<Object?>? _dialog;
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
  void dispose() {
    _closeDialog();
    super.dispose();
  }

  Future<void> _open(
    RedeliveryOperation operation,
    RedeliveryState state,
  ) async {
    if (_dialog != null || _deciding || !widget.allowSubmit) return;
    final provider = redeliveryViewModelProvider(widget.taskId);
    final vm = ref.read(provider.notifier);
    if (!state.details.hasValue) return;
    final details = state.details.requireValue;
    final task = details.task;
    final items = List<DeliveryTaskItem>.unmodifiable(details.items);
    final revision = vm.sessionRevisionForConfirmation;
    final gate = ref.read(outboundResultGateProvider(widget.taskId));
    if (gate != null && !identical(gate, vm)) return;
    if (!_canOpen(operation, state)) return;
    var decided = false;
    _deciding = true;
    late final DialogRoute<Object?> dialog;
    dialog = DialogRoute<Object?>(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (dialogContext, dialogRef, _) {
          final latest = dialogRef.watch(provider);
          final latestVm = dialogRef.read(provider.notifier);
          final stale =
              !latest.details.hasValue ||
              latest.details.requireValue.task != task ||
              !_sameItems(latest.details.requireValue.items, items) ||
              latestVm.sessionRevisionForConfirmation != revision ||
              !_canOpen(operation, latest);
          if (stale) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _dialog == dialog && dialog.isActive) {
                Navigator.of(dialogContext).pop(false);
              }
            });
            return const SizedBox.shrink();
          }
          return switch (operation) {
            RedeliveryOperation.accept => _AcceptDialog(
              task: task,
              items: items,
              onCancel: decided
                  ? null
                  : () {
                      decided = true;
                      Navigator.of(dialogContext).pop(false);
                    },
              onConfirm: decided
                  ? null
                  : () {
                      decided = true;
                      Navigator.of(dialogContext).pop(true);
                    },
            ),
            RedeliveryOperation.start => _StartDialog(
              task: task,
              items: items,
              onCancel: decided
                  ? null
                  : () {
                      decided = true;
                      Navigator.of(dialogContext).pop(false);
                    },
              onConfirm: decided
                  ? null
                  : () {
                      decided = true;
                      Navigator.of(dialogContext).pop(true);
                    },
            ),
            RedeliveryOperation.complete => _CompleteDialog(
              task: task,
              items: items,
              onCancel: decided
                  ? null
                  : () {
                      decided = true;
                      Navigator.of(dialogContext).pop(false);
                    },
              onConfirm: decided
                  ? null
                  : () {
                      decided = true;
                      Navigator.of(dialogContext).pop(true);
                    },
            ),
            RedeliveryOperation.fail => _FailureDialog(
              task: task,
              onCancel: decided
                  ? null
                  : () {
                      decided = true;
                      Navigator.of(dialogContext).pop(null);
                    },
              onConfirm: decided
                  ? null
                  : (value) {
                      decided = true;
                      Navigator.of(dialogContext).pop(value);
                    },
            ),
          };
        },
      ),
    );
    _dialog = dialog;
    try {
      final result = await Navigator.of(context).push<Object?>(dialog);
      _dialog = null;
      if (!mounted || result == false || result == null) return;
      final latest = ref.read(provider);
      final latestVm = ref.read(provider.notifier);
      if (!latest.details.hasValue ||
          latest.details.requireValue.task != task ||
          !_sameItems(latest.details.requireValue.items, items) ||
          latestVm.sessionRevisionForConfirmation != revision) {
        return;
      }
      switch (operation) {
        case RedeliveryOperation.accept:
          await latestVm.submitAccept(
            expectedTask: task,
            expectedItems: items,
            sessionRevision: revision,
          );
        case RedeliveryOperation.start:
          await latestVm.submitStart(
            expectedTask: task,
            sessionRevision: revision,
          );
        case RedeliveryOperation.complete:
          await latestVm.submitComplete(
            expectedTask: task,
            expectedItems: items,
            sessionRevision: revision,
          );
        case RedeliveryOperation.fail:
          final input = result as _RedeliveryFailureInput;
          await latestVm.submitFailure(
            reason: input.reason,
            description: input.description,
            expectedTask: task,
            sessionRevision: revision,
          );
      }
    } finally {
      _dialog = null;
      _deciding = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = redeliveryViewModelProvider(widget.taskId);
    final state = ref.watch(provider);
    final vm = ref.read(provider.notifier);
    final gate = ref.watch(outboundResultGateProvider(widget.taskId));
    final task = state.details.hasValue
        ? state.details.requireValue.task
        : widget.task;
    final gated = gate != null && !identical(gate, vm);
    final action = task == null
        ? null
        : switch (task.status) {
            DeliveryTaskStatus.assigned => RedeliveryOperation.accept,
            DeliveryTaskStatus.accepted => RedeliveryOperation.start,
            DeliveryTaskStatus.inTransit => null,
            _ => null,
          };
    final outcome = task?.status == DeliveryTaskStatus.inTransit;
    final detailsAvailable = state.details.hasValue;
    final openEnabled =
        widget.allowSubmit && !gated && !_deciding && detailsAvailable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.confirmed &&
            state.confirmedOperation == RedeliveryOperation.accept)
          const Text(
            'Đã xác nhận nhận đủ hàng giao lại; không phát sinh COD hoặc xuất tồn mới.',
            key: ValueKey('redelivery-accept-confirmed'),
          ),
        if (state.confirmed &&
            state.confirmedOperation == RedeliveryOperation.start)
          const Text(
            'Đã bắt đầu giao lại; đây là luồng miễn phí, không thu COD lần hai.',
            key: ValueKey('redelivery-start-confirmed'),
          ),
        if (state.confirmed &&
            state.confirmedOperation == RedeliveryOperation.complete)
          const Text(
            'Đã ghi nhận giao lại thành công và đóng yêu cầu trả hàng sau kiểm tra.',
            key: ValueKey('redelivery-complete-confirmed'),
          ),
        if (state.confirmed &&
            state.confirmedOperation == RedeliveryOperation.fail)
          const Text(
            'Đã ghi nhận giao lại thất bại; hàng vẫn thuộc custody và chờ quản lý xử lý. Không tự giao lại lần nữa.',
            key: ValueKey('redelivery-fail-confirmed'),
          ),
        if (state.busy) const Text('Đang gửi và đọc lại trạng thái nhiệm vụ…'),
        if (state.error != null)
          Text(
            redeliveryActionErrorText(state.error!),
            key: const ValueKey('redelivery-action-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (action != null && (!detailsAvailable || _canOpen(action, state)))
          OutlinedButton(
            key: ValueKey(
              action == RedeliveryOperation.accept
                  ? 'redelivery-accept-open'
                  : 'redelivery-start-open',
            ),
            onPressed: openEnabled ? () => _open(action, state) : null,
            child: Text(
              action == RedeliveryOperation.accept
                  ? 'Nhận hàng giao lại'
                  : 'Bắt đầu giao lại',
            ),
          ),
        if (outcome &&
            (!detailsAvailable ||
                _canOpen(RedeliveryOperation.complete, state))) ...[
          const SizedBox(height: 8),
          FilledButton(
            key: const ValueKey('redelivery-complete-open'),
            onPressed: openEnabled
                ? () => _open(RedeliveryOperation.complete, state)
                : null,
            child: const Text('Giao lại thành công'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const ValueKey('redelivery-failure-open'),
            onPressed: openEnabled
                ? () => _open(RedeliveryOperation.fail, state)
                : null,
            child: const Text('Báo giao lại thất bại'),
          ),
        ],
        if (state.pendingCommand != null || state.requiresReadRetry)
          TextButton(
            key: const ValueKey('redelivery-retry'),
            onPressed: state.busy || gated ? null : vm.retry,
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

bool _canOpen(RedeliveryOperation operation, RedeliveryState state) {
  return switch (operation) {
    RedeliveryOperation.accept => state.canAccept,
    RedeliveryOperation.start => state.canStart,
    RedeliveryOperation.complete => state.canComplete,
    RedeliveryOperation.fail => state.canFail,
  };
}

bool _sameItems(List<DeliveryTaskItem> left, List<DeliveryTaskItem> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    final a = left[index];
    final b = right[index];
    if (a.itemId.toLowerCase() != b.itemId.toLowerCase() ||
        a.itemSource != b.itemSource ||
        a.productName != b.productName ||
        a.quantity != b.quantity ||
        a.quantityCollected != b.quantityCollected) {
      return false;
    }
  }
  return true;
}

String redeliveryActionErrorText(OutboundCommandFailure failure) {
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

class _AcceptDialog extends StatefulWidget {
  const _AcceptDialog({
    required this.task,
    required this.items,
    required this.onCancel,
    required this.onConfirm,
  });

  final DeliveryTaskSnapshot task;
  final List<DeliveryTaskItem> items;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;

  @override
  State<_AcceptDialog> createState() => _AcceptDialogState();
}

class _AcceptDialogState extends State<_AcceptDialog> {
  var _checked = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Xác nhận nhận hàng giao lại'),
    content: _PlanContent(
      items: widget.items,
      intro: 'Chỉ xác nhận sau khi đã thực nhận đủ toàn bộ kế hoạch giao lại từ cửa hàng. Server sẽ kiểm tra custody; không xuất kho outbound và không tạo COD.',
      checkboxKey: const ValueKey('redelivery-accept-all'),
      checkboxTitle: 'Tôi đã nhận đủ toàn bộ kế hoạch trên',
      checked: _checked,
      onChanged: (value) => setState(() => _checked = value),
    ),
    actions: [
      TextButton(
        key: const ValueKey('redelivery-accept-cancel'),
        onPressed: widget.onCancel,
        child: const Text('Quay lại'),
      ),
      FilledButton(
        key: const ValueKey('redelivery-accept-confirm'),
        onPressed: _checked ? widget.onConfirm : null,
        child: const Text('Xác nhận nhận đủ'),
      ),
    ],
  );
}

class _StartDialog extends StatefulWidget {
  const _StartDialog({
    required this.task,
    required this.items,
    required this.onCancel,
    required this.onConfirm,
  });

  final DeliveryTaskSnapshot task;
  final List<DeliveryTaskItem> items;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;

  @override
  State<_StartDialog> createState() => _StartDialogState();
}

class _StartDialogState extends State<_StartDialog> {
  var _checked = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Bắt đầu giao lại'),
    content: _PlanContent(
      items: widget.items,
      intro: 'Chỉ bắt đầu khi đang giữ đủ đúng kế hoạch và sẵn sàng vận chuyển. Giao lại miễn phí, không thu COD lần hai và không áp dụng giới hạn hai lần giao outbound.',
      checkboxKey: const ValueKey('redelivery-start-all'),
      checkboxTitle: 'Tôi đang giữ đủ kế hoạch và bắt đầu giao',
      checked: _checked,
      onChanged: (value) => setState(() => _checked = value),
    ),
    actions: [
      TextButton(
        key: const ValueKey('redelivery-start-cancel'),
        onPressed: widget.onCancel,
        child: const Text('Quay lại'),
      ),
      FilledButton(
        key: const ValueKey('redelivery-start-confirm'),
        onPressed: _checked ? widget.onConfirm : null,
        child: const Text('Bắt đầu giao lại'),
      ),
    ],
  );
}

class _CompleteDialog extends StatefulWidget {
  const _CompleteDialog({
    required this.task,
    required this.items,
    required this.onCancel,
    required this.onConfirm,
  });

  final DeliveryTaskSnapshot task;
  final List<DeliveryTaskItem> items;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;

  @override
  State<_CompleteDialog> createState() => _CompleteDialogState();
}

class _CompleteDialogState extends State<_CompleteDialog> {
  var _checked = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Xác nhận giao lại thành công'),
    content: _PlanContent(
      items: widget.items,
      intro: 'Chỉ xác nhận khi khách đã nhận đủ mọi món và đúng số lượng theo kế hoạch. Thao tác này đóng yêu cầu sau kiểm tra; không thu COD lần hai.',
      checkboxKey: const ValueKey('redelivery-complete-all'),
      checkboxTitle: 'Khách đã nhận đủ toàn bộ kế hoạch trên',
      checked: _checked,
      onChanged: (value) => setState(() => _checked = value),
    ),
    actions: [
      TextButton(
        key: const ValueKey('redelivery-complete-cancel'),
        onPressed: widget.onCancel,
        child: const Text('Quay lại'),
      ),
      FilledButton(
        key: const ValueKey('redelivery-complete-confirm'),
        onPressed: _checked ? widget.onConfirm : null,
        child: const Text('Xác nhận giao đủ'),
      ),
    ],
  );
}

class _PlanContent extends StatelessWidget {
  const _PlanContent({
    required this.items,
    required this.intro,
    required this.checkboxKey,
    required this.checkboxTitle,
    required this.checked,
    required this.onChanged,
  });

  final List<DeliveryTaskItem> items;
  final String intro;
  final Key checkboxKey;
  final String checkboxTitle;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(intro),
        const SizedBox(height: 12),
        for (final item in items) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.inventory_2_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${item.productName}\nSố lượng giao lại: ${item.quantity}',
                  key: ValueKey('redelivery-plan-${item.itemId}'),
                ),
              ),
            ],
          ),
          if (item != items.last) const Divider(height: 20),
        ],
        const SizedBox(height: 8),
        CheckboxListTile(
          key: checkboxKey,
          contentPadding: EdgeInsets.zero,
          value: checked,
          onChanged: (value) => onChanged(value ?? false),
          title: Text(checkboxTitle),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      ],
    ),
  );
}

class _RedeliveryFailureInput {
  const _RedeliveryFailureInput(this.reason, this.description);

  final OutboundFailureReason reason;
  final String? description;
}

class _FailureDialog extends StatefulWidget {
  const _FailureDialog({
    required this.task,
    required this.onCancel,
    required this.onConfirm,
  });

  final DeliveryTaskSnapshot task;
  final VoidCallback? onCancel;
  final ValueChanged<_RedeliveryFailureInput?>? onConfirm;

  @override
  State<_FailureDialog> createState() => _FailureDialogState();
}

class _FailureDialogState extends State<_FailureDialog> {
  final _description = TextEditingController();
  OutboundFailureReason? _reason;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid =
        _reason != null &&
        (_reason != OutboundFailureReason.other ||
            _description.text.trim().isNotEmpty);
    return AlertDialog(
      title: const Text('Báo giao lại thất bại'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Chỉ báo khi đang giao lại và vẫn giữ đủ hàng. Task và yêu cầu sẽ chờ quản lý xử lý; không tự động giao lại hoặc hoàn tồn.',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<OutboundFailureReason>(
              key: const ValueKey('redelivery-failure-reason'),
              decoration: const InputDecoration(labelText: 'Lý do'),
              isExpanded: true,
              items: _reasonLabels.entries
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
              key: const ValueKey('redelivery-failure-description'),
              controller: _description,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: _reason == OutboundFailureReason.other
                    ? 'Mô tả (bắt buộc)'
                    : 'Mô tả (không dùng cho lý do này)',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('redelivery-failure-cancel'),
          onPressed: widget.onCancel,
          child: const Text('Quay lại'),
        ),
        FilledButton(
          key: const ValueKey('redelivery-failure-confirm'),
          onPressed: valid
              ? () => widget.onConfirm?.call(
                  _RedeliveryFailureInput(_reason!, _description.text.trim()),
                )
              : null,
          child: const Text('Xác nhận thất bại'),
        ),
      ],
    );
  }
}

const _reasonLabels = <OutboundFailureReason, String>{
  OutboundFailureReason.unreachable: 'Không liên lạc được',
  OutboundFailureReason.reschedule: 'Khách hẹn lại',
  OutboundFailureReason.badAddress: 'Địa chỉ không hợp lệ',
  OutboundFailureReason.refusal: 'Khách từ chối nhận',
  OutboundFailureReason.other: 'Khác',
};
