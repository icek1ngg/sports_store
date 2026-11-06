import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/operational_providers.dart';
import '../../data/repositories/operational_read_access.dart';
import '../../domain/models/delivery_task.dart';
import '../../domain/models/delivery_task_details.dart';
import '../../domain/models/operational_failure.dart';
import '../../domain/models/outbound_failure_command.dart';
import '../../domain/models/outbound_task_command.dart';
import '../../domain/models/return_pickup_command.dart';
import 'delivery_task_detail_view_model.dart';
import 'outbound_result_gate.dart';
import 'return_pickup_providers.dart';

/// Screen-facing state for P08.2 return-pickup actions.
final class ReturnPickupState {
  const ReturnPickupState({
    required this.details,
    this.handoverStatus = const AsyncLoading<ReturnPickupHandoverStatus>(),
    this.busy = false,
    this.error,
    this.pendingCommand,
    this.requiresReadRetry = false,
    this.actionsDenied = false,
    this.acknowledged = false,
    this.confirmed = false,
    this.confirmedOperation,
  });

  const ReturnPickupState.initial()
    : this(details: const AsyncLoading<DeliveryTaskDetails>());

  final AsyncValue<DeliveryTaskDetails> details;
  final AsyncValue<ReturnPickupHandoverStatus> handoverStatus;
  final bool busy;
  final OutboundCommandFailure? error;
  final ReturnPickupCommand? pendingCommand;
  final bool requiresReadRetry;
  final bool actionsDenied;
  final bool acknowledged;
  final bool confirmed;
  final ReturnPickupOperation? confirmedOperation;

  bool get handoverReported =>
      handoverStatus.hasValue && handoverStatus.requireValue.reported;

  bool get handoverReadPending =>
      handoverStatus.isLoading || handoverStatus.hasError;

  bool get awaitingAuthoritativeRead =>
      acknowledged && (busy || requiresReadRetry);

  bool get canCollect =>
      !busy &&
      !actionsDenied &&
      !requiresReadRetry &&
      !acknowledged &&
      pendingCommand == null &&
      !confirmed &&
      details.hasValue &&
      ReturnPickupViewModel.canMutateDetails(details.requireValue);

  bool get canFail =>
      !busy &&
      !actionsDenied &&
      !requiresReadRetry &&
      !acknowledged &&
      pendingCommand == null &&
      !confirmed &&
      details.hasValue &&
      ReturnPickupViewModel.canMutateDetails(details.requireValue);

  /// A handover is available only after the server has exposed the current
  /// task as fully collected and the narrow marker says it has not been
  /// reported. The marker is intentionally fail-closed while loading/error.
  bool get canReportStoreHandover {
    if (busy || actionsDenied || requiresReadRetry || pendingCommand != null) {
      return false;
    }
    if (confirmed && confirmedOperation == ReturnPickupOperation.handover) {
      return false;
    }
    if (!details.hasValue || !handoverStatus.hasValue || handoverReported) {
      return false;
    }
    return ReturnPickupViewModel.canReportHandoverDetails(details.requireValue);
  }

  static const _unset = Object();

  ReturnPickupState copyWith({
    AsyncValue<DeliveryTaskDetails>? details,
    AsyncValue<ReturnPickupHandoverStatus>? handoverStatus,
    bool? busy,
    Object? error = _unset,
    Object? pendingCommand = _unset,
    bool? requiresReadRetry,
    bool? actionsDenied,
    bool? acknowledged,
    bool? confirmed,
    Object? confirmedOperation = _unset,
  }) => ReturnPickupState(
    details: details ?? this.details,
    handoverStatus: handoverStatus ?? this.handoverStatus,
    busy: busy ?? this.busy,
    error: identical(error, _unset)
        ? this.error
        : error as OutboundCommandFailure?,
    pendingCommand: identical(pendingCommand, _unset)
        ? this.pendingCommand
        : pendingCommand as ReturnPickupCommand?,
    requiresReadRetry: requiresReadRetry ?? this.requiresReadRetry,
    actionsDenied: actionsDenied ?? this.actionsDenied,
    acknowledged: acknowledged ?? this.acknowledged,
    confirmed: confirmed ?? this.confirmed,
    confirmedOperation: identical(confirmedOperation, _unset)
        ? this.confirmedOperation
        : confirmedOperation as ReturnPickupOperation?,
  );
}

final returnPickupViewModelProvider = NotifierProvider.autoDispose
    .family<ReturnPickupViewModel, ReturnPickupState, String>(
      ReturnPickupViewModel.new,
    );

/// Coordinates collect/fail writes and their authoritative read reconciliation.
final class ReturnPickupViewModel extends Notifier<ReturnPickupState> {
  ReturnPickupViewModel(this.taskId);

  final String taskId;
  OperationalSession? _activeSession;
  ProviderSubscription<AsyncValue<OperationalSession>>? _sessionSubscription;
  ProviderSubscription<AsyncValue<DeliveryTaskDetails>>? _detailSubscription;
  DeliveryTaskDetails? _currentDetails;
  ReturnPickupCommand? _acknowledgedCommand;
  void Function()? _closePendingKeepAlive;

  var _disposed = false;
  var _visible = true;
  var _sessionRevision = 0;
  var _sessionEventVersion = 0;
  var _detailEventVersion = 0;
  var _operationGeneration = 0;
  var _ackReadDeferred = false;
  var _rejectedReadDeferred = false;
  var _detailInvalidationDeferred = false;
  var _handoverReadVersion = 0;
  var _handoverReadInFlight = false;
  String? _handoverReadTaskId;

  int get sessionRevisionForConfirmation => _sessionRevision;

  @override
  ReturnPickupState build() {
    final resultGate = ref.read(outboundResultGateProvider(taskId).notifier);
    _disposed = false;
    _visible = true;
    _activeSession = null;
    _currentDetails = null;
    _acknowledgedCommand = null;
    _handoverReadVersion++;
    _handoverReadInFlight = false;
    _handoverReadTaskId = null;
    _sessionRevision++;
    _sessionEventVersion++;
    _detailEventVersion++;
    _operationGeneration++;
    _sessionSubscription = ref.container.listen<AsyncValue<OperationalSession>>(
      operationalSessionProvider,
      (_, next) => _scheduleSession(next),
      fireImmediately: true,
    );
    _listenToDetails();
    ref.onCancel(() {
      scheduleMicrotask(() {
        if (_disposed) return;
        _visible = false;
        _detailEventVersion++;
        _handoverReadVersion++;
        _handoverReadInFlight = false;
        _detailSubscription?.close();
        _detailSubscription = null;
        _currentDetails = null;
        if (_hasPendingWork) _retainPendingOperation();
      });
    });
    ref.onResume(() {
      scheduleMicrotask(() {
        if (_disposed) return;
        _visible = true;
        _listenToDetails();
        _resumeVisibleWork();
      });
    });
    ref.onDispose(() {
      scheduleMicrotask(() => resultGate.release(this));
      _disposed = true;
      _visible = false;
      _sessionRevision++;
      _operationGeneration++;
      _sessionEventVersion++;
      _detailEventVersion++;
      _sessionSubscription?.close();
      _sessionSubscription = null;
      _detailSubscription?.close();
      _detailSubscription = null;
      _closePendingKeepAlive?.call();
      _closePendingKeepAlive = null;
      _activeSession = null;
      _currentDetails = null;
      _acknowledgedCommand = null;
      _handoverReadVersion++;
      _handoverReadInFlight = false;
      _handoverReadTaskId = null;
    });
    return const ReturnPickupState.initial();
  }

  /// Collect every item and quantity in the immutable approved plan.
  Future<void> submitCollect({
    DeliveryTaskSnapshot? expectedTask,
    Iterable<DeliveryTaskItem>? expectedItems,
    Iterable<DeliveryTaskItem>? items,
    int? sessionRevision,
  }) async {
    if (!_readyForSubmit(sessionRevision)) return;
    final details = _readCurrentDetails();
    if (details == null || !canMutateDetails(details)) {
      _setValidationError(OutboundCommandFailureCode.staleState);
      return;
    }
    final task = details.task;
    if (expectedTask != null && expectedTask != task) {
      _setValidationError(OutboundCommandFailureCode.staleState);
      return;
    }
    final plan = (expectedItems ?? items ?? details.items).toList(
      growable: false,
    );
    if (!_sameItems(plan, details.items)) {
      _setValidationError(OutboundCommandFailureCode.staleState);
      return;
    }
    late final ReturnPickupCommand command;
    try {
      command = ReturnPickupCommand.collect(
        taskId: task.taskId,
        requestId: ref.read(returnPickupRequestIdProvider)(),
        returnRequestId: task.returnRequestId!,
        orderId: task.orderId!,
        items: _canonicalItems(plan),
      );
      if (!command.isValid) throw const FormatException('invalid pickup plan');
    } on Object {
      _setValidationError(OutboundCommandFailureCode.invalidData);
      return;
    }
    await _submitCommand(command);
  }

  /// Report handover of the exact, fully collected return plan. This is a
  /// separate idempotent write and does not mutate task, return-request,
  /// order, stock, COD, inspection, refund or store-receipt state.
  Future<void> submitHandover({
    DeliveryTaskSnapshot? expectedTask,
    Iterable<DeliveryTaskItem>? expectedItems,
    int? sessionRevision,
  }) async {
    if (!_readyForHandover(sessionRevision)) return;
    final details = _readCurrentDetails();
    if (details == null || !canReportHandoverDetails(details)) {
      _setValidationError(OutboundCommandFailureCode.staleState);
      return;
    }
    final task = details.task;
    if (expectedTask != null && expectedTask != task) {
      _setValidationError(OutboundCommandFailureCode.staleState);
      return;
    }
    final plan = (expectedItems ?? details.items).toList(growable: false);
    if (!_sameItems(plan, details.items) ||
        !plan.every((item) => item.quantityCollected == item.quantity)) {
      _setValidationError(OutboundCommandFailureCode.staleState);
      return;
    }
    late final ReturnPickupCommand command;
    try {
      command = ReturnPickupCommand.handover(
        taskId: task.taskId,
        requestId: ref.read(returnPickupRequestIdProvider)(),
        returnRequestId: task.returnRequestId!,
        orderId: task.orderId!,
        items: _canonicalItems(plan),
      );
      if (!command.isValid) throw const FormatException('invalid handover');
    } on Object {
      _setValidationError(OutboundCommandFailureCode.invalidData);
      return;
    }
    await _submitCommand(command);
  }

  /// Report pickup failure only while the task is assigned and custody is 0.
  Future<void> submitFailure({
    required OutboundFailureReason reason,
    String? description,
    DeliveryTaskSnapshot? expectedTask,
    int? sessionRevision,
  }) async {
    if (!_readyForSubmit(sessionRevision)) return;
    final details = _readCurrentDetails();
    if (details == null || !canMutateDetails(details)) {
      _setValidationError(OutboundCommandFailureCode.staleState);
      return;
    }
    final task = details.task;
    if (expectedTask != null && expectedTask != task) {
      _setValidationError(OutboundCommandFailureCode.staleState);
      return;
    }
    late final ReturnPickupCommand command;
    try {
      command = ReturnPickupCommand.fail(
        taskId: task.taskId,
        requestId: ref.read(returnPickupRequestIdProvider)(),
        returnRequestId: task.returnRequestId!,
        orderId: task.orderId!,
        reason: reason,
        description: description,
      );
      if (!command.isValid) throw const FormatException('invalid reason');
    } on Object {
      _setValidationError(OutboundCommandFailureCode.invalidData);
      return;
    }
    await _submitCommand(command);
  }

  Future<void> submit({
    required ReturnPickupOperation operation,
    DeliveryTaskSnapshot? expectedTask,
    Iterable<DeliveryTaskItem>? expectedItems,
    OutboundFailureReason? reason,
    String? description,
    int? sessionRevision,
  }) {
    if (operation == ReturnPickupOperation.collect) {
      return submitCollect(
        expectedTask: expectedTask,
        expectedItems: expectedItems,
        sessionRevision: sessionRevision,
      );
    }
    if (operation == ReturnPickupOperation.handover) {
      return submitHandover(
        expectedTask: expectedTask,
        expectedItems: expectedItems,
        sessionRevision: sessionRevision,
      );
    }
    if (reason == null) {
      _setValidationError(OutboundCommandFailureCode.invalidData);
      return Future<void>.value();
    }
    return submitFailure(
      reason: reason,
      description: description,
      expectedTask: expectedTask,
      sessionRevision: sessionRevision,
    );
  }

  Future<void> collect({
    DeliveryTaskSnapshot? expectedTask,
    Iterable<DeliveryTaskItem>? expectedItems,
    int? sessionRevision,
  }) => submitCollect(
    expectedTask: expectedTask,
    expectedItems: expectedItems,
    sessionRevision: sessionRevision,
  );

  Future<void> handover({
    DeliveryTaskSnapshot? expectedTask,
    Iterable<DeliveryTaskItem>? expectedItems,
    int? sessionRevision,
  }) => submitHandover(
    expectedTask: expectedTask,
    expectedItems: expectedItems,
    sessionRevision: sessionRevision,
  );

  Future<void> fail({
    required OutboundFailureReason reason,
    String? description,
    DeliveryTaskSnapshot? expectedTask,
    int? sessionRevision,
  }) => submitFailure(
    reason: reason,
    description: description,
    expectedTask: expectedTask,
    sessionRevision: sessionRevision,
  );

  /// Retries the same uncertain write, or performs read/list reconciliation
  /// only after an acknowledgement/read failure.
  Future<void> retry() async {
    if (!_isMounted || !_visible || state.busy) return;
    final session = _activeSession;
    if (!_isSessionUsable(session) || state.actionsDenied) return;
    final revision = _sessionRevision;
    final generation = _operationGeneration;
    final pending = state.pendingCommand;
    if (pending != null) {
      await _executeWrite(pending, session!, revision, generation);
      return;
    }
    final acknowledged = _acknowledgedCommand;
    if (state.acknowledged && acknowledged != null) {
      await _reconcileAcknowledged(
        acknowledged,
        session!,
        revision,
        generation,
      );
      return;
    }
    if (state.requiresReadRetry) {
      await _reloadAfterDefinitiveFailure(
        session!,
        revision,
        generation,
        preserveError: state.error,
      );
      return;
    }
    if (state.handoverStatus.hasError) {
      await retryHandoverStatus();
    }
  }

  /// Retry only the narrow handover-marker read. It never retries a write
  /// with a new request key and never reloads private return data.
  Future<void> retryHandoverStatus() async {
    if (!_isMounted || !_visible || _handoverReadInFlight) return;
    final session = _activeSession;
    if (!_isSessionUsable(session) || state.actionsDenied) return;
    final details = _readCurrentDetails();
    if (details == null || !canReportHandoverDetails(details)) return;
    final read = await _readHandoverStatus(
      session!,
      _sessionRevision,
      _operationGeneration,
      force: true,
      mustConfirm: false,
    );
    final acknowledged = _acknowledgedCommand;
    if (read &&
        acknowledged != null &&
        state.acknowledged &&
        !_disposed &&
        _isSessionUsable(_activeSession)) {
      await _reconcileAcknowledged(
        acknowledged,
        _activeSession!,
        _sessionRevision,
        _operationGeneration,
      );
    }
  }

  Future<void> _submitCommand(ReturnPickupCommand command) async {
    if (!_isMounted ||
        !_visible ||
        state.busy ||
        state.pendingCommand != null) {
      return;
    }
    final session = _activeSession;
    if (!_isSessionUsable(session) || state.actionsDenied) return;
    final revision = _sessionRevision;
    final generation = _operationGeneration;
    final gate = ref.read(outboundResultGateProvider(taskId).notifier);
    if (!gate.acquire(this)) return;
    state = state.copyWith(
      busy: true,
      error: null,
      pendingCommand: command,
      requiresReadRetry: false,
      acknowledged: false,
      confirmed: false,
      confirmedOperation: null,
    );
    _retainPendingOperation();
    await _executeWrite(command, session!, revision, generation);
  }

  Future<void> _executeWrite(
    ReturnPickupCommand command,
    OperationalSession session,
    int revision,
    int generation,
  ) async {
    if (!_isCurrent(session, revision, generation) || !_visible) return;
    try {
      final ack = await ref
          .read(returnPickupRepositoryProvider)
          .execute(command);
      if (!ack.matches(command)) throw const OutboundAcknowledgementFailure();
    } on Object catch (error) {
      if (!_isCurrent(session, revision, generation)) return;
      final failure = _mapFailure(error);
      if (_isAuthInvalidation(failure)) {
        _clearForAuth(failure);
        return;
      }
      if (_isUncertainWrite(failure)) {
        // The transaction may have committed. Preserve exact payload/key and
        // do not issue a speculative read or opposite operation.
        state = state.copyWith(
          busy: false,
          error: failure,
          pendingCommand: command,
          requiresReadRetry: false,
          acknowledged: false,
          confirmed: false,
        );
        _retainPendingOperation();
        return;
      }
      state = state.copyWith(
        busy: false,
        error: failure,
        pendingCommand: null,
        requiresReadRetry: true,
        acknowledged: false,
        confirmed: false,
        confirmedOperation: null,
      );
      _acknowledgedCommand = null;
      _retainPendingOperation();
      if (_visible) {
        await _reloadAfterDefinitiveFailure(
          session,
          revision,
          generation,
          preserveError: failure,
        );
      } else {
        _rejectedReadDeferred = true;
      }
      return;
    }

    if (!_isCurrent(session, revision, generation)) return;
    _acknowledgedCommand = command;
    state = state.copyWith(
      busy: true,
      error: null,
      pendingCommand: null,
      requiresReadRetry: false,
      acknowledged: true,
      confirmed: false,
      confirmedOperation: null,
    );
    _retainPendingOperation();
    await _reconcileAcknowledged(command, session, revision, generation);
  }

  Future<void> _reconcileAcknowledged(
    ReturnPickupCommand command,
    OperationalSession session,
    int revision,
    int generation,
  ) async {
    if (!_isCurrent(session, revision, generation)) return;
    if (!_visible) {
      _ackReadDeferred = true;
      state = state.copyWith(
        busy: false,
        requiresReadRetry: true,
        acknowledged: true,
      );
      _retainPendingOperation();
      return;
    }
    _ackReadDeferred = false;
    state = state.copyWith(busy: true, error: null);
    late final DeliveryTaskDetails details;
    try {
      details = await ref.read(returnPickupDetailsReloadProvider)(taskId);
      if (!_isCurrent(session, revision, generation)) return;
      _validateAcknowledgedDetails(command, details);
      _currentDetails = details;
      state = state.copyWith(details: AsyncData(details));
    } on Object catch (error) {
      if (!_isCurrent(session, revision, generation)) return;
      final failure = _mapFailure(error);
      if (_isAuthInvalidation(failure)) {
        _clearForAuth(failure);
        return;
      }
      state = state.copyWith(
        busy: false,
        error: failure,
        requiresReadRetry: true,
        pendingCommand: null,
        acknowledged: true,
        confirmed: false,
      );
      _retainPendingOperation();
      return;
    }

    // Collection and handover both leave the task in transit. Read the
    // separate marker before declaring the operation reconciled so reopening
    // MH11 cannot expose a duplicate handover action. P08.1-only fixtures may
    // not implement this capability; they remain blocked from handover but a
    // previously supported collect receipt can still be shown as committed.
    if (command.isCollect || command.isHandover) {
      final markerRead = await _readHandoverStatus(
        session,
        revision,
        generation,
        force: true,
        mustConfirm: command.isHandover,
      );
      if (!markerRead || !_isCurrent(session, revision, generation)) return;
    }

    if (!_isCurrent(session, revision, generation)) return;
    try {
      await ref.read(returnPickupTaskListReloadProvider)();
    } on Object catch (error) {
      if (!_isCurrent(session, revision, generation)) return;
      final failure = _mapFailure(error);
      if (_isAuthInvalidation(failure)) {
        _clearForAuth(failure);
        return;
      }
      state = state.copyWith(
        busy: false,
        error: failure,
        requiresReadRetry: true,
        acknowledged: true,
        confirmed: false,
      );
      _retainPendingOperation();
      return;
    }

    if (!_isCurrent(session, revision, generation)) return;
    if (!_visible) {
      _ackReadDeferred = true;
      state = state.copyWith(busy: false, requiresReadRetry: true);
      _retainPendingOperation();
      return;
    }
    state = state.copyWith(
      busy: false,
      error: null,
      pendingCommand: null,
      requiresReadRetry: false,
      acknowledged: true,
      confirmed: true,
      confirmedOperation: command.operation,
    );
    _acknowledgedCommand = null;
    _releasePendingOperationIfIdle();
  }

  Future<void> _reloadAfterDefinitiveFailure(
    OperationalSession session,
    int revision,
    int generation, {
    OutboundCommandFailure? preserveError,
  }) async {
    if (!_isCurrent(session, revision, generation)) return;
    if (!_visible) {
      _rejectedReadDeferred = true;
      state = state.copyWith(busy: false, requiresReadRetry: true);
      _retainPendingOperation();
      return;
    }
    _rejectedReadDeferred = false;
    state = state.copyWith(busy: true);
    try {
      final details = await ref.read(returnPickupDetailsReloadProvider)(taskId);
      if (!_isCurrent(session, revision, generation)) return;
      if (!_sameUuid(details.task.taskId, taskId)) {
        throw const OutboundCommandFailure(
          OutboundCommandFailureCode.invalidData,
        );
      }
      _currentDetails = details;
      state = state.copyWith(details: AsyncData(details));
      _maybeReadHandoverStatus(details);
      await ref.read(returnPickupTaskListReloadProvider)();
      if (!_isCurrent(session, revision, generation)) return;
      state = state.copyWith(
        busy: false,
        error: preserveError,
        requiresReadRetry: false,
        pendingCommand: null,
        acknowledged: false,
        confirmed: false,
        confirmedOperation: null,
      );
      _releasePendingOperationIfIdle();
    } on Object catch (error) {
      if (!_isCurrent(session, revision, generation)) return;
      final failure = _mapFailure(error);
      if (_isAuthInvalidation(failure)) {
        _clearForAuth(failure);
        return;
      }
      state = state.copyWith(
        busy: false,
        error: preserveError ?? failure,
        requiresReadRetry: true,
        pendingCommand: null,
        acknowledged: false,
        confirmed: false,
      );
      _retainPendingOperation();
    }
  }

  void _scheduleSession(AsyncValue<OperationalSession> next) {
    final version = ++_sessionEventVersion;
    scheduleMicrotask(() {
      if (!_isMounted || version != _sessionEventVersion) return;
      _handleSession(next);
    });
  }

  void _handleSession(AsyncValue<OperationalSession> next) {
    if (!_isMounted) return;
    if (next.isLoading) {
      _replaceSession(
        null,
        const OutboundCommandFailure(OutboundCommandFailureCode.sessionExpired),
      );
      return;
    }
    if (next.hasError) {
      _replaceSession(null, _mapFailure(next.error!));
      return;
    }
    final incoming = next.requireValue;
    if (identical(incoming, _activeSession)) return;
    final old = _activeSession;
    final sameActor =
        _isSessionUsable(old) &&
        _isSessionUsable(incoming) &&
        old!.userId == incoming.userId;
    final frozenCommand = state.pendingCommand;
    final acknowledged = _acknowledgedCommand;
    _activeSession = incoming;
    _sessionRevision++;
    _operationGeneration++;
    _currentDetails = null;
    _detailEventVersion++;
    _resetHandoverMarker();
    _invalidateDetailProjection();

    if (sameActor && frozenCommand != null) {
      state = state.copyWith(
        details: const AsyncLoading(),
        busy: false,
        pendingCommand: frozenCommand,
        requiresReadRetry: false,
        actionsDenied: false,
        acknowledged: false,
        confirmed: false,
        confirmedOperation: null,
      );
      _retainPendingOperation();
      return;
    }
    if (sameActor && acknowledged != null) {
      _acknowledgedCommand = acknowledged;
      state = state.copyWith(
        details: const AsyncLoading(),
        busy: false,
        pendingCommand: null,
        requiresReadRetry: true,
        actionsDenied: false,
        acknowledged: true,
        confirmed: false,
        confirmedOperation: null,
      );
      _retainPendingOperation();
      return;
    }

    _acknowledgedCommand = null;
    final failure = incoming.failure == null && _isSessionUsable(incoming)
        ? null
        : incoming.failure ??
              const OutboundCommandFailure(
                OutboundCommandFailureCode.sessionExpired,
              );
    if (failure != null) {
      _setAuthState(_mapFailure(failure));
    } else {
      state = state.copyWith(
        details: const AsyncLoading(),
        busy: false,
        error: null,
        pendingCommand: null,
        requiresReadRetry: false,
        actionsDenied: false,
        acknowledged: false,
        confirmed: false,
        confirmedOperation: null,
      );
      _adoptCurrentProjectionIfReady();
      _releasePendingOperationIfIdle();
    }
  }

  void _adoptCurrentProjectionIfReady() {
    if (!_isMounted || !_isSessionUsable(_activeSession)) return;
    final projected = ref.read(deliveryTaskDetailViewModelProvider(taskId));
    if (!projected.hasValue) return;
    final details = projected.requireValue;
    if (!_sameUuid(details.task.taskId, taskId)) return;
    _currentDetails = details;
    state = state.copyWith(details: AsyncData(details));
    scheduleMicrotask(() {
      if (_isMounted && !_disposed) {
        final next = ref.read(deliveryTaskDetailViewModelProvider(taskId));
        if (next.hasValue) _scheduleDetails(next);
      }
    });
  }

  void _replaceSession(OperationalSession? session, Object failure) {
    if (!_isMounted) return;
    _activeSession = session;
    _sessionRevision++;
    _operationGeneration++;
    _currentDetails = null;
    _acknowledgedCommand = null;
    _detailEventVersion++;
    _resetHandoverMarker();
    _invalidateDetailProjection();
    _setAuthState(_mapFailure(failure));
  }

  void _resetHandoverMarker() {
    _handoverReadVersion++;
    _handoverReadInFlight = false;
    _handoverReadTaskId = null;
    if (_isMounted) {
      state = state.copyWith(handoverStatus: const AsyncLoading());
    }
  }

  void _scheduleDetails(AsyncValue<DeliveryTaskDetails> next) {
    final version = ++_detailEventVersion;
    final generation = _operationGeneration;
    scheduleMicrotask(() {
      if (!_isMounted ||
          version != _detailEventVersion ||
          generation != _operationGeneration) {
        return;
      }
      if (state.actionsDenied) {
        _currentDetails = null;
        return;
      }
      if (next.hasValue) {
        final details = next.requireValue;
        _currentDetails = _sameUuid(details.task.taskId, taskId)
            ? details
            : null;
        if (_currentDetails != null &&
            state.pendingCommand == null &&
            _acknowledgedCommand == null) {
          state = state.copyWith(details: AsyncData(details));
          _maybeReadHandoverStatus(details);
        }
      } else if (next.hasError &&
          state.pendingCommand == null &&
          _acknowledgedCommand == null) {
        final failure = _mapFailure(next.error!);
        if (_isAuthInvalidation(failure)) {
          _clearForAuth(failure);
          return;
        }
        state = state.copyWith(
          details: AsyncError(failure, next.stackTrace ?? StackTrace.empty),
          busy: false,
          error: failure,
          requiresReadRetry: true,
          confirmed: false,
        );
      }
    });
  }

  void _listenToDetails() {
    if (!_isMounted || _detailSubscription != null) return;
    _detailSubscription = ref.container.listen<AsyncValue<DeliveryTaskDetails>>(
      deliveryTaskDetailViewModelProvider(taskId),
      (_, next) => _scheduleDetails(next),
      fireImmediately: true,
    );
  }

  void _maybeReadHandoverStatus(DeliveryTaskDetails details) {
    if (!_isMounted || !_visible || !_isSessionUsable(_activeSession)) return;
    if (!canReportHandoverDetails(details) || _handoverReadInFlight) return;
    if (_handoverReadTaskId == taskId &&
        (state.handoverStatus.hasValue || state.handoverStatus.hasError)) {
      return;
    }
    unawaited(
      _readHandoverStatus(
        _activeSession!,
        _sessionRevision,
        _operationGeneration,
        force: false,
        mustConfirm: false,
      ),
    );
  }

  void _resumeVisibleWork() {
    if (!_isMounted || !_visible) return;
    if (_detailInvalidationDeferred) {
      _detailInvalidationDeferred = false;
      ref.invalidate(deliveryTaskDetailViewModelProvider(taskId));
    }
    final session = _activeSession;
    if (!_isSessionUsable(session) || state.actionsDenied || state.busy) return;
    final revision = _sessionRevision;
    final generation = _operationGeneration;
    if (_ackReadDeferred && _acknowledgedCommand != null) {
      _ackReadDeferred = false;
      unawaited(
        _reconcileAcknowledged(
          _acknowledgedCommand!,
          session!,
          revision,
          generation,
        ),
      );
      return;
    }
    if (_rejectedReadDeferred) {
      _rejectedReadDeferred = false;
      unawaited(
        _reloadAfterDefinitiveFailure(
          session!,
          revision,
          generation,
          preserveError: state.error,
        ),
      );
    }
  }

  bool _readyForSubmit(int? revision) {
    final session = _activeSession;
    return _isMounted &&
        _visible &&
        _isSessionUsable(session) &&
        !state.actionsDenied &&
        !state.busy &&
        state.pendingCommand == null &&
        !state.requiresReadRetry &&
        !state.acknowledged &&
        !state.confirmed &&
        (revision == null || revision == _sessionRevision);
  }

  bool _readyForHandover(int? revision) {
    final session = _activeSession;
    if (!_isMounted ||
        !_visible ||
        !_isSessionUsable(session) ||
        state.actionsDenied ||
        state.busy ||
        state.pendingCommand != null ||
        state.requiresReadRetry ||
        (state.acknowledged &&
            !(state.confirmed &&
                state.confirmedOperation == ReturnPickupOperation.collect)) ||
        !state.handoverStatus.hasValue ||
        (state.confirmed &&
            state.confirmedOperation != ReturnPickupOperation.collect) ||
        (revision != null && revision != _sessionRevision)) {
      return false;
    }
    final details = _readCurrentDetails();
    return details != null &&
        !state.handoverReported &&
        canReportHandoverDetails(details);
  }

  DeliveryTaskDetails? _readCurrentDetails() {
    if (!_isMounted) return null;
    final current = state.details;
    if (!current.hasValue) return _currentDetails;
    final details = current.requireValue;
    if (!_sameUuid(details.task.taskId, taskId)) return null;
    _currentDetails = details;
    return details;
  }

  /// Read the server-owned handover marker without broadening the details
  /// projection. [mustConfirm] is used after a handover ACK: the ACK is not
  /// considered reconciled until this marker is true. A P08.1-only fixture
  /// may expose no marker capability while reconciling an older collect ACK;
  /// that case remains unavailable for future handover and is not treated as
  /// a reported marker.
  Future<bool> _readHandoverStatus(
    OperationalSession session,
    int revision,
    int generation, {
    required bool force,
    required bool mustConfirm,
  }) async {
    if (!_isCurrent(session, revision, generation) || !_visible) return false;
    final details = _readCurrentDetails();
    if (details == null || !canReportHandoverDetails(details)) {
      return !mustConfirm;
    }
    if (_handoverReadInFlight) return false;
    if (!force &&
        _handoverReadTaskId == taskId &&
        state.handoverStatus.hasValue) {
      return !mustConfirm || state.handoverReported;
    }

    final version = ++_handoverReadVersion;
    _handoverReadInFlight = true;
    _handoverReadTaskId = taskId;
    state = state.copyWith(handoverStatus: const AsyncLoading());
    _retainPendingOperation();
    try {
      final status = await ref.read(returnPickupHandoverStatusProvider)(taskId);
      if (!_isCurrent(session, revision, generation) ||
          version != _handoverReadVersion) {
        return false;
      }
      if (!status.isValid || !status.matchesTask(taskId)) {
        throw const FormatException('invalid return-pickup handover marker');
      }
      if (mustConfirm && !status.reported) {
        throw const OutboundCommandFailure(
          OutboundCommandFailureCode.staleState,
        );
      }
      state = state.copyWith(handoverStatus: AsyncData(status));
      return true;
    } on Object catch (error) {
      if (!_isCurrent(session, revision, generation) ||
          version != _handoverReadVersion) {
        return false;
      }
      if (error is UnsupportedError && !mustConfirm) {
        // Existing P08.1 fixtures have no handover marker. Keep the UI
        // blocked and let the already committed collect receipt reconcile.
        state = state.copyWith(
          handoverStatus: AsyncError(error, StackTrace.current),
        );
        return true;
      }
      final failure = _mapFailure(error);
      if (_isAuthInvalidation(failure)) {
        _clearForAuth(failure);
        return false;
      }
      state = state.copyWith(
        handoverStatus: AsyncError(failure, StackTrace.current),
        // A marker read is independent from the write. Always release the
        // busy flag so the dedicated marker retry can run without dispatching
        // a second handover command.
        busy: false,
        error: mustConfirm ? failure : state.error,
        requiresReadRetry: mustConfirm || state.acknowledged
            ? true
            : state.requiresReadRetry,
        acknowledged: mustConfirm ? true : state.acknowledged,
        confirmed: mustConfirm ? false : state.confirmed,
      );
      if (mustConfirm) _retainPendingOperation();
      return false;
    } finally {
      if (version == _handoverReadVersion) {
        _handoverReadInFlight = false;
      }
      if (!_hasPendingWork) _releasePendingOperationIfIdle();
    }
  }

  void _validateAcknowledgedDetails(
    ReturnPickupCommand command,
    DeliveryTaskDetails details,
  ) {
    final task = details.task;
    if (!_sameUuid(task.taskId, command.taskId) ||
        task.kind != DeliveryTaskKind.returnPickup) {
      throw const OutboundCommandFailure(
        OutboundCommandFailureCode.invalidData,
      );
    }
    if (command.isCollect || command.isHandover) {
      if (task.scope != DeliverySnapshotScope.current ||
          task.status != DeliveryTaskStatus.inTransit ||
          task.orderId == null ||
          !_sameUuid(task.orderId!, command.orderId) ||
          task.returnRequestId == null ||
          !_sameUuid(task.returnRequestId!, command.returnRequestId) ||
          task.amountToCollectVnd != 0 ||
          task.acceptedAt == null ||
          task.startedAt == null ||
          task.acceptedAt != task.startedAt ||
          task.completedAt != null) {
        throw const OutboundCommandFailure(
          OutboundCommandFailureCode.staleState,
        );
      }
      final returned = <String, DeliveryTaskItem>{
        for (final item in details.items) item.itemId.toLowerCase(): item,
      };
      if (details.items.length != command.items.length ||
          returned.length != command.items.length ||
          command.items.any((item) {
            final actual = returned[item.returnItemId.toLowerCase()];
            return actual == null ||
                actual.itemSource != DeliveryItemSource.returnPlan ||
                actual.quantity != item.quantity ||
                actual.quantityCollected != item.quantity;
          })) {
        throw const OutboundCommandFailure(
          OutboundCommandFailureCode.staleState,
        );
      }
      return;
    }
    if ((task.scope != DeliverySnapshotScope.current &&
            task.scope != DeliverySnapshotScope.restricted) ||
        task.status != DeliveryTaskStatus.failed ||
        task.acceptedAt != null ||
        task.startedAt != null ||
        task.completedAt == null) {
      throw const OutboundCommandFailure(OutboundCommandFailureCode.staleState);
    }
  }

  /// Fail closed for a legacy/partial projection.  In particular, a null
  /// collected quantity is not treated as zero and an already-collected task
  /// cannot expose a second collection/failure action.
  static bool canMutateDetails(DeliveryTaskDetails details) {
    final task = details.task;
    if (task.kind != DeliveryTaskKind.returnPickup ||
        task.scope != DeliverySnapshotScope.current ||
        task.status != DeliveryTaskStatus.assigned ||
        task.amountToCollectVnd != 0 ||
        task.orderId == null ||
        task.returnRequestId == null ||
        !_isUuid(task.taskId) ||
        !_isUuid(task.orderId!) ||
        !_isUuid(task.returnRequestId!) ||
        task.assignedAt == null ||
        task.acceptedAt != null ||
        task.startedAt != null ||
        task.completedAt != null ||
        task.itemSource != DeliveryItemSource.returnPlan ||
        details.items.isEmpty) {
      return false;
    }
    String? previous;
    final seen = <String>{};
    for (final item in details.items) {
      final current = item.itemId.toLowerCase();
      if (!_isUuid(item.itemId) ||
          item.itemSource != DeliveryItemSource.returnPlan ||
          item.quantity < 1 ||
          item.quantity > _maxInt32 ||
          item.quantityCollected != 0 ||
          !seen.add(current) ||
          (previous != null && current.compareTo(previous) < 0)) {
        return false;
      }
      previous = current;
    }
    return true;
  }

  /// Fail-closed eligibility for reporting store handover. The item list must
  /// remain the approved return-plan snapshot and every quantity must already
  /// be recorded as collected by the server read projection.
  static bool canReportHandoverDetails(DeliveryTaskDetails details) {
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
        task.completedAt != null ||
        task.itemSource != DeliveryItemSource.returnPlan ||
        details.items.isEmpty) {
      return false;
    }
    String? previous;
    final seen = <String>{};
    for (final item in details.items) {
      final current = item.itemId.toLowerCase();
      if (!_isUuid(item.itemId) ||
          item.itemSource != DeliveryItemSource.returnPlan ||
          item.quantity < 1 ||
          item.quantity > _maxInt32 ||
          item.quantityCollected != item.quantity ||
          !seen.add(current) ||
          (previous != null && current.compareTo(previous) < 0)) {
        return false;
      }
      previous = current;
    }
    return true;
  }

  static List<ReturnPickupItem> _canonicalItems(
    Iterable<DeliveryTaskItem> items,
  ) => items
      .map(
        (item) => ReturnPickupItem(
          returnItemId: item.itemId,
          quantity: item.quantity,
        ),
      )
      .toList(growable: false);

  static bool _sameItems(
    List<DeliveryTaskItem> expected,
    List<DeliveryTaskItem> actual,
  ) {
    if (expected.length != actual.length) return false;
    for (var index = 0; index < actual.length; index++) {
      final left = expected[index];
      final right = actual[index];
      if (left.itemId.toLowerCase() != right.itemId.toLowerCase() ||
          left.quantity != right.quantity ||
          left.quantityCollected != right.quantityCollected ||
          left.productName != right.productName) {
        return false;
      }
    }
    return true;
  }

  bool get _hasPendingWork =>
      state.pendingCommand != null ||
      state.busy ||
      _handoverReadInFlight ||
      state.requiresReadRetry ||
      (state.acknowledged && !state.confirmed) ||
      _ackReadDeferred ||
      _rejectedReadDeferred;

  void _retainPendingOperation() {
    _closePendingKeepAlive ??= ref.keepAlive().close;
  }

  void _releasePendingOperationIfIdle() {
    if (_hasPendingWork) return;
    ref.read(outboundResultGateProvider(taskId).notifier).release(this);
    _closePendingKeepAlive?.call();
    _closePendingKeepAlive = null;
  }

  void _clearForAuth(OutboundCommandFailure failure) {
    if (!_isMounted) return;
    _sessionRevision++;
    _operationGeneration++;
    _currentDetails = null;
    _acknowledgedCommand = null;
    _detailEventVersion++;
    _resetHandoverMarker();
    _invalidateDetailProjection();
    _setAuthState(failure);
  }

  void _setAuthState(OutboundCommandFailure failure) {
    state = state.copyWith(
      details: AsyncError(failure, StackTrace.empty),
      handoverStatus: const AsyncLoading(),
      busy: false,
      error: failure,
      pendingCommand: null,
      requiresReadRetry: false,
      actionsDenied: true,
      acknowledged: false,
      confirmed: false,
      confirmedOperation: null,
    );
    _releasePendingOperationIfIdle();
  }

  void _setValidationError(OutboundCommandFailureCode code) {
    if (!_isMounted) return;
    state = state.copyWith(
      busy: false,
      error: OutboundCommandFailure(code),
      pendingCommand: null,
      requiresReadRetry: false,
      acknowledged: false,
      confirmed: false,
      confirmedOperation: null,
    );
  }

  void _invalidateDetailProjection() {
    if (!_isMounted) return;
    if (!_visible) {
      _detailInvalidationDeferred = true;
      return;
    }
    ref.invalidate(deliveryTaskDetailViewModelProvider(taskId));
  }

  bool get _isMounted => !_disposed && ref.mounted;

  bool _isCurrent(OperationalSession session, int revision, int generation) =>
      _isMounted &&
      identical(session, _activeSession) &&
      revision == _sessionRevision &&
      generation == _operationGeneration &&
      _isSessionUsable(session);

  static bool _isSessionUsable(OperationalSession? session) =>
      session != null && session.userId != null && session.failure == null;

  static bool _sameUuid(String left, String right) =>
      left.trim().toLowerCase() == right.trim().toLowerCase();

  static bool _isUuid(String value) => _uuid.hasMatch(value);

  static bool _isAuthInvalidation(OutboundCommandFailure failure) =>
      failure.code == OutboundCommandFailureCode.sessionExpired ||
      failure.code == OutboundCommandFailureCode.permissionDenied ||
      failure.code == OutboundCommandFailureCode.staleAssignment;

  static bool _isUncertainWrite(OutboundCommandFailure failure) =>
      failure is OutboundAcknowledgementFailure ||
      failure.code == OutboundCommandFailureCode.timeout ||
      failure.code == OutboundCommandFailureCode.network ||
      failure.code == OutboundCommandFailureCode.dependencyUnavailable ||
      failure.code == OutboundCommandFailureCode.unexpected;

  static OutboundCommandFailure _mapFailure(Object error) {
    if (error is OutboundCommandFailure) return error;
    if (error is OperationalFailure) {
      return OutboundCommandFailure(switch (error.code) {
        OperationalFailureCode.sessionExpired =>
          OutboundCommandFailureCode.sessionExpired,
        OperationalFailureCode.permissionDenied =>
          OutboundCommandFailureCode.permissionDenied,
        OperationalFailureCode.staleAssignment =>
          OutboundCommandFailureCode.staleAssignment,
        OperationalFailureCode.invalidData =>
          OutboundCommandFailureCode.invalidData,
        OperationalFailureCode.network => OutboundCommandFailureCode.network,
        OperationalFailureCode.backendUnavailable =>
          OutboundCommandFailureCode.dependencyUnavailable,
        OperationalFailureCode.unexpected =>
          OutboundCommandFailureCode.unexpected,
      });
    }
    if (error is TimeoutException) {
      return const OutboundCommandFailure(OutboundCommandFailureCode.timeout);
    }
    if (error is FormatException ||
        error is ArgumentError ||
        error is TypeError) {
      return const OutboundCommandFailure(
        OutboundCommandFailureCode.invalidData,
      );
    }
    return const OutboundCommandFailure(OutboundCommandFailureCode.unexpected);
  }
}

const int _maxInt32 = 2147483647;
final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
