import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/delivery_task.dart';
import '../../domain/models/delivery_task_details.dart';
import '../../domain/models/outbound_failure_command.dart';
import '../../domain/models/outbound_task_command.dart';
import '../../domain/models/return_pickup_command.dart';
import '../view_models/outbound_result_gate.dart';
import '../view_models/return_pickup_view_model.dart';

const _reasonLabels = <OutboundFailureReason, String>{
  OutboundFailureReason.unreachable: 'Không liên hệ được',
  OutboundFailureReason.reschedule: 'Khách hẹn lại',
  OutboundFailureReason.badAddress: 'Sai địa chỉ',
  OutboundFailureReason.refusal: 'Khách từ chối bàn giao/trả hàng',
  OutboundFailureReason.other: 'Khác',
};

/// MH11 pickup actions.  Collection is exact-full and combines accepted/start
/// on the server; there is no separate accept/start button and no quantity
/// editor in this widget.
class ReturnPickupAction extends ConsumerStatefulWidget {
  const ReturnPickupAction({
    super.key,
    required this.taskId,
    this.allowSubmit = true,
  });

  final String taskId;
  final bool allowSubmit;

  @override
  ConsumerState<ReturnPickupAction> createState() => _ReturnPickupActionState();
}

class _ReturnPickupActionState extends ConsumerState<ReturnPickupAction> {
  Route<_PickupFailureInput>? _failureRoute;
  Route<bool>? _collectRoute;
  Route<bool>? _handoverRoute;
  var _dialogOpen = false;
  var _deciding = false;

  Future<void> _openCollect(ReturnPickupState state) async {
    if (_dialogOpen || !state.canCollect || !state.details.hasValue) return;
    if (ref.read(outboundResultGateProvider(widget.taskId)) != null) return;
    final vm = ref.read(returnPickupViewModelProvider(widget.taskId).notifier);
    final revision = vm.sessionRevisionForConfirmation;
    final details = state.details.requireValue;
    final snapshot = details.task;
    final items = List<DeliveryTaskItem>.unmodifiable(details.items);
    setState(() => _dialogOpen = true);
    final route = DialogRoute<bool>(
      context: context,
      builder: (_) => _PickupCollectDialog(
        taskId: widget.taskId,
        snapshot: snapshot,
        items: items,
        revision: revision,
      ),
    );
    _collectRoute = route;
    try {
      final result = await Navigator.of(context).push<bool>(route);
      _collectRoute = null;
      if (!mounted || result != true || _deciding) return;
      _deciding = true;
      final latest = ref.read(returnPickupViewModelProvider(widget.taskId));
      if (!latest.canCollect ||
          !latest.details.hasValue ||
          latest.details.requireValue.task != snapshot ||
          !_sameItems(latest.details.requireValue.items, items) ||
          vm.sessionRevisionForConfirmation != revision) {
        return;
      }
      await vm.submitCollect(
        expectedTask: snapshot,
        expectedItems: items,
        sessionRevision: revision,
      );
    } finally {
      _collectRoute = null;
      _deciding = false;
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  Future<void> _openFailure(ReturnPickupState state) async {
    if (_dialogOpen || !state.canFail || !state.details.hasValue) return;
    if (ref.read(outboundResultGateProvider(widget.taskId)) != null) return;
    final vm = ref.read(returnPickupViewModelProvider(widget.taskId).notifier);
    final revision = vm.sessionRevisionForConfirmation;
    final snapshot = state.details.requireValue.task;
    setState(() => _dialogOpen = true);
    final route = DialogRoute<_PickupFailureInput>(
      context: context,
      builder: (_) => _PickupFailureDialog(
        taskId: widget.taskId,
        snapshot: snapshot,
        revision: revision,
      ),
    );
    _failureRoute = route;
    try {
      final input = await Navigator.of(context).push(route);
      _failureRoute = null;
      if (!mounted || input == null || _deciding) return;
      _deciding = true;
      final latest = ref.read(returnPickupViewModelProvider(widget.taskId));
      if (!latest.canFail ||
          !latest.details.hasValue ||
          latest.details.requireValue.task != snapshot ||
          vm.sessionRevisionForConfirmation != revision) {
        return;
      }
      await vm.submitFailure(
        reason: input.reason,
        description: input.description,
        expectedTask: snapshot,
        sessionRevision: revision,
      );
    } finally {
      _failureRoute = null;
      _deciding = false;
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  Future<void> _openHandover(ReturnPickupState state) async {
    if (_dialogOpen ||
        !state.canReportStoreHandover ||
        !state.details.hasValue) {
      return;
    }
    if (ref.read(outboundResultGateProvider(widget.taskId)) != null) return;
    final vm = ref.read(returnPickupViewModelProvider(widget.taskId).notifier);
    final revision = vm.sessionRevisionForConfirmation;
    final details = state.details.requireValue;
    final snapshot = details.task;
    final items = List<DeliveryTaskItem>.unmodifiable(details.items);
    setState(() => _dialogOpen = true);
    final route = DialogRoute<bool>(
      context: context,
      builder: (_) => _PickupHandoverDialog(
        taskId: widget.taskId,
        snapshot: snapshot,
        items: items,
        revision: revision,
      ),
    );
    _handoverRoute = route;
    try {
      final result = await Navigator.of(context).push<bool>(route);
      _handoverRoute = null;
      if (!mounted || result != true || _deciding) return;
      _deciding = true;
      final latest = ref.read(returnPickupViewModelProvider(widget.taskId));
      if (!latest.canReportStoreHandover ||
          !latest.details.hasValue ||
          latest.details.requireValue.task != snapshot ||
          !_sameItems(latest.details.requireValue.items, items) ||
          vm.sessionRevisionForConfirmation != revision) {
        return;
      }
      await vm.submitHandover(
        expectedTask: snapshot,
        expectedItems: items,
        sessionRevision: revision,
      );
    } finally {
      _handoverRoute = null;
      _deciding = false;
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  @override
  void dispose() {
    final routes = <Route<dynamic>>[
      ...?_collectRoute == null ? null : <Route<dynamic>>[_collectRoute!],
      ...?_failureRoute == null ? null : <Route<dynamic>>[_failureRoute!],
      ...?_handoverRoute == null ? null : <Route<dynamic>>[_handoverRoute!],
    ];
    for (final route in routes) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(returnPickupViewModelProvider(widget.taskId));
    final gate = ref.watch(outboundResultGateProvider(widget.taskId));
    final vm = ref.read(returnPickupViewModelProvider(widget.taskId).notifier);
    final task = state.details.hasValue
        ? state.details.requireValue.task
        : null;
    final isPickup = task?.kind == DeliveryTaskKind.returnPickup;
    final canOpen = widget.allowSubmit && gate == null && !_dialogOpen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.confirmed &&
            state.confirmedOperation == ReturnPickupOperation.collect)
          const Text(
            'Đã ghi nhận đủ hàng tại khách; hàng đang được hoàn về cửa hàng.',
            key: ValueKey('pickup-collect-confirmed'),
          ),
        if (state.confirmed &&
            state.confirmedOperation == ReturnPickupOperation.fail)
          const Text(
            'Đã ghi nhận lấy hàng thất bại. Yêu cầu vẫn chờ quản lý xử lý.',
            key: ValueKey('pickup-failure-confirmed'),
          ),
        if (state.confirmed &&
            state.confirmedOperation == ReturnPickupOperation.handover)
          const Text(
            'Đã báo bàn giao cho cửa hàng; chờ cửa hàng nhận và kiểm tra.',
            key: ValueKey('pickup-handover-confirmed'),
          ),
        if (state.busy) const Text('Đang gửi và đọc lại trạng thái nhiệm vụ…'),
        if (state.error != null)
          Text(
            _errorText(state.error!),
            key: const ValueKey('pickup-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (isPickup &&
            task!.status == DeliveryTaskStatus.inTransit &&
            state.details.hasValue &&
            _canShowInTransit(state.details.requireValue)) ...[
          const Text(
            'Đã nhận tại khách, đang hoàn về; cửa hàng chưa xác nhận nhận/kiểm tra.',
            key: ValueKey('pickup-in-transit-message'),
          ),
          const SizedBox(height: 8),
          if (state.handoverReported)
            const Text(
              'Đã ghi nhận báo bàn giao; cửa hàng chưa xác nhận nhận/kiểm tra.',
              key: ValueKey('pickup-handover-reported'),
            )
          else if (widget.allowSubmit && state.canReportStoreHandover)
            FilledButton(
              key: const ValueKey('pickup-handover-open'),
              onPressed: canOpen ? () => _openHandover(state) : null,
              child: const Text('Báo bàn giao cửa hàng'),
            )
          else ...[
            OutlinedButton(
              key: const ValueKey('pickup-handover-disabled'),
              onPressed: null,
              child: const Text('Báo bàn giao cửa hàng'),
            ),
            Text(
              'Báo bàn giao chưa khả dụng. Liên hệ chủ cửa hàng; việc nhận và kiểm tra được xác nhận riêng.',
              key: const ValueKey('pickup-handover-unavailable'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (state.handoverStatus.hasError)
              OutlinedButton(
                key: const ValueKey('pickup-handover-retry'),
                onPressed: state.busy || gate != null
                    ? null
                    : vm.retryHandoverStatus,
                child: const Text('Đọc lại trạng thái bàn giao'),
              ),
          ],
        ],
        if (widget.allowSubmit && state.canCollect) ...[
          const SizedBox(height: 8),
          FilledButton(
            key: const ValueKey('pickup-collect-open'),
            onPressed: canOpen ? () => _openCollect(state) : null,
            child: const Text('Xác nhận đã nhận đủ hàng'),
          ),
        ],
        if (widget.allowSubmit && state.canFail) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            key: const ValueKey('pickup-failure-open'),
            onPressed: canOpen ? () => _openFailure(state) : null,
            child: const Text('Báo lấy hàng thất bại'),
          ),
        ],
        if (state.pendingCommand != null || state.requiresReadRetry)
          OutlinedButton(
            key: const ValueKey('pickup-retry'),
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

String _errorText(OutboundCommandFailure failure) {
  if (failure is OutboundBusinessFailure) return failure.message;
  return switch (failure.code) {
    OutboundCommandFailureCode.permissionDenied ||
    OutboundCommandFailureCode.staleAssignment ||
    OutboundCommandFailureCode.sessionExpired =>
      'Phiên làm việc hoặc quyền giao hàng đã thay đổi.',
    OutboundCommandFailureCode.staleState =>
      'Trạng thái nhiệm vụ đã thay đổi. Vui lòng đọc lại.',
    OutboundCommandFailureCode.invalidData => 'Dữ liệu xác nhận không hợp lệ.',
    OutboundCommandFailureCode.timeout ||
    OutboundCommandFailureCode.network ||
    OutboundCommandFailureCode.dependencyUnavailable ||
    OutboundCommandFailureCode.unexpected =>
      'Chưa xác minh được kết quả. Vui lòng thử lại cùng yêu cầu.',
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

bool _canShowInTransit(DeliveryTaskDetails details) {
  final task = details.task;
  if (task.kind != DeliveryTaskKind.returnPickup ||
      task.scope != DeliverySnapshotScope.current ||
      task.status != DeliveryTaskStatus.inTransit ||
      task.amountToCollectVnd != 0 ||
      task.orderId == null ||
      task.returnRequestId == null ||
      !_isUuid(task.taskId) ||
      !_isUuid(task.orderId!) ||
      !_isUuid(task.returnRequestId!) ||
      task.assignedAt == null ||
      task.acceptedAt == null ||
      task.startedAt == null ||
      task.acceptedAt != task.startedAt ||
      details.items.isEmpty) {
    return false;
  }
  return details.items.every(
    (item) =>
        item.itemSource == DeliveryItemSource.returnPlan &&
        _isUuid(item.itemId) &&
        item.quantity > 0 &&
        item.quantity <= 2147483647 &&
        item.quantityCollected == item.quantity,
  );
}

bool _isUuid(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
).hasMatch(value);

class _PickupCollectDialog extends ConsumerStatefulWidget {
  const _PickupCollectDialog({
    required this.taskId,
    required this.snapshot,
    required this.items,
    required this.revision,
  });

  final String taskId;
  final DeliveryTaskSnapshot snapshot;
  final List<DeliveryTaskItem> items;
  final int revision;

  @override
  ConsumerState<_PickupCollectDialog> createState() =>
      _PickupCollectDialogState();
}

class _PickupCollectDialogState extends ConsumerState<_PickupCollectDialog> {
  var _receivedAll = false;
  var _closed = false;

  void _decide(bool value) {
    if (_closed) return;
    _closed = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(returnPickupViewModelProvider(widget.taskId));
    final vm = ref.read(returnPickupViewModelProvider(widget.taskId).notifier);
    final gate = ref.watch(outboundResultGateProvider(widget.taskId));
    final stale =
        vm.sessionRevisionForConfirmation != widget.revision ||
        gate != null ||
        !state.canCollect ||
        !state.details.hasValue ||
        state.details.requireValue.task != widget.snapshot ||
        !_sameItems(state.details.requireValue.items, widget.items);
    if (stale && !_closed) {
      _closed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(false);
      });
    }
    if (_closed) return const SizedBox.shrink();
    return AlertDialog(
      title: const Text('Xác nhận lấy đủ hàng'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Chỉ xác nhận khi đã nhận đủ mọi món và đúng số lượng theo kế hoạch. Không thể sửa số lượng tại bước này.',
            ),
            const SizedBox(height: 12),
            for (final item in widget.items) ...[
              _PickupPlanItem(item: item),
              if (item != widget.items.last) const Divider(height: 20),
            ],
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const ValueKey('pickup-collect-all'),
              contentPadding: EdgeInsets.zero,
              value: _receivedAll,
              onChanged: (value) =>
                  setState(() => _receivedAll = value ?? false),
              title: const Text('Đã nhận đủ toàn bộ danh sách trên'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('pickup-collect-cancel'),
          onPressed: () => _decide(false),
          child: const Text('Quay lại'),
        ),
        FilledButton(
          key: const ValueKey('pickup-collect-confirm'),
          onPressed: _receivedAll ? () => _decide(true) : null,
          child: const Text('Xác nhận'),
        ),
      ],
    );
  }
}

class _PickupPlanItem extends StatelessWidget {
  const _PickupPlanItem({required this.item});

  final DeliveryTaskItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.inventory_2_outlined, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${item.productName}\nSố lượng: ${item.quantity}',
            key: ValueKey('pickup-plan-${item.itemId}'),
          ),
        ),
      ],
    );
  }
}

/// Confirmation for reporting store handover. The shipper attests the same
/// full item plan already collected; no store receipt, inspection or refund is
/// implied by this action.
class _PickupHandoverDialog extends ConsumerStatefulWidget {
  const _PickupHandoverDialog({
    required this.taskId,
    required this.snapshot,
    required this.items,
    required this.revision,
  });

  final String taskId;
  final DeliveryTaskSnapshot snapshot;
  final List<DeliveryTaskItem> items;
  final int revision;

  @override
  ConsumerState<_PickupHandoverDialog> createState() =>
      _PickupHandoverDialogState();
}

class _PickupHandoverDialogState extends ConsumerState<_PickupHandoverDialog> {
  var _receivedAll = false;
  var _closed = false;

  void _decide(bool value) {
    if (_closed) return;
    _closed = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(returnPickupViewModelProvider(widget.taskId));
    final vm = ref.read(returnPickupViewModelProvider(widget.taskId).notifier);
    final gate = ref.watch(outboundResultGateProvider(widget.taskId));
    final stale =
        vm.sessionRevisionForConfirmation != widget.revision ||
        gate != null ||
        !state.canReportStoreHandover ||
        !state.details.hasValue ||
        state.details.requireValue.task != widget.snapshot ||
        !_sameItems(state.details.requireValue.items, widget.items);
    if (stale && !_closed) {
      _closed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(false);
      });
    }
    if (_closed) return const SizedBox.shrink();
    return AlertDialog(
      title: const Text('Xác nhận báo bàn giao'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Chỉ xác nhận khi đã bàn giao đủ mọi món và đúng số lượng cho cửa hàng. Thao tác này chỉ ghi nhận bàn giao, không xác nhận cửa hàng đã nhận hoặc kiểm tra hàng.',
            ),
            const SizedBox(height: 12),
            for (final item in widget.items) ...[
              _PickupPlanItem(item: item),
              if (item != widget.items.last) const Divider(height: 20),
            ],
            const SizedBox(height: 8),
            KeyedSubtree(
              key: const ValueKey('pickup-handover-confirmation'),
              child: CheckboxListTile(
                key: const ValueKey('pickup-handover-all'),
                contentPadding: EdgeInsets.zero,
                value: _receivedAll,
                onChanged: (value) =>
                    setState(() => _receivedAll = value ?? false),
                title: const Text('Đã bàn giao đủ toàn bộ danh sách trên'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('pickup-handover-cancel'),
          onPressed: () => _decide(false),
          child: const Text('Quay lại'),
        ),
        FilledButton(
          key: const ValueKey('pickup-handover-confirm'),
          onPressed: _receivedAll ? () => _decide(true) : null,
          child: const Text('Xác nhận bàn giao'),
        ),
      ],
    );
  }
}

class _PickupFailureInput {
  const _PickupFailureInput(this.reason, this.description);

  final OutboundFailureReason reason;
  final String? description;
}

class _PickupFailureDialog extends ConsumerStatefulWidget {
  const _PickupFailureDialog({
    required this.taskId,
    required this.snapshot,
    required this.revision,
  });

  final String taskId;
  final DeliveryTaskSnapshot snapshot;
  final int revision;

  @override
  ConsumerState<_PickupFailureDialog> createState() =>
      _PickupFailureDialogState();
}

class _PickupFailureDialogState extends ConsumerState<_PickupFailureDialog> {
  final _description = TextEditingController();
  OutboundFailureReason? _reason;
  var _closed = false;

  void _decide(_PickupFailureInput? value) {
    if (_closed) return;
    _closed = true;
    Navigator.of(context).pop(value);
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(returnPickupViewModelProvider(widget.taskId));
    final vm = ref.read(returnPickupViewModelProvider(widget.taskId).notifier);
    final gate = ref.watch(outboundResultGateProvider(widget.taskId));
    final stale =
        vm.sessionRevisionForConfirmation != widget.revision ||
        gate != null ||
        !state.canFail ||
        !state.details.hasValue ||
        state.details.requireValue.task != widget.snapshot;
    if (stale && !_closed) {
      _closed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
    if (_closed) return const SizedBox.shrink();
    final valid =
        _reason != null &&
        (_reason != OutboundFailureReason.other ||
            _description.text.trim().isNotEmpty);
    return AlertDialog(
      title: const Text('Báo lấy hàng thất bại'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Chỉ báo thất bại trước khi nhận hàng. Yêu cầu sẽ vẫn chờ quản lý quyết định.',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<OutboundFailureReason>(
              key: const ValueKey('pickup-failure-reason'),
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
              key: const ValueKey('pickup-failure-description'),
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
          key: const ValueKey('pickup-failure-cancel'),
          onPressed: () => _decide(null),
          child: const Text('Quay lại'),
        ),
        FilledButton(
          key: const ValueKey('pickup-failure-confirm'),
          onPressed: valid
              ? () => _decide(
                  _PickupFailureInput(_reason!, _description.text.trim()),
                )
              : null,
          child: const Text('Xác nhận thất bại'),
        ),
      ],
    );
  }
}
