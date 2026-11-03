import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../deliveries/data/repositories/operational_read_access.dart';
import '../../data/repositories/supabase_return_tracking_repository.dart';
import '../../domain/models/return_request_failure.dart';
import '../../domain/models/return_request_submission.dart';
import '../../domain/models/return_tracking.dart';
import '../../domain/repositories/return_tracking_repository.dart';

/// Real Supabase data in the app. The DEMO preview and tests override it.
/// Its own access epoch (default read timeout) drops data on account change.
final returnTrackingRepositoryProvider =
    Provider.autoDispose<ReturnTrackingRepository>((ref) {
      final access = OperationalReadAccess(ref.watch(supabaseClientProvider));
      ref.onDispose(() => unawaited(access.dispose()));
      return SupabaseReturnTrackingRepository(access: access);
    });

enum ReturnInfoPhase { editing, sending, sent }

class ReturnTrackingState {
  const ReturnTrackingState({
    this.tracking,
    this.loading = true,
    this.loadFailure,
    this.infoDescription = '',
    this.infoVideo,
    this.infoPhase = ReturnInfoPhase.editing,
    this.infoFailure,
    this.infoShowErrors = false,
    this.videoNotice,
  });

  /// Last confirmed snapshot; kept when a refresh fails.
  final ReturnTracking? tracking;
  final bool loading;
  final ReturnRequestFailure? loadFailure;

  final String infoDescription;
  final ReturnVideoFile? infoVideo;
  final ReturnInfoPhase infoPhase;
  final ReturnRequestFailure? infoFailure;
  final bool infoShowErrors;
  final String? videoNotice;

  /// Showing stale data after a failed refresh.
  bool get isStale => tracking != null && loadFailure != null;

  String get normalizedInfo =>
      infoDescription.trim().replaceAll(RegExp(r'\s+'), ' ');

  String? get infoError {
    if (!infoShowErrors) return null;
    final length = normalizedInfo.length;
    if (length < 10) return 'Nhập tối thiểu 10 ký tự.';
    if (length > 1000) return 'Tối đa 1000 ký tự.';
    return null;
  }

  ReturnTrackingState copyWith({
    ReturnTracking? tracking,
    bool? loading,
    ReturnRequestFailure? loadFailure,
    bool clearLoadFailure = false,
    String? infoDescription,
    ReturnVideoFile? infoVideo,
    bool clearInfoVideo = false,
    ReturnInfoPhase? infoPhase,
    ReturnRequestFailure? infoFailure,
    bool clearInfoFailure = false,
    bool? infoShowErrors,
    String? videoNotice,
    bool clearVideoNotice = false,
  }) => ReturnTrackingState(
    tracking: tracking ?? this.tracking,
    loading: loading ?? this.loading,
    loadFailure: clearLoadFailure ? null : (loadFailure ?? this.loadFailure),
    infoDescription: infoDescription ?? this.infoDescription,
    infoVideo: clearInfoVideo ? null : (infoVideo ?? this.infoVideo),
    infoPhase: infoPhase ?? this.infoPhase,
    infoFailure: clearInfoFailure ? null : (infoFailure ?? this.infoFailure),
    infoShowErrors: infoShowErrors ?? this.infoShowErrors,
    videoNotice: clearVideoNotice ? null : (videoNotice ?? this.videoNotice),
  );
}

final returnTrackingProvider = NotifierProvider.autoDispose
    .family<ReturnTrackingViewModel, ReturnTrackingState, String>(
      ReturnTrackingViewModel.new,
    );

class ReturnTrackingViewModel extends Notifier<ReturnTrackingState> {
  ReturnTrackingViewModel(this.returnId);

  final String returnId;
  int _loadEpoch = 0;
  String? _pendingInfoKey;
  String? _pendingInfoSignature;

  /// Watched (not read) so the autoDispose repository — and its auth epoch —
  /// lives as long as this screen instead of being recreated per call.
  late ReturnTrackingRepository _repository;

  @override
  ReturnTrackingState build() {
    _repository = ref.watch(returnTrackingRepositoryProvider);
    Future.microtask(refresh);
    return const ReturnTrackingState();
  }

  bool _inFlight = false;

  /// Explicit reload (open, pull-to-refresh, "Tải lại", "Thử lại").
  Future<void> refresh() => _load(quiet: false);

  /// Foreground freshness check: no spinner; skipped while a read runs,
  /// before the first snapshot, or after access was revoked.
  Future<void> poll() async {
    if (!canPoll) return;
    await _load(quiet: true);
  }

  bool get canPoll =>
      !_inFlight &&
      !state.loading &&
      state.tracking != null &&
      state.loadFailure?.revokesAccess != true;

  Future<void> _load({required bool quiet}) async {
    final epoch = ++_loadEpoch;
    _inFlight = true;
    if (!quiet) state = state.copyWith(loading: true);
    try {
      final tracking = await _repository.load(returnId);
      if (!ref.mounted || epoch != _loadEpoch) return;
      if (tracking.returnId != returnId) {
        throw const ReturnRequestFailure(ReturnRequestFailureCode.unexpected);
      }
      state = state.copyWith(
        tracking: tracking,
        loading: false,
        clearLoadFailure: true,
      );
    } on ReturnRequestFailure catch (failure) {
      if (!ref.mounted || epoch != _loadEpoch) return;
      if (failure.revokesAccess) {
        // Another account, lost ownership or expired session: never keep
        // the previous private snapshot on screen.
        state = ReturnTrackingState(loading: false, loadFailure: failure);
      } else {
        // Keep the last confirmed snapshot visible and labeled as such.
        state = state.copyWith(loading: false, loadFailure: failure);
      }
    } finally {
      if (epoch == _loadEpoch) _inFlight = false;
    }
  }

  bool get _canEditInfo => state.infoPhase == ReturnInfoPhase.editing;

  void setInfoDescription(String value) {
    if (!_canEditInfo) return;
    state = state.copyWith(infoDescription: value, clearInfoFailure: true);
  }

  void setInfoVideo(ReturnVideoFile video) {
    if (!_canEditInfo) return;
    state = state.copyWith(
      infoVideo: video,
      clearVideoNotice: true,
      clearInfoFailure: true,
    );
  }

  void removeInfoVideo() {
    if (!_canEditInfo) return;
    state = state.copyWith(clearInfoVideo: true);
  }

  void reportVideoProblem(String message) {
    if (!_canEditInfo) return;
    state = state.copyWith(videoNotice: message);
  }

  Future<void> submitInfo() async {
    if (!_canEditInfo) return;
    final request = state.tracking?.infoRequest;
    if (request == null || !request.isOpen) return;
    state = state.copyWith(infoShowErrors: true, clearInfoFailure: true);
    if (state.infoError != null) return;

    final description = state.normalizedInfo;
    final video = state.infoVideo;
    final signature = '$description|${identityHashCode(video)}';
    if (_pendingInfoSignature != signature) {
      _pendingInfoKey = const Uuid().v4();
      _pendingInfoSignature = signature;
    }
    state = state.copyWith(infoPhase: ReturnInfoPhase.sending);
    try {
      await _repository.submitAdditionalInfo(
        returnId: returnId,
        requestId: _pendingInfoKey!,
        description: description,
        video: video,
      );
      if (!ref.mounted) return;
      _pendingInfoKey = null;
      _pendingInfoSignature = null;
      state = state.copyWith(infoPhase: ReturnInfoPhase.sent);
      await refresh();
    } on ReturnRequestFailure catch (failure) {
      if (!ref.mounted) return;
      if (!failure.isAmbiguous) {
        _pendingInfoKey = null;
        _pendingInfoSignature = null;
      }
      state = state.copyWith(
        infoPhase: ReturnInfoPhase.editing,
        infoFailure: failure,
      );
    }
  }
}
