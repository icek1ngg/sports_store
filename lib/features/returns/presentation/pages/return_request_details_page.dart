import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/utils/display_formatters.dart';
import '../../domain/repositories/return_video_picker.dart';
import '../view_models/return_request_flow_view_model.dart';
import '../view_models/return_request_providers.dart';
import '../widgets/create_return_sections.dart';
import '../widgets/return_request_details_sections.dart';

/// MH13 step 2: description, unboxing video and refund account, then submit.
///
/// All input lives in [returnRequestFlowProvider] so going back to step 1 and
/// returning keeps it.
class ReturnRequestDetailsPage extends ConsumerStatefulWidget {
  const ReturnRequestDetailsPage({
    required this.orderId,
    required this.totalPaidVnd,
    required this.onOpenReturn,
    super.key,
  });

  final String orderId;
  final int totalPaidVnd;

  /// Opens tracking (MH14) with the return id the server just created.
  final ValueChanged<String> onOpenReturn;

  static const stepLabel = 'Bước 2/2';

  @override
  ConsumerState<ReturnRequestDetailsPage> createState() =>
      _ReturnRequestDetailsPageState();
}

class _ReturnRequestDetailsPageState
    extends ConsumerState<ReturnRequestDetailsPage> {
  late final TextEditingController _description;
  late final TextEditingController _bankName;
  late final TextEditingController _accountNumber;
  late final TextEditingController _accountHolder;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(returnRequestFlowProvider(widget.orderId)).draft;
    _description = TextEditingController(text: draft.description);
    _bankName = TextEditingController(text: draft.bankName);
    _accountNumber = TextEditingController(text: draft.accountNumber);
    _accountHolder = TextEditingController(text: draft.accountHolder);
  }

  @override
  void dispose() {
    _description.dispose();
    _bankName.dispose();
    _accountNumber.dispose();
    _accountHolder.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final viewModel = ref.read(
      returnRequestFlowProvider(widget.orderId).notifier,
    );
    try {
      final video = await ref.read(returnVideoPickerProvider).pickVideo();
      if (!mounted || video == null) return;
      viewModel.setVideo(video);
    } on ReturnVideoPickFailure catch (failure) {
      if (mounted) viewModel.reportVideoProblem(failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = returnRequestFlowProvider(widget.orderId);
    final state = ref.watch(provider);
    final viewModel = ref.read(provider.notifier);
    final errors = state.visibleErrors;
    final editable = !state.isBusy;
    final reason = state.draft.reason;

    if (state.phase == ReturnSubmitPhase.succeeded) {
      return _SuccessView(
        receiptId: state.receipt?.returnRequestId,
        onDone: () => widget.onOpenReturn(state.receipt!.returnRequestId),
      );
    }

    return AppTheme.notificationsScope(
      child: PopScope(
        canPop: !state.isBusy,
        child: Scaffold(
          backgroundColor: AppColors.surface,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                CreateReturnHeader(
                  stepLabel: ReturnRequestDetailsPage.stepLabel,
                  onBack: state.isBusy
                      ? null
                      : () => Navigator.maybePop(context),
                ),
                Expanded(
                  child: ListView(
                    key: const ValueKey('mh13-details-scroll'),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      if (reason != null)
                        ReturnReasonSummary(
                          reason: reason,
                          onChange: editable
                              ? () => Navigator.maybePop(context)
                              : null,
                        ),
                      const SizedBox(height: 24),
                      ReturnFormSection(
                        title: 'Mô tả vấn đề',
                        helper: 'Cho cửa hàng biết sản phẩm gặp vấn đề gì.',
                        child: ReturnTextField(
                          fieldKey: const ValueKey('mh13-description'),
                          controller: _description,
                          label: 'Mô tả',
                          hint: 'Ví dụ: áo bị bung chỉ ở vai trái khi mở kiện',
                          minLines: 4,
                          maxLines: 6,
                          maxLength: 1000,
                          enabled: editable,
                          error: errors[ReturnDraftField.description],
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: viewModel.setDescription,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ReturnFormSection(
                        title: 'Video mở kiện',
                        helper:
                            'Quay liên tục từ lúc mở kiện, thấy rõ sản phẩm '
                            'và vấn đề gặp phải.',
                        child: ReturnVideoField(
                          video: state.draft.video,
                          onPick: editable ? _pickVideo : null,
                          onRemove: editable ? viewModel.removeVideo : null,
                          error:
                              state.videoNotice ??
                              errors[ReturnDraftField.video],
                        ),
                      ),
                      const SizedBox(height: 28),
                      ReturnFormSection(
                        title: 'Thông tin nhận hoàn tiền',
                        helper:
                            'Nếu yêu cầu được duyệt sau khi kiểm hàng, cửa '
                            'hàng chuyển khoản ${formatVnd(widget.totalPaidVnd)} '
                            '(tiền hàng và phí giao hàng ban đầu).',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ReturnTextField(
                              fieldKey: const ValueKey('mh13-bank-name'),
                              controller: _bankName,
                              label: 'Ngân hàng',
                              hint: 'Ví dụ: Vietcombank',
                              enabled: editable,
                              error: errors[ReturnDraftField.bankName],
                              textCapitalization: TextCapitalization.words,
                              onChanged: viewModel.setBankName,
                            ),
                            const SizedBox(height: 12),
                            ReturnTextField(
                              fieldKey: const ValueKey('mh13-account-number'),
                              controller: _accountNumber,
                              label: 'Số tài khoản',
                              enabled: editable,
                              error: errors[ReturnDraftField.accountNumber],
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9 ]'),
                                ),
                                LengthLimitingTextInputFormatter(24),
                              ],
                              onChanged: viewModel.setAccountNumber,
                            ),
                            const SizedBox(height: 12),
                            ReturnTextField(
                              fieldKey: const ValueKey('mh13-account-holder'),
                              controller: _accountHolder,
                              label: 'Chủ tài khoản',
                              hint: 'Như trên thẻ/ứng dụng ngân hàng',
                              enabled: editable,
                              error: errors[ReturnDraftField.accountHolder],
                              textCapitalization: TextCapitalization.characters,
                              onChanged: viewModel.setAccountHolder,
                            ),
                          ],
                        ),
                      ),
                      if (state.failure != null) ...[
                        const SizedBox(height: 20),
                        ReturnFailureBanner(message: state.failure!.message),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: ReturnSubmitBar(
            label: 'Gửi yêu cầu trả hàng',
            busyLabel: switch (state.phase) {
              ReturnSubmitPhase.uploading => 'Đang tải video lên…',
              ReturnSubmitPhase.submitting => 'Đang gửi yêu cầu…',
              _ => null,
            },
            onPressed: viewModel.submit,
            note:
                'Nhấn gửi đồng nghĩa bạn xác nhận thông tin và video cung cấp '
                'là chính xác.',
          ),
        ),
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.receiptId, required this.onDone});

  final String? receiptId;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return AppTheme.notificationsScope(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) onDone();
        },
        child: Scaffold(
          backgroundColor: AppColors.surface,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: ReturnPalette.successSurface,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 40,
                        color: AppColors.success,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Đã gửi yêu cầu trả hàng',
                    key: ValueKey('mh13-success'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Cửa hàng sẽ xem xét video và phản hồi sớm. Đây chưa phải '
                    'xác nhận hoàn tiền.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: AppColors.charcoal,
                    ),
                  ),
                  if (receiptId != null) ...[
                    const SizedBox(height: 16),
                    SelectableText(
                      'Mã yêu cầu: $receiptId',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.mute,
                      ),
                    ),
                  ],
                  const Spacer(flex: 2),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      key: const ValueKey('mh13-done'),
                      onPressed: onDone,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: const Text('Theo dõi yêu cầu'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
