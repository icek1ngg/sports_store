import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/utils/display_formatters.dart';
import '../../../../shared/widgets/foreground_refresh.dart';
import '../../domain/models/return_request_failure.dart';
import '../../domain/models/return_tracking.dart';
import '../../domain/repositories/return_video_picker.dart';
import '../view_models/return_request_providers.dart';
import '../view_models/return_tracking_timeline.dart';
import '../view_models/return_tracking_view_model.dart';
import '../widgets/create_return_sections.dart';
import '../widgets/return_request_details_sections.dart';
import '../widgets/return_tracking_sections.dart';

/// Customer return tracking: progress, pickup person, more-info requests,
/// inspection result, refund record or free redelivery.
class ReturnTrackingPage extends ConsumerWidget {
  const ReturnTrackingPage({
    required this.returnId,
    required this.onBack,
    this.onCall,
    super.key,
  });

  final String returnId;
  final VoidCallback onBack;

  /// Opens the phone dialer. Defaults to a `tel:` launch.
  final ValueChanged<String>? onCall;

  static Future<void> launchDialer(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: digits));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = returnTrackingProvider(returnId);
    final state = ref.watch(provider);
    final viewModel = ref.read(provider.notifier);
    final tracking = state.tracking;

    final Widget body;
    if (tracking == null) {
      body = Center(
        child: state.loading
            ? const CircularProgressIndicator(key: ValueKey('mh14-loading'))
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      key: const ValueKey('mh14-load-error'),
                      _loadMessage(state.loadFailure),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        color: AppColors.charcoal,
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: viewModel.refresh,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ink,
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              ),
      );
    } else {
      final steps = buildReturnTimeline(tracking);
      final info = tracking.infoRequest;
      body = RefreshIndicator(
        onRefresh: viewModel.refresh,
        child: ListView(
          key: const ValueKey('mh14-scroll'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (state.isStale) ...[
              ReturnStaleBanner(
                confirmedAt: tracking.refreshedAt,
                message: _loadMessage(state.loadFailure),
                onRetry: state.loading ? null : viewModel.refresh,
              ),
              const SizedBox(height: 12),
            ],
            ReturnSummaryCard(tracking: tracking, steps: steps),
            if (info != null) ...[
              const SizedBox(height: 16),
              _InfoRequestCard(returnId: returnId, request: info, state: state),
            ],
            const SizedBox(height: 16),
            ReturnTimelineCard(
              tracking: tracking,
              steps: steps,
              onCall: onCall ?? launchDialer,
            ),
            // No collection happens after an initial rejection.
            if (tracking.status != ReturnRequestStatus.initiallyRejected) ...[
              const SizedBox(height: 16),
              ReturnItemsCard(items: tracking.items),
            ],
          ],
        ),
      );
    }

    return AppTheme.notificationsScope(
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              ReturnTrackingHeader(
                onBack: onBack,
                onRefresh: state.loading ? null : viewModel.refresh,
              ),
              if (state.loading && tracking != null)
                const LinearProgressIndicator(minHeight: 2),
              Expanded(
                // Shared foreground freshness policy (same as MH07/MH09/MH17):
                // picks up manager decisions while the screen stays open.
                child: ForegroundRefresh(
                  enabled: tracking != null && !_isClosed(tracking),
                  canRefresh: () => viewModel.canPoll,
                  onRefresh: viewModel.poll,
                  child: body,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Final states: nothing further can change without a new request.
bool _isClosed(ReturnTracking t) =>
    t.status == ReturnRequestStatus.refunded ||
    t.status == ReturnRequestStatus.initiallyRejected ||
    t.status == ReturnRequestStatus.rejectedAfterInspection;

String _loadMessage(ReturnRequestFailure? failure) => switch (failure?.code) {
  ReturnRequestFailureCode.network => 'Không thể kết nối.',
  ReturnRequestFailureCode.returnNotFound ||
  ReturnRequestFailureCode.orderNotFound ||
  ReturnRequestFailureCode.permissionDenied =>
    'Không tìm thấy yêu cầu trả hàng của bạn.',
  ReturnRequestFailureCode.sessionExpired => 'Phiên đăng nhập đã hết hạn.',
  ReturnRequestFailureCode.backendUnavailable =>
    'Dịch vụ theo dõi trả hàng chưa sẵn sàng.',
  _ => 'Không tải được tiến độ mới.',
};

class _InfoRequestCard extends ConsumerStatefulWidget {
  const _InfoRequestCard({
    required this.returnId,
    required this.request,
    required this.state,
  });

  final String returnId;
  final ReturnInfoRequest request;
  final ReturnTrackingState state;

  @override
  ConsumerState<_InfoRequestCard> createState() => _InfoRequestCardState();
}

class _InfoRequestCardState extends ConsumerState<_InfoRequestCard> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.state.infoDescription,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final viewModel = ref.read(
      returnTrackingProvider(widget.returnId).notifier,
    );
    try {
      final video = await ref.read(returnVideoPickerProvider).pickVideo();
      if (!mounted || video == null) return;
      viewModel.setInfoVideo(video);
    } on ReturnVideoPickFailure catch (failure) {
      if (mounted) viewModel.reportVideoProblem(failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final state = widget.state;
    final viewModel = ref.read(
      returnTrackingProvider(widget.returnId).notifier,
    );
    final sending = state.infoPhase == ReturnInfoPhase.sending;
    final requestedAt = formatHanoiDateTime(request.requestedAt);

    return Container(
      key: const ValueKey('mh14-info-request'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ReturnPalette.creamSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ReturnPalette.creamBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.forum_outlined,
                size: 18,
                color: ReturnPalette.warningInk,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  request.isOpen
                      ? 'Cửa hàng cần thêm thông tin'
                      : 'Bạn đã gửi thông tin bổ sung',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: ReturnPalette.warningInk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.message,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Cửa hàng yêu cầu lúc $requestedAt',
                  style: const TextStyle(fontSize: 12, color: AppColors.mute),
                ),
              ],
            ),
          ),
          if (!request.isOpen) ...[
            const SizedBox(height: 8),
            Text(
              'Đã gửi lúc ${formatHanoiDateTime(request.respondedAt!)}. '
              'Cửa hàng đang xem xét, yêu cầu vẫn đang xử lý.',
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: ReturnPalette.warningInk,
              ),
            ),
          ] else ...[
            const SizedBox(height: 14),
            ReturnTextField(
              fieldKey: const ValueKey('mh14-info-description'),
              controller: _controller,
              label: 'Mô tả bổ sung',
              hint: 'Trả lời câu hỏi của cửa hàng',
              minLines: 3,
              maxLines: 5,
              maxLength: 1000,
              enabled: !sending,
              error: state.infoError,
              textCapitalization: TextCapitalization.sentences,
              onChanged: viewModel.setInfoDescription,
            ),
            const SizedBox(height: 8),
            ReturnVideoField(
              video: state.infoVideo,
              onPick: sending ? null : _pickVideo,
              onRemove: sending ? null : viewModel.removeInfoVideo,
              error: state.videoNotice,
              pickLabel: 'Thêm video bổ sung (không bắt buộc)',
              pickKey: const ValueKey('mh14-info-pick-video'),
            ),
            if (state.infoFailure != null) ...[
              const SizedBox(height: 12),
              ReturnFailureBanner(message: state.infoFailure!.message),
            ],
            const SizedBox(height: 14),
            SizedBox(
              height: 48,
              child: FilledButton(
                key: const ValueKey('mh14-info-send'),
                onPressed: sending ? null : viewModel.submitInfo,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  disabledBackgroundColor: AppColors.surfaceContainerHigh,
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(sending ? 'Đang gửi…' : 'Gửi bổ sung'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
