import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/utils/display_formatters.dart';
import '../../domain/models/return_tracking.dart';
import '../view_models/return_tracking_timeline.dart';
import 'create_return_sections.dart';

const _title = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w700,
  height: 1.3,
  color: AppColors.ink,
);
const _muted = TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.mute);
const _body = TextStyle(fontSize: 13, height: 1.45, color: AppColors.charcoal);

BoxDecoration _card() => BoxDecoration(
  color: AppColors.surface,
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: AppColors.hairlineSoft),
);

String _time(DateTime value) {
  final h = toHanoi(value);
  return '${h.hour.toString().padLeft(2, '0')}:'
      '${h.minute.toString().padLeft(2, '0')}';
}

String _dateTime(DateTime value) =>
    '${_time(value)}, ${formatHanoiDate(value)}';

class ReturnTrackingHeader extends StatelessWidget {
  const ReturnTrackingHeader({
    required this.onBack,
    required this.onRefresh,
    super.key,
  });

  final VoidCallback? onBack;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.hairlineSoft)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Quay lại',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: AppColors.ink),
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Text(
              'Theo dõi yêu cầu trả',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('mh14-refresh'),
            tooltip: 'Tải lại',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, color: AppColors.ink),
          ),
        ],
      ),
    );
  }
}

enum _Tone { progress, success, danger, attention }

_Tone _toneOf(ReturnTracking t) => switch (t.status) {
  ReturnRequestStatus.refunded => _Tone.success,
  ReturnRequestStatus.initiallyRejected ||
  ReturnRequestStatus.rejectedAfterInspection ||
  ReturnRequestStatus.awaitingRedelivery => _Tone.danger,
  ReturnRequestStatus.managerActionRequired ||
  ReturnRequestStatus.redeliveryFailed => _Tone.attention,
  _ when t.infoRequest?.isOpen == true => _Tone.attention,
  _ => _Tone.progress,
};

({Color bg, Color fg}) _toneColors(_Tone tone) => switch (tone) {
  _Tone.success => (bg: ReturnPalette.successSurface, fg: AppColors.success),
  _Tone.danger => (bg: const Color(0xfffdecec), fg: AppColors.saleDeep),
  _Tone.attention => (
    bg: ReturnPalette.creamSurface,
    fg: ReturnPalette.warningAccent,
  ),
  _Tone.progress => (
    bg: ReturnPalette.creamSurface,
    fg: ReturnPalette.warningAccent,
  ),
};

class ReturnSummaryCard extends StatelessWidget {
  const ReturnSummaryCard({
    required this.tracking,
    required this.steps,
    super.key,
  });

  final ReturnTracking tracking;
  final List<ReturnTimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    final colors = _toneColors(_toneOf(tracking));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Mã trả hàng', style: _muted),
                    const SizedBox(height: 2),
                    Text(
                      tracking.returnCode,
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                key: const ValueKey('mh14-status'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: colors.bg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  returnTrackingStatusLabel(tracking),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.fg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Đơn gốc #${tracking.orderCode}', style: _muted),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.schedule, size: 15, color: AppColors.mute),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Gửi lúc ${_dateTime(tracking.submittedAt)}',
                  style: _muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final (index, step) in steps.skip(1).indexed) ...[
                if (index > 0) const SizedBox(width: 6),
                Expanded(
                  child: _StagePill(index: index + 1, step: step),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StagePill extends StatelessWidget {
  const _StagePill({required this.index, required this.step});

  final int index;
  final ReturnTimelineStep step;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border, icon) = switch (step.state) {
      ReturnStepState.done => (
        AppColors.success,
        AppColors.onPrimary,
        AppColors.success,
        Icons.check,
      ),
      ReturnStepState.current => (
        AppColors.primary,
        AppColors.onPrimary,
        AppColors.primary,
        step.attention ? Icons.priority_high : null,
      ),
      ReturnStepState.stopped => (
        const Color(0xfffdecec),
        AppColors.saleDeep,
        const Color(0xfff3c2c2),
        Icons.close,
      ),
      ReturnStepState.upcoming => (
        AppColors.surface,
        AppColors.mute,
        AppColors.hairline,
        null,
      ),
    };
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 4),
            ],
            Text(
              '$index. ${step.shortLabel}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReturnStaleBanner extends StatelessWidget {
  const ReturnStaleBanner({
    required this.confirmedAt,
    required this.message,
    required this.onRetry,
    super.key,
  });

  final DateTime confirmedAt;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('mh14-stale'),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: AppColors.softCloud,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairlineSoft),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 18, color: AppColors.ash),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$message Đang hiển thị thông tin xác nhận lúc '
              '${_dateTime(confirmedAt)}.',
              style: _body.copyWith(fontSize: 12.5),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: AppColors.info),
            child: const Text('Thử lại'),
          ),
        ],
      ),
    );
  }
}

class ReturnTimelineCard extends StatelessWidget {
  const ReturnTimelineCard({
    required this.tracking,
    required this.steps,
    required this.onCall,
    super.key,
  });

  final ReturnTracking tracking;
  final List<ReturnTimelineStep> steps;
  final ValueChanged<String>? onCall;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Tiến trình xử lý', style: _title)),
              Text(
                'Cập nhật ${_dateTime(tracking.refreshedAt)}',
                style: _muted.copyWith(fontSize: 11.5),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final (index, step) in steps.indexed)
            _TimelineRow(
              number: index + 1,
              step: step,
              isLast: index == steps.length - 1,
              detail: _detailFor(step),
            ),
        ],
      ),
    );
  }

  Widget? _detailFor(ReturnTimelineStep step) => switch (step.detail) {
    ReturnStepDetail.none => null,
    ReturnStepDetail.pickup => _AssignmentPanel(
      assignment: tracking.pickup,
      unassignedText: 'Chưa phân công người lấy hàng',
      scheduleLabel: 'Hẹn lấy',
      addressLabel: 'Địa chỉ lấy hàng',
      address: tracking.pickupAddress,
      onCall: onCall,
    ),
    ReturnStepDetail.redelivery => _AssignmentPanel(
      assignment: tracking.redelivery?.assignment,
      unassignedText: 'Chưa phân công người giao lại',
      scheduleLabel: 'Hẹn giao',
      addressLabel: 'Địa chỉ giao lại',
      address: tracking.pickupAddress,
      onCall: onCall,
      footnote: 'Miễn phí giao lại · Không thu thêm tiền COD',
    ),
    ReturnStepDetail.refundPending => _RefundPanel(
      tracking: tracking,
      done: false,
    ),
    ReturnStepDetail.refundDone => _RefundPanel(tracking: tracking, done: true),
  };
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.number,
    required this.step,
    required this.isLast,
    this.detail,
  });

  final int number;
  final ReturnTimelineStep step;
  final bool isLast;
  final Widget? detail;

  @override
  Widget build(BuildContext context) {
    final upcoming = step.state == ReturnStepState.upcoming;
    final current = step.state == ReturnStepState.current;
    final lineColor = step.state == ReturnStepState.done
        ? AppColors.successBright
        : AppColors.hairlineSoft;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                _StepDot(step: step),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: lineColor,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 10 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          '$number. ${step.title}',
                          key: ValueKey('mh14-step-${step.key}'),
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.35,
                            fontWeight: upcoming
                                ? FontWeight.w500
                                : FontWeight.w700,
                            color: upcoming
                                ? AppColors.stone
                                : step.state == ReturnStepState.stopped
                                ? AppColors.saleDeep
                                : AppColors.ink,
                          ),
                        ),
                      ),
                      if (step.occurredAt != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, top: 2),
                          child: Text(
                            _time(step.occurredAt!),
                            style: _muted.copyWith(fontSize: 12),
                          ),
                        ),
                      if (current)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: step.attention
                                ? ReturnPalette.warningAccent
                                : AppColors.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            step.attention ? 'Đang xử lý' : 'Hiện tại',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (step.occurredAt != null)
                    Text(
                      formatHanoiDate(step.occurredAt!),
                      style: _muted.copyWith(fontSize: 11.5),
                    ),
                  if (step.description != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      step.description!,
                      style: _body.copyWith(
                        color: upcoming ? AppColors.stone : AppColors.charcoal,
                      ),
                    ),
                  ],
                  if (detail != null) ...[const SizedBox(height: 10), detail!],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.step});

  final ReturnTimelineStep step;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color? border, Widget? child) = switch (step.state) {
      ReturnStepState.done => (
        AppColors.successBright,
        null,
        const Icon(Icons.check, size: 15, color: AppColors.onPrimary),
      ),
      ReturnStepState.current => (
        step.attention ? ReturnPalette.warningAccent : AppColors.primary,
        null,
        Icon(
          step.attention ? Icons.priority_high : Icons.more_horiz,
          size: 15,
          color: AppColors.onPrimary,
        ),
      ),
      ReturnStepState.stopped => (
        AppColors.sale,
        null,
        const Icon(Icons.close, size: 15, color: AppColors.onPrimary),
      ),
      ReturnStepState.upcoming => (AppColors.surface, AppColors.hairline, null),
    };
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: border == null ? null : Border.all(color: border, width: 2),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

BoxDecoration _panel() => BoxDecoration(
  color: AppColors.softCloud,
  borderRadius: BorderRadius.circular(12),
);

class _AssignmentPanel extends StatelessWidget {
  const _AssignmentPanel({
    required this.assignment,
    required this.unassignedText,
    required this.scheduleLabel,
    required this.addressLabel,
    required this.address,
    required this.onCall,
    this.footnote,
  });

  final ReturnPickupAssignment? assignment;
  final String unassignedText;
  final String scheduleLabel;
  final String addressLabel;
  final String address;
  final ValueChanged<String>? onCall;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final person = assignment;
    final phone = person?.shipperPhone;
    return Container(
      key: const ValueKey('mh14-assignment'),
      padding: const EdgeInsets.all(12),
      decoration: _panel(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  person == null
                      ? Icons.person_off_outlined
                      : Icons.two_wheeler,
                  size: 20,
                  color: person == null ? AppColors.stone : AppColors.ink,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: person == null
                    ? Text(
                        unassignedText,
                        style: _body.copyWith(fontWeight: FontWeight.w600),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            person.shipperName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          Text(
                            person.scheduledAt == null
                                ? 'Chưa có lịch hẹn'
                                : '$scheduleLabel: '
                                      '${_dateTime(person.scheduledAt!)}',
                            style: _muted,
                          ),
                        ],
                      ),
              ),
              if (phone != null && phone.isNotEmpty)
                Material(
                  color: ReturnPalette.successSurface,
                  shape: const CircleBorder(),
                  child: IconButton(
                    key: const ValueKey('mh14-call'),
                    tooltip: 'Gọi người phụ trách',
                    onPressed: onCall == null ? null : () => onCall!(phone),
                    icon: const Icon(
                      Icons.call_outlined,
                      color: AppColors.success,
                    ),
                  ),
                ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: AppColors.hairlineSoft),
          ),
          Text(addressLabel, style: _muted),
          const SizedBox(height: 2),
          Text(
            address,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          if (footnote != null) ...[
            const SizedBox(height: 8),
            Text(
              footnote!,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.success,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RefundPanel extends StatelessWidget {
  const _RefundPanel({required this.tracking, required this.done});

  final ReturnTracking tracking;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final refund = tracking.refund;
    final account = [
      tracking.refundBankName,
      tracking.refundAccountMasked,
    ].whereType<String>().join(' ');
    return Container(
      key: ValueKey(done ? 'mh14-refund-done' : 'mh14-refund-pending'),
      padding: const EdgeInsets.all(12),
      decoration: _panel(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row('Tiền hàng', formatVnd(tracking.merchandiseVnd)),
          _row('Phí giao ban đầu', formatVnd(tracking.deliveryFeeVnd)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1, color: AppColors.hairlineSoft),
          ),
          _row(
            done ? 'Đã hoàn' : 'Số tiền hoàn',
            formatVnd(refund?.amountVnd ?? tracking.refundAmountVnd),
            strong: true,
          ),
          if (account.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Tài khoản nhận: $account', style: _muted),
          ],
          if (done && refund != null) ...[
            const SizedBox(height: 4),
            Text(
              refund.hasTransferEvidence
                  ? 'Cửa hàng đã lưu bằng chứng chuyển khoản lúc '
                        '${_dateTime(refund.refundedAt)}.'
                  : 'Ghi nhận lúc ${_dateTime(refund.refundedAt)}.',
              style: _muted,
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool strong = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label, style: _body)),
        Text(
          value,
          style: TextStyle(
            fontSize: strong ? 15 : 13,
            fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
      ],
    ),
  );
}

class ReturnItemsCard extends StatefulWidget {
  const ReturnItemsCard({required this.items, super.key});

  final List<ReturnTrackingItem> items;

  @override
  State<ReturnItemsCard> createState() => _ReturnItemsCardState();
}

class _ReturnItemsCardState extends State<ReturnItemsCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final total = widget.items.fold<int>(0, (sum, i) => sum + i.quantity);
    return Container(
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const ValueKey('mh14-items-toggle'),
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Chi tiết hàng thu hồi', style: _title),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.softCloud,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$total món',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ash,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.ash,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1, color: AppColors.hairlineSoft),
            if (widget.items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Cửa hàng chưa chốt danh sách hàng cần thu hồi.',
                  style: _muted,
                ),
              )
            else
              for (final item in widget.items)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                            if (item.variantLabel != null)
                              Text(item.variantLabel!, style: _muted),
                          ],
                        ),
                      ),
                      Text(
                        'SL ${item.quantity}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                'Chỉ thu hồi hàng bạn thực nhận; món giao thiếu không cần trả.',
                style: _muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
