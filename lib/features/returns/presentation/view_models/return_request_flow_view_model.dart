import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/return_reason.dart';
import '../../domain/models/return_request_failure.dart';
import '../../domain/models/return_request_submission.dart';
import 'return_request_providers.dart';

/// Everything the customer typed across steps 1–2. Lives as long as the flow
/// is on screen, so going back to step 1 never loses step 2 input.
class ReturnRequestDraft {
  const ReturnRequestDraft({
    this.reason,
    this.description = '',
    this.video,
    this.bankName = '',
    this.accountNumber = '',
    this.accountHolder = '',
  });

  final ReturnReason? reason;
  final String description;
  final ReturnVideoFile? video;
  final String bankName;
  final String accountNumber;
  final String accountHolder;

  String get normalizedDescription => _collapse(description);
  String get normalizedBankName => _collapse(bankName);
  String get normalizedAccountNumber =>
      accountNumber.replaceAll(RegExp(r'\s'), '');
  String get normalizedAccountHolder => _collapse(accountHolder).toUpperCase();

  ReturnRequestDraft copyWith({
    ReturnReason? reason,
    String? description,
    ReturnVideoFile? video,
    bool clearVideo = false,
    String? bankName,
    String? accountNumber,
    String? accountHolder,
  }) => ReturnRequestDraft(
    reason: reason ?? this.reason,
    description: description ?? this.description,
    video: clearVideo ? null : (video ?? this.video),
    bankName: bankName ?? this.bankName,
    accountNumber: accountNumber ?? this.accountNumber,
    accountHolder: accountHolder ?? this.accountHolder,
  );

  /// Same rules as `submit_return_request`; the server stays authoritative.
  Map<ReturnDraftField, String> validate() {
    final errors = <ReturnDraftField, String>{};
    if (reason == null) errors[ReturnDraftField.reason] = 'Chọn một lý do.';
    final desc = normalizedDescription.length;
    if (desc < 10) {
      errors[ReturnDraftField.description] = 'Nhập tối thiểu 10 ký tự.';
    } else if (desc > 1000) {
      errors[ReturnDraftField.description] = 'Mô tả tối đa 1000 ký tự.';
    }
    if (video == null) {
      errors[ReturnDraftField.video] = 'Cần video quay lúc mở kiện hàng.';
    }
    if (!_between(normalizedBankName.length, 2, 100)) {
      errors[ReturnDraftField.bankName] = 'Nhập tên ngân hàng.';
    }
    if (!RegExp(r'^[0-9]{6,20}$').hasMatch(normalizedAccountNumber)) {
      errors[ReturnDraftField.accountNumber] = 'Số tài khoản gồm 6–20 chữ số.';
    }
    if (!_between(normalizedAccountHolder.length, 2, 100)) {
      errors[ReturnDraftField.accountHolder] = 'Nhập tên chủ tài khoản.';
    }
    return errors;
  }

  bool sameSubmission(ReturnRequestDraft other) =>
      reason == other.reason &&
      normalizedDescription == other.normalizedDescription &&
      identical(video, other.video) &&
      normalizedBankName == other.normalizedBankName &&
      normalizedAccountNumber == other.normalizedAccountNumber &&
      normalizedAccountHolder == other.normalizedAccountHolder;

  static String _collapse(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');
  static bool _between(int value, int min, int max) =>
      value >= min && value <= max;
}

enum ReturnDraftField {
  reason,
  description,
  video,
  bankName,
  accountNumber,
  accountHolder,
}

enum ReturnSubmitPhase { editing, uploading, submitting, succeeded }

class ReturnRequestFlowState {
  const ReturnRequestFlowState({
    this.draft = const ReturnRequestDraft(),
    this.phase = ReturnSubmitPhase.editing,
    this.showErrors = false,
    this.failure,
    this.receipt,
    this.videoNotice,
  });

  final ReturnRequestDraft draft;
  final ReturnSubmitPhase phase;
  final bool showErrors;
  final ReturnRequestFailure? failure;
  final ReturnRequestReceipt? receipt;

  /// Local problem with the last picked file (shown under the video field).
  final String? videoNotice;

  bool get isBusy =>
      phase == ReturnSubmitPhase.uploading ||
      phase == ReturnSubmitPhase.submitting;

  Map<ReturnDraftField, String> get visibleErrors =>
      showErrors ? draft.validate() : const {};

  ReturnRequestFlowState copyWith({
    ReturnRequestDraft? draft,
    ReturnSubmitPhase? phase,
    bool? showErrors,
    ReturnRequestFailure? failure,
    bool clearFailure = false,
    ReturnRequestReceipt? receipt,
    String? videoNotice,
    bool clearVideoNotice = false,
  }) => ReturnRequestFlowState(
    draft: draft ?? this.draft,
    phase: phase ?? this.phase,
    showErrors: showErrors ?? this.showErrors,
    failure: clearFailure ? null : (failure ?? this.failure),
    receipt: receipt ?? this.receipt,
    videoNotice: clearVideoNotice ? null : (videoNotice ?? this.videoNotice),
  );
}

final returnRequestFlowProvider = NotifierProvider.autoDispose
    .family<ReturnRequestFlowViewModel, ReturnRequestFlowState, String>(
      ReturnRequestFlowViewModel.new,
    );

class _PendingSubmission {
  _PendingSubmission(this.requestId, this.draft);

  final String requestId;
  final ReturnRequestDraft draft;
  String? videoPath;
}

class ReturnRequestFlowViewModel extends Notifier<ReturnRequestFlowState> {
  ReturnRequestFlowViewModel(this.orderId);

  final String orderId;
  _PendingSubmission? _pending;

  @override
  ReturnRequestFlowState build() => const ReturnRequestFlowState();

  void _edit(ReturnRequestDraft Function(ReturnRequestDraft) change) {
    if (state.isBusy || state.phase == ReturnSubmitPhase.succeeded) return;
    state = state.copyWith(draft: change(state.draft), clearFailure: true);
  }

  void setReason(ReturnReason reason) =>
      _edit((d) => d.copyWith(reason: reason));
  void setDescription(String value) =>
      _edit((d) => d.copyWith(description: value));
  void setVideo(ReturnVideoFile video) {
    _edit((d) => d.copyWith(video: video));
    state = state.copyWith(clearVideoNotice: true);
  }

  void removeVideo() => _edit((d) => d.copyWith(clearVideo: true));
  void setBankName(String value) => _edit((d) => d.copyWith(bankName: value));
  void setAccountNumber(String value) =>
      _edit((d) => d.copyWith(accountNumber: value));
  void setAccountHolder(String value) =>
      _edit((d) => d.copyWith(accountHolder: value));

  /// Rejects a picked file locally (wrong type/size/unreadable) without
  /// touching the draft's current video.
  void reportVideoProblem(String message) {
    if (state.isBusy) return;
    state = state.copyWith(videoNotice: message);
  }

  Future<void> submit() async {
    if (state.isBusy || state.phase == ReturnSubmitPhase.succeeded) return;
    final draft = state.draft;
    if (draft.validate().isNotEmpty) {
      state = state.copyWith(showErrors: true, clearFailure: true);
      return;
    }
    // Reuse the idempotency key only for an unchanged draft after an
    // ambiguous attempt; any edit starts a new request.
    final previous = _pending;
    final pending = previous != null && previous.draft.sameSubmission(draft)
        ? previous
        : _PendingSubmission(const Uuid().v4(), draft);
    _pending = pending;
    final repository = ref.read(returnRequestRepositoryProvider);

    try {
      state = state.copyWith(
        phase: ReturnSubmitPhase.uploading,
        showErrors: true,
        clearFailure: true,
      );
      pending.videoPath ??= await repository.uploadVideo(
        orderId: orderId,
        requestId: pending.requestId,
        video: draft.video!,
      );
      if (!ref.mounted) return;
      state = state.copyWith(phase: ReturnSubmitPhase.submitting);
      final receipt = await repository.submit(
        ReturnRequestCommand(
          orderId: orderId,
          requestId: pending.requestId,
          reason: draft.reason!,
          description: draft.normalizedDescription,
          videoObjectPath: pending.videoPath!,
          bankName: draft.normalizedBankName,
          accountNumber: draft.normalizedAccountNumber,
          accountHolder: draft.normalizedAccountHolder,
        ),
      );
      if (!ref.mounted) return;
      _pending = null;
      state = state.copyWith(
        phase: ReturnSubmitPhase.succeeded,
        receipt: receipt,
        clearFailure: true,
      );
      ref.invalidate(returnRequestContextProvider(orderId));
    } on ReturnRequestFailure catch (failure) {
      if (!ref.mounted) return;
      if (!failure.isAmbiguous) _pending = null;
      state = state.copyWith(
        phase: ReturnSubmitPhase.editing,
        failure: failure,
      );
    } catch (_) {
      if (!ref.mounted) return;
      // Preserve the request id after an ambiguous server response.
      state = state.copyWith(
        phase: ReturnSubmitPhase.editing,
        failure: const ReturnRequestFailure(
          ReturnRequestFailureCode.unexpected,
        ),
      );
    }
  }
}
