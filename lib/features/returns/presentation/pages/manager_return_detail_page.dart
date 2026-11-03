import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/utils/display_formatters.dart';
import '../../../../shared/widgets/foreground_refresh.dart';
import '../../domain/models/manager_return.dart';
import '../../domain/models/return_request_failure.dart';
import '../view_models/manager_return_view_models.dart';
import '../widgets/create_return_sections.dart';
import '../widgets/manager_return_sections.dart';
import '../widgets/manager_return_action_sheets.dart';
import 'manager_returns_page.dart' show managerLoadMessage;

/// Return management detail (manager). Shows only the actions allowed for
/// the current status; the server re-checks role, state and idempotency.
class ManagerReturnDetailPage extends ConsumerStatefulWidget {
  const ManagerReturnDetailPage({
    required this.returnId,
    required this.onBack,
    this.openUrl,
    this.onCall,
    super.key,
  });

  final String returnId;
  final VoidCallback onBack;

  /// Opens a signed video URL. Defaults to a new browser tab / external app.
  final Future<void> Function(Uri url)? openUrl;
  final ValueChanged<String>? onCall;

  @override
  ConsumerState<ManagerReturnDetailPage> createState() =>
      _ManagerReturnDetailPageState();
}

class _ManagerReturnDetailPageState
    extends ConsumerState<ManagerReturnDetailPage> {
  String? _openingVideo;
  String? _videoError;

  Future<void> _openVideo(String path) async {
    setState(() {
      _openingVideo = path;
      _videoError = null;
    });
    try {
      final url = await ref
          .read(managerReturnDetailProvider(widget.returnId).notifier)
          .videoUrl(path);
      final open =
          widget.openUrl ??
          (u) => launchUrl(u, mode: LaunchMode.externalApplication);
      await open(url);
    } on ReturnRequestFailure catch (failure) {
      _videoError = failure.code == ReturnRequestFailureCode.permissionDenied
          ? 'Không có quyền xem video này.'
          : 'Không tải được video. Bấm để thử lại.';
    } catch (_) {
      _videoError = 'Không mở được video. Bấm để thử lại.';
    } finally {
      if (mounted) setState(() => _openingVideo = null);
    }
  }

  Future<void> _openEvidence(ManagerEvidenceKind kind, String path) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final url = await ref
          .read(managerReturnDetailProvider(widget.returnId).notifier)
          .evidenceUrl(kind, path);
      final open =
          widget.openUrl ??
          (u) => launchUrl(u, mode: LaunchMode.externalApplication);
      await open(url);
    } catch (_) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Không mở được chứng từ. Thử lại sau.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = managerReturnDetailProvider(widget.returnId);
    final state = ref.watch(provider);
    final viewModel = ref.read(provider.notifier);
    final detail = state.detail;

    ref.listen(provider.select((s) => s.notice), (_, notice) {
      if (notice == null) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(key: const ValueKey('mh15-notice'), content: Text(notice)),
      );
      viewModel.clearNotice();
    });

    final Widget body;
    if (detail == null) {
      body = Center(
        child: state.loading
            ? const CircularProgressIndicator(
                key: ValueKey('mh15-detail-loading'),
              )
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      managerLoadMessage(state.loadFailure),
                      key: const ValueKey('mh15-detail-error'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.charcoal,
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: viewModel.refresh,
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: viewModel.refresh,
        child: ListView(
          key: const ValueKey('mh15-detail'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            if (state.isStale) ...[
              Text(
                '${managerLoadMessage(state.loadFailure)} Đang hiển thị dữ liệu đã tải trước đó.',
                style: const TextStyle(fontSize: 12.5, color: AppColors.sale),
              ),
              const SizedBox(height: 8),
            ],
            ManagerSummaryCard(detail: detail),
            const SizedBox(height: 12),
            ManagerContactCard(
              detail: detail,
              onCall:
                  widget.onCall ??
                  (phone) => launchUrl(Uri(scheme: 'tel', path: phone)),
            ),
            const SizedBox(height: 12),
            ManagerOrderItemsCard(detail: detail),
            const SizedBox(height: 12),
            ManagerReasonCard(detail: detail),
            const SizedBox(height: 12),
            ManagerVideoCard(
              paths: detail.videoPaths,
              onOpen: _openVideo,
              openingPath: _openingVideo,
              error: _videoError,
            ),
            if (detail.bank != null) ...[
              const SizedBox(height: 12),
              ManagerBankCard(bank: detail.bank!),
            ],
            if (detail.pickupTask != null) ...[
              const SizedBox(height: 12),
              ManagerPickupCard(task: detail.pickupTask!),
            ],
            for (final info in detail.infoRequests) ...[
              const SizedBox(height: 12),
              ManagerInfoRequestCard(
                request: info,
                onOpenVideo: info.responseVideoPath == null
                    ? null
                    : () => _openVideo(info.responseVideoPath!),
              ),
            ],
            if (detail.redeliveryTask != null) ...[
              const SizedBox(height: 12),
              ManagerPickupCard(
                task: detail.redeliveryTask!,
                title: 'Giao lại miễn phí',
              ),
            ],
            if (detail.inspectedAt != null ||
                detail.inspectionEvidencePaths.isNotEmpty) ...[
              const SizedBox(height: 12),
              ManagerInspectionCard(
                detail: detail,
                onOpenEvidence: (path) =>
                    _openEvidence(ManagerEvidenceKind.inspection, path),
              ),
            ],
            if (detail.refund != null) ...[
              const SizedBox(height: 12),
              ManagerRefundCard(
                refund: detail.refund!,
                onOpenEvidence: () => _openEvidence(
                  ManagerEvidenceKind.refund,
                  detail.refund!.evidencePath,
                ),
              ),
            ],
            if (detail.decisionAt != null) ...[
              const SizedBox(height: 12),
              ManagerDecisionCard(detail: detail),
            ],
            if (detail.availableActions.isEmpty) ...[
              const SizedBox(height: 12),
              ManagerNextStepNote(status: detail.status),
            ],
          ],
        ),
      );
    }

    final actions = detail?.availableActions ?? const {};
    return AppTheme.notificationsScope(
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              ManagerReturnsHeader(
                onBack: widget.onBack,
                subtitle: 'Chi tiết yêu cầu',
                onRefresh: state.loading || state.submitting
                    ? null
                    : viewModel.refresh,
              ),
              if (state.loading && detail != null)
                const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: ForegroundRefresh(
                  enabled: detail != null,
                  canRefresh: () => viewModel.canPoll,
                  onRefresh: viewModel.poll,
                  child: body,
                ),
              ),
              if (actions.isNotEmpty && detail != null)
                _ActionBar(
                  detail: detail,
                  state: state,
                  onAction: (action) => _onAction(context, action, detail),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onAction(
    BuildContext context,
    ManagerReturnAction action,
    ManagerReturnDetail detail,
  ) => switch (action) {
    ManagerReturnAction.approveCollection => _showApproveSheet(context, detail),
    ManagerReturnAction.reject => _showRejectDialog(context),
    _ => showManagerReturnActionSheet(
      context,
      returnId: widget.returnId,
      detail: detail,
      action: action,
    ),
  };

  Future<void> _showApproveSheet(
    BuildContext context,
    ManagerReturnDetail detail,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ApproveSheet(returnId: widget.returnId, detail: detail),
    );
  }

  Future<void> _showRejectDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _RejectDialog(returnId: widget.returnId),
    );
  }
}

typedef _ActionSpec = ({String label, String key, bool primary, bool danger});

const _actionSpecs = <ManagerReturnAction, _ActionSpec>{
  ManagerReturnAction.reject: (
    label: 'Từ chối',
    key: 'mh15-reject',
    primary: false,
    danger: true,
  ),
  ManagerReturnAction.approveCollection: (
    label: 'Duyệt lấy hàng',
    key: 'mh15-approve',
    primary: true,
    danger: false,
  ),
  ManagerReturnAction.receive: (
    label: 'Xác nhận đã nhận hàng',
    key: 'mh15-receive',
    primary: true,
    danger: false,
  ),
  ManagerReturnAction.rejectInspection: (
    label: 'Từ chối sau kiểm tra',
    key: 'mh15-reject-inspection',
    primary: false,
    danger: true,
  ),
  ManagerReturnAction.acceptInspection: (
    label: 'Chấp nhận',
    key: 'mh15-accept-inspection',
    primary: true,
    danger: false,
  ),
  ManagerReturnAction.recordRefund: (
    label: 'Ghi nhận hoàn tiền',
    key: 'mh15-record-refund',
    primary: true,
    danger: false,
  ),
  ManagerReturnAction.assignRedelivery: (
    label: 'Phân công giao lại',
    key: 'mh15-assign-redelivery',
    primary: true,
    danger: false,
  ),
};

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.detail,
    required this.state,
    required this.onAction,
  });

  final ManagerReturnDetail detail;
  final ManagerReturnDetailState state;
  final ValueChanged<ManagerReturnAction> onAction;

  @override
  Widget build(BuildContext context) {
    final actions = detail.availableActions;
    final busy = state.submitting;
    final buttons = [
      for (final entry in _actionSpecs.entries)
        if (actions.contains(entry.key)) entry,
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.hairlineSoft)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.actionFailure != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                state.actionFailure!.message,
                key: const ValueKey('mh15-action-error'),
                style: const TextStyle(fontSize: 12.5, color: AppColors.sale),
              ),
            ),
          if (actions.contains(ManagerReturnAction.requestInfo))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('mh15-request-info'),
                onPressed: busy
                    ? null
                    : () => onAction(ManagerReturnAction.requestInfo),
                icon: const Icon(Icons.help_outline, size: 18),
                label: const Text('Yêu cầu khách bổ sung'),
                style: TextButton.styleFrom(foregroundColor: AppColors.ink),
              ),
            ),
          Row(
            children: [
              for (final (i, entry) in buttons.indexed) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  flex: entry.value.primary ? 2 : 1,
                  child: entry.value.primary
                      ? FilledButton(
                          key: ValueKey(entry.value.key),
                          onPressed: busy ? null : () => onAction(entry.key),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
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
                              : Text(
                                  entry.value.label,
                                  textAlign: TextAlign.center,
                                ),
                        )
                      : OutlinedButton(
                          key: ValueKey(entry.value.key),
                          onPressed: busy ? null : () => onAction(entry.key),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: entry.value.danger
                                ? AppColors.saleDeep
                                : AppColors.ink,
                            side: const BorderSide(color: AppColors.hairline),
                            minimumSize: const Size.fromHeight(48),
                            shape: const StadiumBorder(),
                          ),
                          child: Text(
                            entry.value.label,
                            textAlign: TextAlign.center,
                          ),
                        ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Choose the goods actually to collect and the shipper, then confirm once.
class _ApproveSheet extends ConsumerStatefulWidget {
  const _ApproveSheet({required this.returnId, required this.detail});

  final String returnId;
  final ManagerReturnDetail detail;

  @override
  ConsumerState<_ApproveSheet> createState() => _ApproveSheetState();
}

class _ApproveSheetState extends ConsumerState<_ApproveSheet> {
  late final Map<String, int> _quantities = {
    for (final item in widget.detail.orderItems)
      item.orderItemId: item.quantity,
  };
  String? _shipperId;
  bool _showErrors = false;

  List<ManagerCollectionLine> get _lines => [
    for (final e in _quantities.entries)
      if (e.value > 0)
        ManagerCollectionLine(orderItemId: e.key, quantity: e.value),
  ];

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(managerReturnDetailProvider(widget.returnId));
    final busy = state.submitting;
    final detail = widget.detail;
    final noLines = _lines.isEmpty;
    final noShipper = _shipperId == null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(
        key: const ValueKey('mh15-approve-sheet'),
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        children: [
          const Text(
            'Duyệt lấy hàng',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: ReturnPalette.creamSurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Chỉ tổ chức thu hồi hàng. Hoàn tiền chỉ được quyết định sau khi '
              'cửa hàng nhận và kiểm tra hàng.',
              style: TextStyle(fontSize: 12.5, color: ReturnPalette.warningInk),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Sản phẩm cần thu hồi',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
          const SizedBox(height: 8),
          for (final item in detail.orderItems)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.productName),
                        Text(
                          '${item.variantLabel ?? ''} · Đã giao ${item.quantity}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.mute,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: ValueKey('mh15-qty-minus-${item.orderItemId}'),
                    tooltip: 'Giảm',
                    onPressed: busy || _quantities[item.orderItemId]! == 0
                        ? null
                        : () => setState(
                            () => _quantities[item.orderItemId] =
                                _quantities[item.orderItemId]! - 1,
                          ),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${_quantities[item.orderItemId]}',
                      key: ValueKey('mh15-qty-${item.orderItemId}'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    key: ValueKey('mh15-qty-plus-${item.orderItemId}'),
                    tooltip: 'Tăng',
                    onPressed:
                        busy || _quantities[item.orderItemId]! >= item.quantity
                        ? null
                        : () => setState(
                            () => _quantities[item.orderItemId] =
                                _quantities[item.orderItemId]! + 1,
                          ),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ),
          if (_showErrors && noLines)
            const Text(
              'Chọn ít nhất một sản phẩm cần thu hồi.',
              style: TextStyle(fontSize: 12.5, color: AppColors.sale),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const ValueKey('mh15-shipper'),
            initialValue: _shipperId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Shipper lấy hàng',
              border: const OutlineInputBorder(),
              errorText: _showErrors && noShipper ? 'Chọn shipper.' : null,
            ),
            items: [
              for (final s in detail.shippers)
                DropdownMenuItem(
                  value: s.shipperId,
                  child: Text(
                    s.phone == null ? s.name : '${s.name} · ${s.phone}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: busy ? null : (v) => setState(() => _shipperId = v),
          ),
          if (detail.shippers.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Chưa có tài khoản shipper nào.',
                style: TextStyle(fontSize: 12.5, color: AppColors.sale),
              ),
            ),
          if (state.actionFailure != null) ...[
            const SizedBox(height: 10),
            Text(
              state.actionFailure!.message,
              style: const TextStyle(fontSize: 12.5, color: AppColors.sale),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('mh15-approve-confirm'),
            onPressed: busy
                ? null
                : () async {
                    setState(() => _showErrors = true);
                    if (noLines || noShipper) return;
                    final ok = await ref
                        .read(
                          managerReturnDetailProvider(widget.returnId).notifier,
                        )
                        .approveCollection(
                          lines: _lines,
                          shipperId: _shipperId!,
                        );
                    if (ok && context.mounted) Navigator.of(context).pop();
                  },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
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
                : Text(
                    'Xác nhận duyệt và phân công'
                    '${noLines ? '' : ' (${_lines.fold(0, (a, l) => a + l.quantity)} sp)'}',
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tổng đã thanh toán của đơn: ${formatVnd(detail.totalVnd)}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.mute),
          ),
        ],
      ),
    );
  }
}

class _RejectDialog extends ConsumerStatefulWidget {
  const _RejectDialog({required this.returnId});

  final String returnId;

  @override
  ConsumerState<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends ConsumerState<_RejectDialog> {
  final _controller = TextEditingController();
  bool _confirmed = false;
  bool _showErrors = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? get _error {
    if (!_showErrors) return null;
    final length = _controller.text.trim().length;
    if (length < 5) return 'Nhập lý do (tối thiểu 5 ký tự).';
    if (length > 500) return 'Tối đa 500 ký tự.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(managerReturnDetailProvider(widget.returnId));
    final busy = state.submitting;
    return AlertDialog(
      key: const ValueKey('mh15-reject-dialog'),
      title: const Text('Từ chối yêu cầu trả hàng'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hàng vẫn ở khách. Không tạo thu hồi hay hoàn tiền. '
              'Khách sẽ thấy lý do trong theo dõi yêu cầu.',
              style: TextStyle(fontSize: 13, color: AppColors.charcoal),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('mh15-reject-reason'),
              controller: _controller,
              enabled: !busy,
              maxLines: 3,
              maxLength: 500,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Lý do từ chối',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
            ),
            CheckboxListTile(
              key: const ValueKey('mh15-reject-confirm-check'),
              contentPadding: EdgeInsets.zero,
              value: _confirmed,
              onChanged: busy
                  ? null
                  : (v) => setState(() => _confirmed = v ?? false),
              title: const Text(
                'Tôi xác nhận từ chối yêu cầu này',
                style: TextStyle(fontSize: 13),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (state.actionFailure != null)
              Text(
                state.actionFailure!.message,
                style: const TextStyle(fontSize: 12.5, color: AppColors.sale),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const ValueKey('mh15-reject-submit'),
          onPressed: busy || !_confirmed
              ? null
              : () async {
                  setState(() => _showErrors = true);
                  if (_error != null) return;
                  final ok = await ref
                      .read(
                        managerReturnDetailProvider(widget.returnId).notifier,
                      )
                      .reject(_controller.text);
                  if (ok && context.mounted) Navigator.of(context).pop();
                },
          style: FilledButton.styleFrom(backgroundColor: AppColors.saleDeep),
          child: busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.onPrimary,
                  ),
                )
              : const Text('Từ chối'),
        ),
      ],
    );
  }
}
