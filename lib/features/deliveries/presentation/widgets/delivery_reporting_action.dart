import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/delivery_reporting.dart';
import '../../domain/models/outbound_task_command.dart';
import '../view_models/delivery_reporting_view_model.dart';
import '../view_models/outbound_result_gate.dart';

/// MH11's outbound handover/incident actions.
///
/// The reporting context is fetched separately from the task detail. This is
/// important for failed/cancelled outbound projections whose normal detail is
/// restricted but whose server-authorized reporting context is still usable.
class DeliveryReportingAction extends ConsumerStatefulWidget {
  const DeliveryReportingAction({
    super.key,
    required this.taskId,
    this.allowSubmit = true,
  });

  final String taskId;
  final bool allowSubmit;

  @override
  ConsumerState<DeliveryReportingAction> createState() =>
      _DeliveryReportingActionState();
}

class _DeliveryReportingActionState
    extends ConsumerState<DeliveryReportingAction> {
  Route<Object?>? _dialog;
  bool _dialogOpen = false;
  bool _deciding = false;

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

  Future<void> _openHandover(DeliveryReportingState state) async {
    if (!_canOpen(state)) return;
    final vm = ref.read(
      deliveryReportingViewModelProvider(widget.taskId).notifier,
    );
    final revision = vm.sessionRevisionForConfirmation;
    final snapshot = state.context.requireValue;
    setState(() => _dialogOpen = true);
    final route = DialogRoute<bool>(
      context: context,
      builder: (_) => _HandoverDialog(
        taskId: widget.taskId,
        revision: revision,
        snapshot: snapshot,
      ),
    );
    _dialog = route;
    try {
      final confirmed = await Navigator.of(context).push<bool>(route);
      _dialog = null;
      if (!mounted || confirmed != true || _deciding) return;
      final latest = ref.read(
        deliveryReportingViewModelProvider(widget.taskId),
      );
      if (!_sameContext(latest, snapshot) ||
          vm.sessionRevisionForConfirmation != revision ||
          !latest.canHandover ||
          ref.read(outboundResultGateProvider(widget.taskId)) != null) {
        return;
      }
      _deciding = true;
      await vm.submitHandover(sessionRevision: revision);
    } finally {
      _dialog = null;
      _deciding = false;
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  Future<void> _openIncident(DeliveryReportingState state) async {
    if (!_canOpen(state) || !state.canIncident) return;
    final vm = ref.read(
      deliveryReportingViewModelProvider(widget.taskId).notifier,
    );
    final revision = vm.sessionRevisionForConfirmation;
    final snapshot = state.context.requireValue;
    setState(() => _dialogOpen = true);
    final route = DialogRoute<_IncidentInput>(
      context: context,
      builder: (_) => _IncidentDialog(
        taskId: widget.taskId,
        revision: revision,
        snapshot: snapshot,
      ),
    );
    _dialog = route;
    try {
      final input = await Navigator.of(context).push<_IncidentInput>(route);
      _dialog = null;
      if (!mounted || input == null || _deciding) return;
      final latest = ref.read(
        deliveryReportingViewModelProvider(widget.taskId),
      );
      if (!_sameContext(latest, snapshot) ||
          vm.sessionRevisionForConfirmation != revision ||
          !latest.canIncident ||
          ref.read(outboundResultGateProvider(widget.taskId)) != null) {
        return;
      }
      _deciding = true;
      await vm.submitIncident(
        kind: input.kind,
        reason: input.reason,
        sessionRevision: revision,
      );
    } finally {
      _dialog = null;
      _deciding = false;
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  bool _canOpen(DeliveryReportingState state) {
    final gate = ref.read(outboundResultGateProvider(widget.taskId));
    return widget.allowSubmit &&
        !_dialogOpen &&
        !_deciding &&
        gate == null &&
        state.context.hasValue &&
        !state.busy &&
        !state.actionsDenied &&
        !state.requiresReadRetry &&
        !state.awaitingAuthoritativeRead &&
        state.pendingCommand == null;
  }

  static bool _sameContext(
    DeliveryReportingState state,
    ReportingContext snapshot,
  ) => state.context.hasValue && state.context.requireValue == snapshot;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deliveryReportingViewModelProvider(widget.taskId));
    final gate = ref.watch(outboundResultGateProvider(widget.taskId));
    final vm = ref.read(
      deliveryReportingViewModelProvider(widget.taskId).notifier,
    );
    final scheme = Theme.of(context).colorScheme;
    final contextValue = state.context.asData?.value;
    final hasServerContext = contextValue != null;
    final reportError = state.error;
    final canOpen = _canOpen(state) && gate == null;

    return Column(
      key: const ValueKey('delivery-reporting-action'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.context.isLoading && !hasServerContext)
          const Text(
            'Đang đọc quyền báo cáo…',
            key: ValueKey('reporting-loading'),
          ),
        if (state.context.hasError && !hasServerContext)
          Text(
            _reportingErrorText(reportError),
            key: const ValueKey('reporting-error'),
            style: TextStyle(color: scheme.error),
          ),
        if (state.acknowledgement != null)
          Text(
            state.acknowledgement!.operation ==
                    ReportingOperation.handover.rpcName
                ? 'Đã gửi báo cáo bàn giao cho cửa hàng. Đây chưa phải xác nhận cửa hàng đã nhận, kiểm tra hoặc nhập lại tồn kho.'
                : 'Đã gửi báo cáo sự cố; chủ cửa hàng đã được thông báo. Báo cáo này không thay thế báo giao thất bại.',
            key: const ValueKey('reporting-ack'),
          ),
        if (state.handoverReported)
          const Text(
            'Đã gửi báo cáo bàn giao cho cửa hàng. Chờ cửa hàng nhận và kiểm tra riêng.',
            key: ValueKey('reporting-handover-reported'),
          ),
        if (hasServerContext &&
            !state.handoverReported &&
            state.handoverBlockReason != null &&
            !state.canHandover)
          _BlockReason(
            key: const ValueKey('reporting-handover-blocked'),
            label: 'Chưa thể báo bàn giao',
            reason: state.handoverBlockReason!,
          ),
        if (hasServerContext && state.canHandover && widget.allowSubmit)
          FilledButton.icon(
            key: const ValueKey('reporting-handover-open'),
            onPressed: canOpen ? () => _openHandover(state) : null,
            icon: const Icon(Icons.inventory_outlined),
            label: const Text('Báo bàn giao cửa hàng'),
          ),
        if (hasServerContext &&
            !state.canIncident &&
            state.incidentBlockReason != null)
          _BlockReason(
            key: const ValueKey('reporting-incident-blocked'),
            label: 'Chưa thể báo sự cố',
            reason: state.incidentBlockReason!,
          ),
        if (hasServerContext && state.canIncident && widget.allowSubmit)
          OutlinedButton.icon(
            key: const ValueKey('reporting-incident-open'),
            onPressed: canOpen ? () => _openIncident(state) : null,
            icon: const Icon(Icons.report_problem_outlined),
            label: const Text('Báo sự cố hàng hóa'),
          ),
        if (state.busy)
          const Text(
            'Đang gửi và đọc lại dữ liệu từ server…',
            key: ValueKey('reporting-busy'),
          ),
        if (reportError != null && !state.context.hasError)
          Text(
            _reportingErrorText(reportError),
            key: const ValueKey('reporting-error'),
            style: TextStyle(color: scheme.error),
          ),
        if (state.pendingCommand != null || state.requiresReadRetry)
          OutlinedButton(
            key: const ValueKey('reporting-retry'),
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

class _BlockReason extends StatelessWidget {
  const _BlockReason({super.key, required this.label, required this.reason});

  final String label;
  final String reason;

  @override
  Widget build(BuildContext context) =>
      Text('$label: ${_safeBlockReason(reason)}');
}

class _HandoverDialog extends ConsumerStatefulWidget {
  const _HandoverDialog({
    required this.taskId,
    required this.revision,
    required this.snapshot,
  });

  final String taskId;
  final int revision;
  final ReportingContext snapshot;

  @override
  ConsumerState<_HandoverDialog> createState() => _HandoverDialogState();
}

class _HandoverDialogState extends ConsumerState<_HandoverDialog> {
  var _confirmed = false;
  var _closed = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deliveryReportingViewModelProvider(widget.taskId));
    final vm = ref.read(
      deliveryReportingViewModelProvider(widget.taskId).notifier,
    );
    ref.watch(outboundResultGateProvider(widget.taskId));
    final stale =
        vm.sessionRevisionForConfirmation != widget.revision ||
        !_sameSnapshot(state, widget.snapshot) ||
        !state.canHandover ||
        ref.read(outboundResultGateProvider(widget.taskId)) != null;
    if (stale && !_closed) {
      _closed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(false);
      });
    }
    if (_closed) return const SizedBox.shrink();
    return AlertDialog(
      title: const Text('Báo bàn giao cửa hàng'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chỉ xác nhận khi bạn đã bàn giao đủ toàn bộ hàng cho cửa hàng. Báo cáo chỉ ghi nhận thông báo của shipper; không phải xác nhận nhận hàng của chủ cửa hàng, kiểm tra chất lượng hoặc nhập lại tồn kho của quản lý.',
            ),
            const SizedBox(height: 12),
            for (final item in widget.snapshot.items) ...[
              _ReportItemLine(item: item),
              const SizedBox(height: 8),
            ],
            CheckboxListTile(
              key: const ValueKey('reporting-handover-confirmation'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _confirmed,
              onChanged: (value) => setState(() => _confirmed = value ?? false),
              title: const Text('Tôi đã bàn giao đủ toàn bộ hàng'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('reporting-handover-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Quay lại'),
        ),
        FilledButton(
          key: const ValueKey('reporting-handover-confirm'),
          onPressed: _confirmed ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Gửi báo cáo bàn giao'),
        ),
      ],
    );
  }

  static bool _sameSnapshot(
    DeliveryReportingState state,
    ReportingContext snapshot,
  ) => state.context.hasValue && state.context.requireValue == snapshot;
}

class _ReportItemLine extends StatelessWidget {
  const _ReportItemLine({required this.item});

  final ReportItem item;

  @override
  Widget build(BuildContext context) => Text(
    '${item.productName}${item.variantLabel == null ? '' : ' – ${item.variantLabel}'} · Số lượng: ${item.quantity}',
  );
}

class _IncidentInput {
  const _IncidentInput({required this.kind, required this.reason});

  final ReportingIncidentKind kind;
  final String reason;
}

class _IncidentDialog extends ConsumerStatefulWidget {
  const _IncidentDialog({
    required this.taskId,
    required this.revision,
    required this.snapshot,
  });

  final String taskId;
  final int revision;
  final ReportingContext snapshot;

  @override
  ConsumerState<_IncidentDialog> createState() => _IncidentDialogState();
}

class _IncidentDialogState extends ConsumerState<_IncidentDialog> {
  final _reason = TextEditingController();
  ReportingIncidentKind? _kind;
  var _closed = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deliveryReportingViewModelProvider(widget.taskId));
    final vm = ref.read(
      deliveryReportingViewModelProvider(widget.taskId).notifier,
    );
    ref.watch(outboundResultGateProvider(widget.taskId));
    final stale =
        vm.sessionRevisionForConfirmation != widget.revision ||
        !_sameSnapshot(state, widget.snapshot) ||
        !state.canIncident ||
        ref.read(outboundResultGateProvider(widget.taskId)) != null;
    if (stale && !_closed) {
      _closed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
    if (_closed) return const SizedBox.shrink();
    final valid = _kind != null && _reason.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('Báo sự cố hàng hóa'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chọn loại sự cố và mô tả rõ nguyên nhân. Chủ cửa hàng sẽ được thông báo; thao tác này không ghi nhận báo giao thất bại, không xác nhận nhận hàng và không tự nhập lại tồn kho.',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ReportingIncidentKind>(
              key: const ValueKey('reporting-incident-kind'),
              initialValue: _kind,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Loại sự cố'),
              items: const [
                DropdownMenuItem(
                  value: ReportingIncidentKind.damaged,
                  child: Text('Hàng bị hỏng'),
                ),
                DropdownMenuItem(
                  value: ReportingIncidentKind.lost,
                  child: Text('Hàng bị mất'),
                ),
                DropdownMenuItem(
                  value: ReportingIncidentKind.other,
                  child: Text('Sự cố khác'),
                ),
              ],
              onChanged: (kind) => setState(() => _kind = kind),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('reporting-incident-reason'),
              controller: _reason,
              minLines: 3,
              maxLines: 5,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Lý do (bắt buộc)',
                hintText: 'Mô tả sự cố, không chỉ nhập khoảng trắng',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('reporting-incident-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Quay lại'),
        ),
        FilledButton(
          key: const ValueKey('reporting-incident-confirm'),
          onPressed: valid
              ? () => Navigator.of(
                  context,
                ).pop(_IncidentInput(kind: _kind!, reason: _reason.text.trim()))
              : null,
          child: const Text('Gửi báo cáo sự cố'),
        ),
      ],
    );
  }

  static bool _sameSnapshot(
    DeliveryReportingState state,
    ReportingContext snapshot,
  ) => state.context.hasValue && state.context.requireValue == snapshot;
}

String _reportingErrorText(OutboundCommandFailure? failure) {
  if (failure == null) return 'Không thể tải dữ liệu báo cáo.';
  if (failure is OutboundBusinessFailure) return failure.message;
  return switch (failure.code) {
    OutboundCommandFailureCode.timeout ||
    OutboundCommandFailureCode.network ||
    OutboundCommandFailureCode.unexpected =>
      'Chưa xác minh được kết quả. Thử lại cùng yêu cầu đang giữ.',
    OutboundCommandFailureCode.dependencyUnavailable =>
      'Dịch vụ báo cáo chưa sẵn sàng. Vui lòng thử lại.',
    OutboundCommandFailureCode.permissionDenied ||
    OutboundCommandFailureCode.staleAssignment ||
    OutboundCommandFailureCode.sessionExpired =>
      'Phiên làm việc hoặc quyền giao hàng đã thay đổi.',
    OutboundCommandFailureCode.invalidData =>
      'Dữ liệu báo cáo không hợp lệ. Vui lòng đọc lại nhiệm vụ.',
    OutboundCommandFailureCode.staleState =>
      'Trạng thái nhiệm vụ đã thay đổi. Vui lòng đọc lại dữ liệu.',
  };
}

String _safeBlockReason(String reason) {
  final normalized = reason.trim().toUpperCase();
  return switch (normalized) {
    'STATE_CONFLICT' => 'Trạng thái nhiệm vụ không còn phù hợp.',
    'CUSTODY_UNRESOLVED' => 'Chưa xác minh đủ người giữ hàng.',
    'ITEMS_MISMATCH' => 'Số lượng hàng chưa khớp bằng chứng của server.',
    'UNSUPPORTED_TASK_KIND' => 'Loại nhiệm vụ này chưa hỗ trợ báo cáo.',
    'PERMISSION_DENIED' ||
    'NOT_FOUND_OR_FORBIDDEN' => 'Bạn không còn quyền báo cáo nhiệm vụ này.',
    _ when RegExp(r'^[A-Z0-9_]+$').hasMatch(normalized) =>
      'Thao tác chưa được server cho phép ở trạng thái hiện tại.',
    _ => reason,
  };
}

/// Alias for an outbound-specific call site.
typedef OutboundDeliveryReportingAction = DeliveryReportingAction;
