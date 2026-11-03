import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/utils/display_formatters.dart';
import '../../domain/models/manager_return.dart';
import '../../domain/repositories/manager_evidence_picker.dart';
import '../view_models/manager_return_view_models.dart';
import 'create_return_sections.dart';

/// Opens the confirmation UI for a return management action. Every sheet
/// submits once through the detail ViewModel (idempotent key, double-tap
/// guard) and closes only when the server confirmed.
Future<void> showManagerReturnActionSheet(
  BuildContext context, {
  required String returnId,
  required ManagerReturnDetail detail,
  required ManagerReturnAction action,
}) {
  final Widget sheet = switch (action) {
    ManagerReturnAction.requestInfo => _RequestInfoSheet(returnId: returnId),
    ManagerReturnAction.receive => _ReceiveSheet(
      returnId: returnId,
      detail: detail,
    ),
    ManagerReturnAction.acceptInspection => _AcceptInspectionSheet(
      returnId: returnId,
      detail: detail,
    ),
    ManagerReturnAction.rejectInspection => _RejectInspectionSheet(
      returnId: returnId,
    ),
    ManagerReturnAction.recordRefund => _RefundSheet(
      returnId: returnId,
      detail: detail,
    ),
    ManagerReturnAction.assignRedelivery => _RedeliverySheet(
      returnId: returnId,
      detail: detail,
    ),
    ManagerReturnAction.approveCollection ||
    ManagerReturnAction.reject => throw ArgumentError.value(action),
  };
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => sheet,
  );
}

const _hint = TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.mute);
const _error = TextStyle(fontSize: 12.5, color: AppColors.sale);

/// Common sheet frame: title, note, body, server error and confirm button.
class _SheetFrame extends ConsumerWidget {
  const _SheetFrame({
    required this.returnId,
    required this.title,
    required this.confirmLabel,
    required this.confirmKey,
    required this.onConfirm,
    required this.children,
    this.note,
    this.danger = false,
  });

  final String returnId;
  final String title;
  final String? note;
  final String confirmLabel;
  final String confirmKey;
  final Future<void> Function()? onConfirm;
  final List<Widget> children;
  final bool danger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(managerReturnDetailProvider(returnId));
    final busy = state.submitting;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(
        key: ValueKey('$confirmKey-sheet'),
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: ReturnPalette.creamSurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                note!,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: ReturnPalette.warningInk,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          ...children,
          if (state.actionFailure != null) ...[
            const SizedBox(height: 10),
            Text(state.actionFailure!.message, style: _error),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: ValueKey(confirmKey),
            onPressed: busy || onConfirm == null ? null : () => onConfirm!(),
            style: FilledButton.styleFrom(
              backgroundColor: danger ? AppColors.saleDeep : AppColors.primary,
              minimumSize: const Size.fromHeight(48),
              shape: const StadiumBorder(),
            ),
            child: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onPrimary,
                    ),
                  )
                : Text(confirmLabel),
          ),
        ],
      ),
    );
  }
}

class _ConfirmCheck extends StatelessWidget {
  const _ConfirmCheck({
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) => CheckboxListTile(
    key: const ValueKey('mh15-confirm-check'),
    contentPadding: EdgeInsets.zero,
    value: value,
    onChanged: (v) => onChanged(v ?? false),
    title: Text(label, style: const TextStyle(fontSize: 13)),
    controlAffinity: ListTileControlAffinity.leading,
  );
}

/// Picks up to [max] evidence files; shows picker errors inline.
class _EvidenceField extends ConsumerStatefulWidget {
  const _EvidenceField({
    required this.files,
    required this.onChanged,
    required this.label,
    this.max = 5,
    this.errorText,
  });

  final List<ManagerEvidenceFile> files;
  final ValueChanged<List<ManagerEvidenceFile>> onChanged;
  final String label;
  final int max;
  final String? errorText;

  @override
  ConsumerState<_EvidenceField> createState() => _EvidenceFieldState();
}

class _EvidenceFieldState extends ConsumerState<_EvidenceField> {
  String? _pickError;

  Future<void> _pick() async {
    setState(() => _pickError = null);
    try {
      final file = await ref.read(managerEvidencePickerProvider).pickEvidence();
      if (file != null) widget.onChanged([...widget.files, file]);
    } on ManagerEvidencePickFailure catch (e) {
      setState(() => _pickError = e.message);
    } catch (_) {
      setState(() => _pickError = 'Không đọc được tệp. Thử tệp khác.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 6),
        for (final (index, file) in widget.files.indexed)
          Row(
            children: [
              const Icon(Icons.attach_file, size: 18, color: AppColors.mute),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Bỏ tệp',
                onPressed: () => widget.onChanged([
                  for (final (i, f) in widget.files.indexed)
                    if (i != index) f,
                ]),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        if (widget.files.length < widget.max)
          OutlinedButton.icon(
            key: const ValueKey('mh15-pick-evidence'),
            onPressed: _pick,
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Chọn ảnh hoặc PDF'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.ink,
              shape: const StadiumBorder(),
            ),
          ),
        if (_pickError != null || widget.errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_pickError ?? widget.errorText!, style: _error),
          ),
      ],
    );
  }
}

Future<void> _submit(
  BuildContext context,
  Future<bool> Function() command,
) async {
  final ok = await command();
  if (ok && context.mounted) Navigator.of(context).pop();
}

// ------------------------------------------------------------- sheets ----

class _RequestInfoSheet extends ConsumerStatefulWidget {
  const _RequestInfoSheet({required this.returnId});

  final String returnId;

  @override
  ConsumerState<_RequestInfoSheet> createState() => _RequestInfoSheetState();
}

class _RequestInfoSheetState extends ConsumerState<_RequestInfoSheet> {
  final _controller = TextEditingController();
  bool _showErrors = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? get _errorText {
    if (!_showErrors) return null;
    final n = _controller.text.trim().length;
    if (n < 5) return 'Nhập nội dung cần bổ sung (tối thiểu 5 ký tự).';
    if (n > 500) return 'Tối đa 500 ký tự.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      returnId: widget.returnId,
      title: 'Yêu cầu khách bổ sung',
      note:
          'Yêu cầu vẫn mở; khách trả lời trong màn theo dõi yêu cầu, có thể '
          'kèm video. Quyết định tiếp theo mở lại khi khách phản hồi.',
      confirmLabel: 'Gửi yêu cầu bổ sung',
      confirmKey: 'mh15-request-info-confirm',
      onConfirm: () async {
        setState(() => _showErrors = true);
        if (_errorText != null) return;
        await _submit(
          context,
          () => ref
              .read(managerReturnDetailProvider(widget.returnId).notifier)
              .requestInfo(_controller.text),
        );
      },
      children: [
        TextField(
          key: const ValueKey('mh15-request-info-text'),
          controller: _controller,
          maxLines: 3,
          maxLength: 500,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Nội dung cần khách bổ sung',
            border: const OutlineInputBorder(),
            errorText: _errorText,
          ),
        ),
      ],
    );
  }
}

class _ReceiveSheet extends ConsumerStatefulWidget {
  const _ReceiveSheet({required this.returnId, required this.detail});

  final String returnId;
  final ManagerReturnDetail detail;

  @override
  ConsumerState<_ReceiveSheet> createState() => _ReceiveSheetState();
}

class _ReceiveSheetState extends ConsumerState<_ReceiveSheet> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      returnId: widget.returnId,
      title: 'Xác nhận cửa hàng đã nhận hàng',
      note:
          'Ghi nhận cửa hàng thực nhận, tách khỏi báo bàn giao của shipper. '
          'Chưa nhập kho: hàng chỉ vào kho bán sau khi kiểm tra.',
      confirmLabel: 'Đã nhận đủ hàng',
      confirmKey: 'mh15-receive-confirm',
      onConfirm: _confirmed
          ? () => _submit(
              context,
              () => ref
                  .read(managerReturnDetailProvider(widget.returnId).notifier)
                  .receive(),
            )
          : null,
      children: [
        for (final i in widget.detail.returnItems)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('${i.name} × ${i.quantityCollected}'),
          ),
        _ConfirmCheck(
          value: _confirmed,
          onChanged: (v) => setState(() => _confirmed = v),
          label: 'Tôi đã kiểm đếm đủ hàng shipper bàn giao',
        ),
      ],
    );
  }
}

class _AcceptInspectionSheet extends ConsumerStatefulWidget {
  const _AcceptInspectionSheet({required this.returnId, required this.detail});

  final String returnId;
  final ManagerReturnDetail detail;

  @override
  ConsumerState<_AcceptInspectionSheet> createState() =>
      _AcceptInspectionSheetState();
}

class _AcceptInspectionSheetState
    extends ConsumerState<_AcceptInspectionSheet> {
  /// Sellable per return item; damaged = received - sellable.
  late final Map<String, int> _sellable = {
    for (final i in widget.detail.returnItems)
      i.returnItemId: i.quantityCollected,
  };
  List<ManagerEvidenceFile> _evidence = const [];
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    return _SheetFrame(
      returnId: widget.returnId,
      title: 'Chấp nhận sau kiểm tra',
      note:
          'Hàng bán được nhập lại kho một lần; hàng lỗi ghi vào hàng hỏng, '
          'không bán lại. Sau bước này mới ghi nhận hoàn tiền '
          '${formatVnd(detail.refundAmountVnd)}.',
      confirmLabel: 'Chấp nhận và nhập kho',
      confirmKey: 'mh15-accept-confirm',
      onConfirm: _confirmed
          ? () => _submit(
              context,
              () => ref
                  .read(managerReturnDetailProvider(widget.returnId).notifier)
                  .acceptInspection(
                    lines: [
                      for (final i in detail.returnItems)
                        ManagerInspectionLine(
                          returnItemId: i.returnItemId,
                          sellableQuantity: _sellable[i.returnItemId]!,
                          damagedQuantity:
                              i.quantityCollected - _sellable[i.returnItemId]!,
                        ),
                    ],
                    evidence: _evidence,
                  ),
            )
          : null,
      children: [
        for (final i in detail.returnItems)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(i.name),
                      Text(
                        'Thực nhận ${i.quantityCollected} · Lỗi '
                        '${i.quantityCollected - _sellable[i.returnItemId]!}',
                        style: _hint,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('mh15-sellable-minus-${i.returnItemId}'),
                  tooltip: 'Giảm hàng bán được',
                  onPressed: _sellable[i.returnItemId]! == 0
                      ? null
                      : () => setState(
                          () => _sellable[i.returnItemId] =
                              _sellable[i.returnItemId]! - 1,
                        ),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text(
                  'Bán được ${_sellable[i.returnItemId]}',
                  key: ValueKey('mh15-sellable-${i.returnItemId}'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                IconButton(
                  tooltip: 'Tăng hàng bán được',
                  onPressed: _sellable[i.returnItemId]! >= i.quantityCollected
                      ? null
                      : () => setState(
                          () => _sellable[i.returnItemId] =
                              _sellable[i.returnItemId]! + 1,
                        ),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        _EvidenceField(
          files: _evidence,
          onChanged: (f) => setState(() => _evidence = f),
          label: 'Ảnh kiểm tra (không bắt buộc)',
        ),
        _ConfirmCheck(
          value: _confirmed,
          onChanged: (v) => setState(() => _confirmed = v),
          label: 'Hàng thực nhận phù hợp với yêu cầu và video của khách',
        ),
      ],
    );
  }
}

class _RejectInspectionSheet extends ConsumerStatefulWidget {
  const _RejectInspectionSheet({required this.returnId});

  final String returnId;

  @override
  ConsumerState<_RejectInspectionSheet> createState() =>
      _RejectInspectionSheetState();
}

class _RejectInspectionSheetState
    extends ConsumerState<_RejectInspectionSheet> {
  final _controller = TextEditingController();
  List<ManagerEvidenceFile> _evidence = const [];
  bool _confirmed = false;
  bool _showErrors = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? get _reasonError {
    if (!_showErrors) return null;
    final n = _controller.text.trim().length;
    if (n < 5) return 'Nhập lý do (tối thiểu 5 ký tự).';
    if (n > 500) return 'Tối đa 500 ký tự.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      returnId: widget.returnId,
      title: 'Từ chối sau kiểm tra',
      danger: true,
      note:
          'Toàn bộ hàng thực nhận sẽ được giao lại miễn phí, không thu COD. '
          'Yêu cầu chỉ đóng khi khách nhận lại hàng.',
      confirmLabel: 'Từ chối và chuẩn bị giao lại',
      confirmKey: 'mh15-reject-inspection-confirm',
      onConfirm: _confirmed
          ? () async {
              setState(() => _showErrors = true);
              if (_reasonError != null || _evidence.isEmpty) return;
              await _submit(
                context,
                () => ref
                    .read(managerReturnDetailProvider(widget.returnId).notifier)
                    .rejectInspection(
                      reason: _controller.text,
                      evidence: _evidence,
                    ),
              );
            }
          : null,
      children: [
        TextField(
          key: const ValueKey('mh15-reject-inspection-reason'),
          controller: _controller,
          maxLines: 3,
          maxLength: 500,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Lý do từ chối',
            border: const OutlineInputBorder(),
            errorText: _reasonError,
          ),
        ),
        _EvidenceField(
          files: _evidence,
          onChanged: (f) => setState(() => _evidence = f),
          label: 'Bằng chứng kiểm tra (bắt buộc)',
          errorText: _showErrors && _evidence.isEmpty
              ? 'Cần ít nhất một ảnh hoặc tệp bằng chứng.'
              : null,
        ),
        _ConfirmCheck(
          value: _confirmed,
          onChanged: (v) => setState(() => _confirmed = v),
          label: 'Tôi xác nhận từ chối sau kiểm tra',
        ),
      ],
    );
  }
}

class _RefundSheet extends ConsumerStatefulWidget {
  const _RefundSheet({required this.returnId, required this.detail});

  final String returnId;
  final ManagerReturnDetail detail;

  @override
  ConsumerState<_RefundSheet> createState() => _RefundSheetState();
}

class _RefundSheetState extends ConsumerState<_RefundSheet> {
  DateTime? _transferredAt;
  List<ManagerEvidenceFile> _evidence = const [];
  bool _confirmed = false;
  bool _showErrors = false;

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null) return;
    setState(
      () => _transferredAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final bank = detail.bank;
    return _SheetFrame(
      returnId: widget.returnId,
      title: 'Ghi nhận hoàn tiền',
      note:
          'Chuyển khoản ngoài ứng dụng trước, rồi ghi thời điểm chuyển thực tế '
          'và tải chứng từ. Hoàn tiền không trừ vào COD của shipper.',
      confirmLabel: 'Ghi nhận đã hoàn ${formatVnd(detail.refundAmountVnd)}',
      confirmKey: 'mh15-refund-confirm',
      onConfirm: _confirmed
          ? () async {
              setState(() => _showErrors = true);
              if (_transferredAt == null || _evidence.isEmpty) return;
              await _submit(
                context,
                () => ref
                    .read(managerReturnDetailProvider(widget.returnId).notifier)
                    .recordRefund(
                      transferredAt: _transferredAt!,
                      evidence: _evidence.single,
                    ),
              );
            }
          : null,
      children: [
        Text(
          'Số tiền hoàn: ${formatVnd(detail.refundAmountVnd)} '
          '(tiền hàng ${formatVnd(detail.subtotalVnd)} + phí giao '
          '${formatVnd(detail.deliveryFeeVnd)})',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (bank != null) ...[
          const SizedBox(height: 6),
          Text(
            '${bank.bankName} · ${bank.accountNumber} · ${bank.accountHolder}',
            style: _hint,
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('mh15-refund-time'),
          onPressed: _pickTime,
          icon: const Icon(Icons.schedule),
          label: Text(
            _transferredAt == null
                ? 'Chọn thời điểm chuyển khoản'
                : 'Chuyển lúc ${formatHanoiDateTime(_transferredAt!)}',
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.ink,
            shape: const StadiumBorder(),
          ),
        ),
        if (_showErrors && _transferredAt == null)
          const Text('Chọn thời điểm chuyển khoản.', style: _error),
        const SizedBox(height: 12),
        _EvidenceField(
          files: _evidence,
          max: 1,
          onChanged: (f) => setState(() => _evidence = f),
          label: 'Chứng từ chuyển khoản (bắt buộc)',
          errorText: _showErrors && _evidence.isEmpty
              ? 'Cần chứng từ chuyển khoản.'
              : null,
        ),
        _ConfirmCheck(
          value: _confirmed,
          onChanged: (v) => setState(() => _confirmed = v),
          label: 'Tôi đã chuyển đủ số tiền trên cho khách',
        ),
      ],
    );
  }
}

class _RedeliverySheet extends ConsumerStatefulWidget {
  const _RedeliverySheet({required this.returnId, required this.detail});

  final String returnId;
  final ManagerReturnDetail detail;

  @override
  ConsumerState<_RedeliverySheet> createState() => _RedeliverySheetState();
}

class _RedeliverySheetState extends ConsumerState<_RedeliverySheet> {
  String? _shipperId;

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      returnId: widget.returnId,
      title: 'Phân công giao lại miễn phí',
      note: 'Giao lại toàn bộ hàng thực nhận cho khách, không thu COD.',
      confirmLabel: 'Phân công giao lại',
      confirmKey: 'mh15-redelivery-confirm',
      onConfirm: _shipperId == null
          ? null
          : () => _submit(
              context,
              () => ref
                  .read(managerReturnDetailProvider(widget.returnId).notifier)
                  .assignRedelivery(_shipperId!),
            ),
      children: [
        DropdownButtonFormField<String>(
          key: const ValueKey('mh15-redelivery-shipper'),
          initialValue: _shipperId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Shipper giao lại',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final s in widget.detail.shippers)
              DropdownMenuItem(
                value: s.shipperId,
                child: Text(
                  s.phone == null ? s.name : '${s.name} · ${s.phone}',
                ),
              ),
          ],
          onChanged: (v) => setState(() => _shipperId = v),
        ),
      ],
    );
  }
}
