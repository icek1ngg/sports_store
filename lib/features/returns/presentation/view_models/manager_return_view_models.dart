import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../deliveries/data/repositories/operational_read_access.dart';
import '../../data/repositories/file_selector_evidence_picker.dart';
import '../../data/repositories/supabase_manager_return_repository.dart';
import '../../domain/repositories/manager_evidence_picker.dart';
import '../../domain/models/manager_return.dart';
import '../../domain/models/return_request_failure.dart';
import '../../domain/repositories/manager_return_repository.dart';

/// Real Supabase data in the app. The DEMO preview and tests override it.
/// Its own access epoch drops data when the signed-in account changes.
final managerReturnRepositoryProvider =
    Provider.autoDispose<ManagerReturnRepository>((ref) {
      final access = OperationalReadAccess(ref.watch(supabaseClientProvider));
      ref.onDispose(() => unawaited(access.dispose()));
      return SupabaseManagerReturnRepository(access: access);
    });

// ---------------------------------------------------------------- list ----

class ManagerReturnListState {
  const ManagerReturnListState({
    this.list,
    this.loading = true,
    this.failure,
    this.status,
    this.query = '',
  });

  /// Last confirmed page for [status] + [query]; kept when a refresh fails.
  final ManagerReturnList? list;
  final bool loading;
  final ReturnRequestFailure? failure;

  /// null = "Tất cả".
  final ReturnRequestStatus? status;
  final String query;

  bool get isStale => list != null && failure != null;

  ManagerReturnListState copyWith({
    ManagerReturnList? list,
    bool clearList = false,
    bool? loading,
    ReturnRequestFailure? failure,
    bool clearFailure = false,
    ReturnRequestStatus? status,
    bool clearStatus = false,
    String? query,
  }) => ManagerReturnListState(
    list: clearList ? null : (list ?? this.list),
    loading: loading ?? this.loading,
    failure: clearFailure ? null : (failure ?? this.failure),
    status: clearStatus ? null : (status ?? this.status),
    query: query ?? this.query,
  );
}

final managerReturnListProvider =
    NotifierProvider.autoDispose<
      ManagerReturnListViewModel,
      ManagerReturnListState
    >(ManagerReturnListViewModel.new);

class ManagerReturnListViewModel extends Notifier<ManagerReturnListState> {
  late ManagerReturnRepository _repository;
  int _epoch = 0;
  bool _inFlight = false;
  Timer? _debounce;

  static const searchDelay = Duration(milliseconds: 350);

  @override
  ManagerReturnListState build() {
    _repository = ref.watch(managerReturnRepositoryProvider);
    ref.onDispose(() => _debounce?.cancel());
    Future.microtask(refresh);
    return const ManagerReturnListState();
  }

  Future<void> refresh() => _load(quiet: false);

  bool get canPoll =>
      !_inFlight &&
      !state.loading &&
      state.list != null &&
      state.failure?.revokesAccess != true;

  Future<void> poll() async {
    if (canPoll) await _load(quiet: true);
  }

  void selectStatus(ReturnRequestStatus? status) {
    if (status == state.status) return;
    state = status == null
        ? state.copyWith(clearStatus: true)
        : state.copyWith(status: status);
    unawaited(refresh());
  }

  void setQuery(String value) {
    if (value == state.query) return;
    state = state.copyWith(query: value);
    _debounce?.cancel();
    _debounce = Timer(searchDelay, () => unawaited(refresh()));
  }

  Future<void> _load({required bool quiet}) async {
    final epoch = ++_epoch;
    _inFlight = true;
    if (!quiet) state = state.copyWith(loading: true);
    try {
      final list = await _repository.list(
        status: state.status,
        query: state.query,
      );
      if (!ref.mounted || epoch != _epoch) return;
      state = state.copyWith(list: list, loading: false, clearFailure: true);
    } on ReturnRequestFailure catch (failure) {
      if (!ref.mounted || epoch != _epoch) return;
      state = failure.revokesAccess
          ? ManagerReturnListState(
              loading: false,
              failure: failure,
              status: state.status,
              query: state.query,
            )
          : state.copyWith(loading: false, failure: failure);
    } finally {
      if (epoch == _epoch) _inFlight = false;
    }
  }
}

// -------------------------------------------------------------- detail ----

enum ManagerReturnPhase { idle, submitting }

class ManagerReturnDetailState {
  const ManagerReturnDetailState({
    this.detail,
    this.loading = true,
    this.loadFailure,
    this.phase = ManagerReturnPhase.idle,
    this.actionFailure,
    this.notice,
  });

  final ManagerReturnDetail? detail;
  final bool loading;
  final ReturnRequestFailure? loadFailure;
  final ManagerReturnPhase phase;
  final ReturnRequestFailure? actionFailure;

  /// One-shot confirmation shown after a successful command.
  final String? notice;

  bool get isStale => detail != null && loadFailure != null;
  bool get submitting => phase == ManagerReturnPhase.submitting;

  ManagerReturnDetailState copyWith({
    ManagerReturnDetail? detail,
    bool? loading,
    ReturnRequestFailure? loadFailure,
    bool clearLoadFailure = false,
    ManagerReturnPhase? phase,
    ReturnRequestFailure? actionFailure,
    bool clearActionFailure = false,
    String? notice,
    bool clearNotice = false,
  }) => ManagerReturnDetailState(
    detail: detail ?? this.detail,
    loading: loading ?? this.loading,
    loadFailure: clearLoadFailure ? null : (loadFailure ?? this.loadFailure),
    phase: phase ?? this.phase,
    actionFailure: clearActionFailure
        ? null
        : (actionFailure ?? this.actionFailure),
    notice: clearNotice ? null : (notice ?? this.notice),
  );
}

final managerReturnDetailProvider = NotifierProvider.autoDispose
    .family<ManagerReturnDetailViewModel, ManagerReturnDetailState, String>(
      ManagerReturnDetailViewModel.new,
    );

class ManagerReturnDetailViewModel extends Notifier<ManagerReturnDetailState> {
  ManagerReturnDetailViewModel(this.returnId);

  final String returnId;
  late ManagerReturnRepository _repository;
  int _epoch = 0;
  bool _inFlight = false;

  /// Idempotency key reused while the same command is retried.
  String? _pendingKey;
  String? _pendingSignature;

  @override
  ManagerReturnDetailState build() {
    _repository = ref.watch(managerReturnRepositoryProvider);
    Future.microtask(refresh);
    return const ManagerReturnDetailState();
  }

  Future<void> refresh() => _load(quiet: false);

  bool get canPoll =>
      !_inFlight &&
      !state.loading &&
      !state.submitting &&
      state.detail != null &&
      state.loadFailure?.revokesAccess != true;

  Future<void> poll() async {
    if (canPoll) await _load(quiet: true);
  }

  void clearNotice() => state = state.copyWith(clearNotice: true);

  Future<Uri> videoUrl(String path) => _repository.videoUrl(path);

  Future<void> _load({required bool quiet}) async {
    final epoch = ++_epoch;
    _inFlight = true;
    if (!quiet) state = state.copyWith(loading: true);
    try {
      final detail = await _repository.load(returnId);
      if (!ref.mounted || epoch != _epoch) return;
      state = state.copyWith(
        detail: detail,
        loading: false,
        clearLoadFailure: true,
      );
    } on ReturnRequestFailure catch (failure) {
      if (!ref.mounted || epoch != _epoch) return;
      state = failure.revokesAccess
          ? ManagerReturnDetailState(loading: false, loadFailure: failure)
          : state.copyWith(loading: false, loadFailure: failure);
    } finally {
      if (epoch == _epoch) _inFlight = false;
    }
  }

  String _keyFor(String signature) {
    if (_pendingSignature != signature) {
      _pendingKey = const Uuid().v4();
      _pendingSignature = signature;
    }
    return _pendingKey!;
  }

  /// Returns true when the server confirmed the command.
  Future<bool> _command(
    String signature,
    Future<void> Function(String requestId) send,
    String notice,
  ) async {
    if (state.submitting) return false; // double tap
    final key = _keyFor(signature);
    state = state.copyWith(
      phase: ManagerReturnPhase.submitting,
      clearActionFailure: true,
      clearNotice: true,
    );
    try {
      await send(key);
      if (!ref.mounted) return true;
      _pendingKey = null;
      _pendingSignature = null;
      state = state.copyWith(phase: ManagerReturnPhase.idle, notice: notice);
      await refresh();
      return true;
    } on ReturnRequestFailure catch (failure) {
      if (!ref.mounted) return false;
      // Unknown outcome: keep the key so "Thử lại" cannot act twice.
      if (!failure.isAmbiguous) {
        _pendingKey = null;
        _pendingSignature = null;
      }
      state = state.copyWith(
        phase: ManagerReturnPhase.idle,
        actionFailure: failure,
      );
      if (failure.code == ReturnRequestFailureCode.stateConflict) {
        await refresh();
      }
      return false;
    }
  }

  Future<bool> approveCollection({
    required List<ManagerCollectionLine> lines,
    required String shipperId,
  }) {
    final sorted = [...lines]
      ..sort((a, b) => a.orderItemId.compareTo(b.orderItemId));
    final signature =
        'approve|$shipperId|'
        '${sorted.map((l) => '${l.orderItemId}:${l.quantity}').join(',')}';
    return _command(
      signature,
      (key) => _repository.approveCollection(
        returnId: returnId,
        requestId: key,
        lines: sorted,
        shipperId: shipperId,
      ),
      'Đã duyệt lấy hàng và phân công shipper. Khách sẽ thấy "Chờ lấy hàng".',
    );
  }

  Future<bool> reject(String reason) {
    final normalized = reason.trim().replaceAll(RegExp(r'\s+'), ' ');
    return _command(
      'reject|$normalized',
      (key) => _repository.reject(
        returnId: returnId,
        requestId: key,
        reason: normalized,
      ),
      'Đã từ chối yêu cầu. Hàng vẫn ở khách, không tạo thu hồi hay hoàn tiền.',
    );
  }

  static String _normalize(String text) =>
      text.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Object names derive from the command key, so retrying the same command
  /// overwrites nothing and reuses the files already uploaded.
  Future<List<String>> _upload(
    String key,
    ManagerEvidenceKind kind,
    List<ManagerEvidenceFile> files,
  ) async => [
    for (final (index, file) in files.indexed)
      await _repository.uploadEvidence(
        returnId: returnId,
        kind: kind,
        objectName: '$key-$index.${file.name.split('.').last.toLowerCase()}',
        file: file,
      ),
  ];

  static String _filesSignature(List<ManagerEvidenceFile> files) =>
      files.map((f) => '${f.name}:${f.bytes.length}').join(',');

  Future<bool> requestInfo(String message) {
    final normalized = _normalize(message);
    return _command(
      'info|$normalized',
      (key) => _repository.requestInfo(
        returnId: returnId,
        requestId: key,
        message: normalized,
      ),
      'Đã gửi yêu cầu bổ sung. Khách sẽ thấy trong theo dõi yêu cầu.',
    );
  }

  Future<bool> receive() {
    final detail = state.detail;
    final task = detail?.pickupTask;
    if (detail == null || task == null) return Future.value(false);
    return _command(
      'receive|${task.taskId}',
      (key) => _repository.receive(
        returnId: returnId,
        taskId: task.taskId,
        requestId: key,
        items: detail.returnItems,
      ),
      'Đã ghi nhận cửa hàng nhận đủ hàng. Chuyển sang kiểm tra.',
    );
  }

  Future<bool> acceptInspection({
    required List<ManagerInspectionLine> lines,
    List<ManagerEvidenceFile> evidence = const [],
  }) {
    final sorted = [...lines]
      ..sort((a, b) => a.returnItemId.compareTo(b.returnItemId));
    final signature =
        'accept|${sorted.map((l) => '${l.returnItemId}:${l.sellableQuantity}:${l.damagedQuantity}').join(',')}'
        '|${_filesSignature(evidence)}';
    return _command(signature, (key) async {
      final paths = await _upload(
        key,
        ManagerEvidenceKind.inspection,
        evidence,
      );
      await _repository.acceptInspection(
        returnId: returnId,
        requestId: key,
        lines: sorted,
        evidencePaths: paths,
      );
    }, 'Đã chấp nhận sau kiểm tra. Hàng bán được đã nhập lại kho.');
  }

  Future<bool> rejectInspection({
    required String reason,
    required List<ManagerEvidenceFile> evidence,
  }) {
    final normalized = _normalize(reason);
    return _command(
      'reject-inspection|$normalized|${_filesSignature(evidence)}',
      (key) async {
        final paths = await _upload(
          key,
          ManagerEvidenceKind.inspection,
          evidence,
        );
        await _repository.rejectInspection(
          returnId: returnId,
          requestId: key,
          reason: normalized,
          evidencePaths: paths,
        );
      },
      'Đã từ chối sau kiểm tra. Phân công giao lại miễn phí cho khách.',
    );
  }

  Future<bool> recordRefund({
    required DateTime transferredAt,
    required ManagerEvidenceFile evidence,
  }) {
    final detail = state.detail;
    if (detail == null) return Future.value(false);
    final amount = detail.refundAmountVnd;
    return _command('refund|$amount|${transferredAt.toUtc().toIso8601String()}|'
        '${_filesSignature([evidence])}', (key) async {
      final paths = await _upload(key, ManagerEvidenceKind.refund, [evidence]);
      await _repository.recordRefund(
        returnId: returnId,
        requestId: key,
        amountVnd: amount,
        transferredAt: transferredAt,
        evidencePath: paths.single,
      );
    }, 'Đã ghi nhận hoàn tiền. Yêu cầu đã đóng.');
  }

  Future<bool> assignRedelivery(String shipperId) => _command(
    'redelivery|$shipperId',
    (key) => _repository.assignRedelivery(
      returnId: returnId,
      requestId: key,
      shipperId: shipperId,
    ),
    'Đã phân công giao lại miễn phí. Không thu COD lần hai.',
  );

  Future<Uri> evidenceUrl(ManagerEvidenceKind kind, String path) =>
      _repository.evidenceUrl(kind, path);
}

final managerEvidencePickerProvider = Provider<ManagerEvidencePicker>(
  (ref) => const FileSelectorEvidencePicker(),
);
