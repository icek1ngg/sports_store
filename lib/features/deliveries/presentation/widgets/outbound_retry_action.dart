import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/operational_providers.dart';
import '../../domain/models/delivery_task.dart';
import '../../domain/models/outbound_task_command.dart';
import '../view_models/outbound_result_gate.dart';
import '../view_models/outbound_retry_view_model.dart';

/// Explicit action shown for a failed first outbound attempt. The server
/// checks that this shipper still owns the failed task and creates task 2;
/// this widget never invents an assignment or silently retries the write.
class OutboundRetryAction extends ConsumerStatefulWidget {
  const OutboundRetryAction({
    super.key,
    required this.task,
    required this.onCreated,
  });

  final DeliveryTaskSnapshot task;
  final Future<void> Function(String retryTaskId) onCreated;

  @override
  ConsumerState<OutboundRetryAction> createState() =>
      _OutboundRetryActionState();
}

class _OutboundRetryActionState extends ConsumerState<OutboundRetryAction> {
  bool _dialogOpen = false;
  bool _deciding = false;
  String? _navigatedTaskId;
  Route<bool>? _dialog;

  bool get _eligible {
    final task = widget.task;
    return task.kind == DeliveryTaskKind.outbound &&
        task.status == DeliveryTaskStatus.failed &&
        task.attemptNumber == 1 &&
        (task.scope == DeliverySnapshotScope.restricted ||
            task.scope == DeliverySnapshotScope.current);
  }

  Future<void> _openConfirmation(OutboundRetryState state) async {
    if (!_eligible ||
        _dialogOpen ||
        _deciding ||
        state.busy ||
        state.actionsDenied ||
        state.confirmed ||
        ref.read(outboundResultGateProvider(widget.task.taskId)) != null) {
      return;
    }
    setState(() => _dialogOpen = true);
    final dialog = DialogRoute<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Giao lại lần 2'),
        content: const Text(
          'Bạn sẽ tiếp tục giữ hàng và giao lần 2, không cần chờ quản lý duyệt.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('outbound-retry-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Quay lại'),
          ),
          FilledButton(
            key: const ValueKey('outbound-retry-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xác nhận giao lại'),
          ),
        ],
      ),
    );
    _dialog = dialog;
    try {
      final result = await Navigator.of(context).push(dialog);
      _dialog = null;
      if (result != true || !mounted || _deciding) return;
      _deciding = true;
      final vm = ref.read(
        outboundRetryViewModelProvider(widget.task.taskId).notifier,
      );
      final retryTaskId = await vm.submit(task: widget.task);
      if (mounted && retryTaskId != null) {
        await _navigateOnce(retryTaskId);
      }
    } finally {
      _dialog = null;
      _deciding = false;
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  Future<void> _navigateOnce(String retryTaskId) async {
    if (_navigatedTaskId == retryTaskId) return;
    _navigatedTaskId = retryTaskId;
    if (!mounted) return;
    await widget.onCreated(retryTaskId);
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
    if (!_eligible) return const SizedBox.shrink();
    final provider = outboundRetryViewModelProvider(widget.task.taskId);
    ref.listen<OutboundRetryState>(provider, (_, next) {
      final retryTaskId = next.confirmed ? next.retryTaskId : null;
      if (retryTaskId != null && mounted) {
        unawaited(_navigateOnce(retryTaskId));
      }
    });
    final state = ref.watch(provider);
    final vm = ref.read(provider.notifier);
    final gate = ref.watch(outboundResultGateProvider(widget.task.taskId));
    final session = ref.watch(operationalSessionProvider);
    final sessionReady =
        session.asData?.value.userId != null &&
        session.asData?.value.failure == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.confirmed)
          const Text(
            'Đã tạo nhiệm vụ giao lại lần 2. Đang mở nhiệm vụ mới…',
            key: ValueKey('outbound-retry-confirmed'),
          ),
        if (state.busy)
          const Text(
            'Đang xác minh nhiệm vụ giao lại…',
            key: ValueKey('outbound-retry-loading'),
          ),
        if (state.error != null)
          Text(
            _errorText(state.error!),
            key: const ValueKey('outbound-retry-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (!state.confirmed &&
            !state.actionsDenied &&
            state.pendingCommand == null &&
            !state.requiresReadRetry)
          OutlinedButton(
            key: const ValueKey('outbound-retry-open'),
            onPressed: !sessionReady || _dialogOpen || _deciding || gate != null
                ? null
                : () => _openConfirmation(state),
            child: const Text('Giao lại lần 2'),
          ),
        if (state.pendingCommand != null || state.requiresReadRetry)
          TextButton(
            key: const ValueKey('outbound-retry-retry'),
            onPressed: state.busy || (gate != null && !identical(gate, vm))
                ? null
                : vm.retry,
            child: Text(
              state.pendingCommand != null
                  ? 'Thử lại cùng yêu cầu'
                  : 'Đọc lại nhiệm vụ giao lại',
            ),
          ),
      ],
    );
  }
}

String _errorText(OutboundCommandFailure failure) {
  if (failure is OutboundBusinessFailure) return failure.message;
  return switch (failure.code) {
    OutboundCommandFailureCode.timeout ||
    OutboundCommandFailureCode.network ||
    OutboundCommandFailureCode.unexpected =>
      'Chưa xác minh được kết quả. Thử lại cùng yêu cầu.',
    OutboundCommandFailureCode.dependencyUnavailable =>
      'Dịch vụ giao lại chưa sẵn sàng. Vui lòng thử lại.',
    OutboundCommandFailureCode.permissionDenied ||
    OutboundCommandFailureCode.staleAssignment ||
    OutboundCommandFailureCode.sessionExpired =>
      'Phiên làm việc hoặc quyền giao hàng đã thay đổi.',
    OutboundCommandFailureCode.invalidData =>
      'Dữ liệu giao lại không hợp lệ. Vui lòng đọc lại nhiệm vụ.',
    OutboundCommandFailureCode.staleState =>
      'Trạng thái nhiệm vụ đã thay đổi. Vui lòng đọc lại nhiệm vụ.',
  };
}
