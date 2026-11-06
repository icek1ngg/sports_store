// P07.3 TEST-ONLY layout. Never imported by runtime MH11 or a router.
import 'package:flutter/material.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';

const fixtureFailureReasons = <String, String>{
  'unreachable': 'Không liên hệ được',
  'reschedule': 'Khách hẹn lại',
  'bad_address': 'Sai địa chỉ',
  'refusal': 'Từ chối nhận',
  'other': 'Khác',
};

class FailurePanelFixture extends StatefulWidget {
  const FailurePanelFixture({
    super.key,
    required this.details,
    required this.eligible,
    required this.busy,
    required this.sessionRevision,
    required this.onConfirmed,
    this.errorMessage,
    this.onRetry,
    this.retryLabel = 'Thử lại cùng yêu cầu',
    this.resultLabel,
  });

  final DeliveryTaskDetails? details;
  final bool eligible;
  final bool busy;
  final Object sessionRevision;
  final Future<void> Function(String reason, String? description) onConfirmed;
  final String? errorMessage;
  final Future<void> Function()? onRetry;
  final String retryLabel;
  final String? resultLabel;

  @override
  State<FailurePanelFixture> createState() => _FailurePanelFixtureState();
}

class _FailurePanelFixtureState extends State<FailurePanelFixture> {
  DialogRoute<bool>? _route;
  bool _submitting = false;

  bool get _canOpen {
    final task = widget.details?.task;
    return widget.eligible &&
        !widget.busy &&
        !_submitting &&
        task?.scope == DeliverySnapshotScope.current &&
        task?.kind == DeliveryTaskKind.outbound &&
        task?.status == DeliveryTaskStatus.inTransit &&
        (task?.attemptNumber == 1 || task?.attemptNumber == 2) &&
        task?.acceptedAt != null &&
        task?.startedAt != null;
  }

  @override
  void didUpdateWidget(covariant FailurePanelFixture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionRevision != widget.sessionRevision ||
        oldWidget.details?.task != widget.details?.task ||
        !_canOpen) {
      _closeDialog();
    }
  }

  void _closeDialog() {
    final route = _route;
    _route = null;
    if (route == null) return;
    // Called during rebuild/disposal: only touch Navigator after that frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route.isActive) route.navigator?.removeRoute(route);
    });
  }

  @override
  void dispose() {
    _closeDialog();
    super.dispose();
  }

  Future<void> _open() async {
    if (!_canOpen || _route != null) return;
    final revision = widget.sessionRevision;
    final openedTask = widget.details!.task;
    final callback = widget.onConfirmed;
    String? reason;
    final description = TextEditingController();
    var showValidation = false;
    var decisionTaken = false;
    late final DialogRoute<bool> route;
    route = DialogRoute<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          // A stale account/task cannot keep the dialog's draft visible.
          if (!mounted ||
              widget.sessionRevision != revision ||
              widget.details?.task != openedTask ||
              !_canOpen) {
            return const SizedBox.shrink();
          }
          final needsDescription = reason == 'other';
          final valid =
              reason != null &&
              (!needsDescription || description.text.trim().isNotEmpty);
          return AlertDialog(
            title: const Text('Báo giao thất bại'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Chọn lý do giao không thành công.'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('failure-reason'),
                    isExpanded: true,
                    initialValue: reason,
                    decoration: const InputDecoration(labelText: 'Lý do'),
                    items: fixtureFailureReasons.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(() {
                      reason = value;
                      showValidation = false;
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('failure-description'),
                    controller: description,
                    minLines: 2,
                    maxLines: 4,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: needsDescription
                          ? 'Mô tả bắt buộc'
                          : 'Mô tả (tùy chọn)',
                      errorText: showValidation && !valid
                          ? 'Chọn lý do và nhập mô tả khi chọn Khác.'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Báo thất bại không xác nhận thu COD hoặc cửa hàng đã nhận hàng. Quyết định tiếp theo thuộc quản lý.',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                key: const ValueKey('failure-cancel'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Quay lại'),
              ),
              FilledButton(
                key: const ValueKey('failure-confirm'),
                onPressed: () {
                  if (decisionTaken) return;
                  if (!valid) {
                    setDialogState(() => showValidation = true);
                    return;
                  }
                  decisionTaken = true;
                  Navigator.of(dialogContext).pop(true);
                },
                child: const Text('Xác nhận thất bại'),
              ),
            ],
          );
        },
      ),
    );
    _route = route;
    try {
      final confirmed = await Navigator.of(context).push(route);
      _route = null;
      if (confirmed != true ||
          !mounted ||
          revision != widget.sessionRevision ||
          widget.details?.task != openedTask ||
          !_canOpen) {
        return;
      }
      final frozenDescription = description.text.trim();
      setState(() => _submitting = true);
      try {
        await callback(
          reason!,
          frozenDescription.isEmpty ? null : frozenDescription,
        );
      } finally {
        if (mounted) setState(() => _submitting = false);
      }
    } finally {
      // The closing route may still animate with the controller attached.
      await route.completed;
      description.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('P07.3 — TEST FIXTURE, chưa nối API live'),
      if (widget.resultLabel != null)
        Text(widget.resultLabel!, key: const ValueKey('failure-result')),
      if (_canOpen)
        FilledButton(
          key: const ValueKey('failure-open'),
          onPressed: _open,
          child: const Text('Báo giao thất bại'),
        ),
      if (widget.busy || _submitting) const LinearProgressIndicator(),
      if (widget.errorMessage != null)
        Text(widget.errorMessage!, key: const ValueKey('failure-error')),
      if (widget.onRetry != null)
        TextButton(
          key: const ValueKey('failure-retry'),
          onPressed: widget.busy || _submitting ? null : widget.onRetry,
          child: Text(widget.retryLabel),
        ),
    ],
  );
}
