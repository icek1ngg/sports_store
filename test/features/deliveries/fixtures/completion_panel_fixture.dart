// P05.2 TEST-ONLY. Not a routable MH11 page and never imported by production.
import 'package:flutter/material.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/repositories/delivery_phone_dialer.dart';

typedef ConfirmCompletionFixture = Future<void> Function({
  required bool receivedAllItems,
  required bool receivedFullCod,
  required int displayedAmountVnd,
});

class CompletionPanelFixture extends StatefulWidget {
  const CompletionPanelFixture({
    super.key,
    required this.details,
    required this.canComplete,
    required this.busy,
    required this.onConfirmed,
    this.errorMessage,
    this.onRetry,
    this.retryLabel = 'Thử lại yêu cầu',
    this.dialer,
  });

  final DeliveryTaskDetails? details;
  final bool canComplete;
  final bool busy;
  final ConfirmCompletionFixture onConfirmed;
  final String? errorMessage;
  final Future<void> Function()? onRetry;
  final String retryLabel;
  final DeliveryPhoneDialer? dialer;

  @override
  State<CompletionPanelFixture> createState() => _CompletionPanelFixtureState();
}

class _CompletionPanelFixtureState extends State<CompletionPanelFixture> {
  bool _dialogOpen = false;
  bool _dialerBusy = false;
  String? _dialerMessage;

  Future<void> _confirm() async {
    final amount = widget.details?.task.amountToCollectVnd;
    if (_dialogOpen || widget.busy || !widget.canComplete || amount == null) {
      return;
    }
    final handler =
        widget.onConfirmed; // Bind the confirmation to this session/snapshot.
    setState(() => _dialogOpen = true);
    var goods = false;
    var money = false;
    try {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Xác nhận giao thành công'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatFixtureVnd(amount),
                    key: const ValueKey('completion-dialog-amount'),
                  ),
                  const Text(
                    'Toàn bộ COD theo backend, gồm phí giao nếu áp dụng. Không chỉnh sửa số tiền.',
                  ),
                  CheckboxListTile(
                    key: const ValueKey('completion-goods'),
                    value: goods,
                    onChanged: (value) =>
                        setDialogState(() => goods = value ?? false),
                    title: const Text('Khách đã nhận đủ toàn bộ hàng'),
                  ),
                  CheckboxListTile(
                    key: const ValueKey('completion-money'),
                    value: money,
                    onChanged: (value) =>
                        setDialogState(() => money = value ?? false),
                    title: Text('Đã thu đủ ${formatFixtureVnd(amount)}'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                key: const ValueKey('completion-cancel'),
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Quay lại'),
              ),
              FilledButton(
                key: const ValueKey('completion-confirm'),
                onPressed: goods && money
                    ? () => Navigator.pop(context, true)
                    : null,
                child: const Text('Xác nhận'),
              ),
            ],
          ),
        ),
      );
      if (approved == true && mounted) {
        await handler(
          receivedAllItems: true,
          receivedFullCod: true,
          displayedAmountVnd: amount,
        );
      }
    } finally {
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  Future<void> _openDialer() async {
    final task = widget.details?.task;
    final phone = task?.destination?.phone.trim();
    final dialer = widget.dialer;
    if (_dialerBusy ||
        task?.scope != DeliverySnapshotScope.current ||
        phone == null ||
        !RegExp(r'^\+?[0-9]{6,15}$').hasMatch(phone) ||
        dialer == null) {
      return;
    }
    setState(() {
      _dialerBusy = true;
      _dialerMessage = null;
    });
    DialerOpenOutcome outcome;
    try {
      outcome = await dialer.openDialer(Uri(scheme: 'tel', path: phone));
    } catch (_) {
      outcome = DialerOpenOutcome.failed;
    }
    if (!mounted) return;
    if (widget.details?.task != task || !identical(widget.dialer, dialer)) {
      setState(() {
        _dialerBusy = false;
        _dialerMessage = null;
      });
      return;
    }
    setState(() {
      _dialerBusy = false;
      _dialerMessage = switch (outcome) {
        DialerOpenOutcome.opened => 'Đã mở trình quay số (fixture).',
        DialerOpenOutcome.unavailable => 'Không có trình quay số khả dụng.',
        DialerOpenOutcome.failed => 'Không thể mở trình quay số.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.details?.task;
    final amount = task?.amountToCollectVnd;
    final phone = task?.destination?.phone.trim();
    final canDial =
        task?.scope == DeliverySnapshotScope.current &&
        phone != null &&
        RegExp(r'^\+?[0-9]{6,15}$').hasMatch(phone) &&
        widget.dialer != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('P05.2 TEST-ONLY — chưa kết nối completion RPC live'),
        if (task?.status == DeliveryTaskStatus.delivered)
          const Text('Đã giao thành công (theo dữ liệu đọc)'),
        Text(
          amount == null
              ? 'COD không khả dụng trong snapshot này.'
              : formatFixtureVnd(amount),
          key: const ValueKey('completion-amount'),
        ),
        if (task?.kind == DeliveryTaskKind.outbound &&
            task?.scope == DeliverySnapshotScope.current &&
            task?.status == DeliveryTaskStatus.inTransit)
          FilledButton(
            key: const ValueKey('completion-open'),
            onPressed: widget.canComplete && !widget.busy && !_dialogOpen
                ? _confirm
                : null,
            child: const Text('Giao thành công'),
          ),
        if (widget.busy) const Text('Đang chờ kết quả và đọc lại dữ liệu…'),
        if (widget.errorMessage != null)
          Text(
            widget.errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (widget.onRetry != null)
          OutlinedButton(
            key: const ValueKey('completion-retry'),
            onPressed: widget.busy ? null : widget.onRetry,
            child: Text(widget.retryLabel),
          ),
        OutlinedButton.icon(
          key: const ValueKey('completion-dialer'),
          onPressed: canDial && !_dialerBusy ? _openDialer : null,
          icon: const Icon(Icons.phone_outlined),
          label: const Text('Mở trình quay số'),
        ),
        if (_dialerMessage != null) Text(_dialerMessage!),
      ],
    );
  }
}

String formatFixtureVnd(int value) {
  final digits = value.toString();
  final output = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) output.write('.');
    output.write(digits[i]);
  }
  return '$output đ';
}
