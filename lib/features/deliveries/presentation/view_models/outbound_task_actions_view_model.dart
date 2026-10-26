import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/operational_providers.dart';
import '../../data/repositories/operational_read_access.dart';
import '../../domain/models/delivery_task.dart';
import '../../domain/models/delivery_task_details.dart';
import '../../domain/models/operational_failure.dart';
import '../../domain/models/outbound_task_command.dart';
import 'delivery_task_detail_view_model.dart';
import 'outbound_action_providers.dart';

/// The action state for the outbound part of MH11.
///
/// The detail page owns the task projection. This state only owns the write
/// protocol: a command is either still pending, has been acknowledged and is
/// being reconciled, or has completed its read/list reconciliation. Keeping
/// that distinction here prevents a command ACK from being mistaken for a
/// task status update.
final class OutboundTaskActionsState {
  const OutboundTaskActionsState({
    this.busy = false,
    this.error,
    this.pendingCommand,
    this.requiresReadRetry = false,
    this.actionsDenied = false,
    this.acknowledged = false,
    this.confirmedAction,
  });

  const OutboundTaskActionsState.initial() : this();

  final bool busy;
  final OutboundCommandFailure? error;
  final OutboundTaskCommand? pendingCommand;
  final bool requiresReadRetry;
  final bool actionsDenied;

  /// True after the server has acknowledged the exact command key. It remains
  /// true while detail/list reads need retrying and after a fully reconciled
  /// action so the UI can distinguish a committed write from a validation
  /// failure.
  final bool acknowledged;

  /// The action whose ACK was reconciled by an authoritative detail read.
  final OutboundTaskAction? confirmedAction;

  bool get isSubmitting => busy;

  bool get confirmed => acknowledged && confirmedAction != null;

  bool get awaitingAuthoritativeRead =>
      acknowledged && (busy || requiresReadRetry);

  bool get actionBlocked =>
      busy || pendingCommand != null || requiresReadRetry || actionsDenied;

  static const _unset = Object();

  OutboundTaskActionsState copyWith({
    bool? busy,
    Object? error = _unset,
    Object? pendingCommand = _unset,
    bool? requiresReadRetry,
    bool? actionsDenied,
    bool? acknowledged,
    Object? confirmedAction = _unset,
  }) {
    return OutboundTaskActionsState(
      busy: busy ?? this.busy,
      error: identical(error, _unset)
          ? this.error
          : error as OutboundCommandFailure?,
      pendingCommand: identical(pendingCommand, _unset)
          ? this.pendingCommand
          : pendingCommand as OutboundTaskCommand?,
      requiresReadRetry: requiresReadRetry ?? this.requiresReadRetry,
      actionsDenied: actionsDenied ?? this.actionsDenied,
      acknowledged: acknowledged ?? this.acknowledged,
      confirmedAction: identical(confirmedAction, _unset)
          ? this.confirmedAction
          : confirmedAction as OutboundTaskAction?,
    );
  }
}

/// Production P04.2 action controller for one MH11 task.
final outboundTaskActionsViewModelProvider = NotifierProvider.autoDispose
    .family<OutboundTaskActionsViewModel, OutboundTaskActionsState, String>(
      OutboundTaskActionsViewModel.new,
    );

class OutboundTaskActionsViewModel extends Notifier<OutboundTaskActionsState> {
  OutboundTaskActionsViewModel(this.taskId);

  final String taskId;

  OperationalSession? _activeSession;
  ProviderSubscription<AsyncValue<OperationalSession>>? _sessionSubscription;
  ProviderSubscription<AsyncValue<DeliveryTaskDetails>>? _detailSubscription;
  void Function()? _closePendingKeepAlive;

  DeliveryTaskDetails? _currentDetails;
  OutboundTaskCommand? _acknowledgedCommand;
  int? _acknowledgedAttempt;

  var _disposed = false;
  var _visible = true;
  var _sessionRevision = 0;
  var _sessionEventVersion = 0;
  var _detailEventVersion = 0;
  var _operationGeneration = 0;
  var _ackReadDeferred = false;
  var _rejectedReadDeferred = false;
  var _detailInvalidationDeferred = false;

  int get sessionRevisionForConfirmation => _sessionRevision;

  @override
  OutboundTaskActionsState build() {
    _disposed = false;
    _visible = true;
    _activeSession = null;
    _currentDetails = null;
    _acknowledgedCommand = null;
    _acknowledgedAttempt = null;
    _sessionRevision++;
    _sessionEventVersion++;
    _detailEventVersion++;
    _operationGeneration++;
    _ackReadDeferred = false;
    _rejectedReadDeferred = false;
    _detailInvalidationDeferred = false;

    // These are container listeners on purpose. Watching either provider
    // would rebuild this Notifier during a detail reload/auth epoch and could
    // discard a frozen request ID while its write is still in flight.
    _sessionSubscription = ref.container.listen<AsyncValue<OperationalSession>>(
      operationalSessionProvider,
      (_, next) => _scheduleSession(next),
      fireImmediately: true,
    );
    _listenToDetails();

    // Riverpod lifecycle callbacks must not read Ref or mutate Notifier state
    // synchronously. A microtask also lets the provider settle before the
    // visibility transition is handled.
    ref.onCancel(() {
      scheduleMicrotask(() {
        if (_disposed) return;
        _visible = false;
        _detailEventVersion++;
        _detailSubscription?.close();
        _detailSubscription = null;
        _currentDetails = null;
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
      _acknowledgedAttempt = null;
      _detailInvalidationDeferred = false;
    });

    return const OutboundTaskActionsState();
  }

  /// Presentation eligibility only. The server still validates custody,
  /// stock and the current assignment in the RPC.
  bool canExecute(OutboundTaskAction action, DeliveryTaskSnapshot task) {
    if (!_isSessionUsable(_activeSession) ||
        state.actionsDenied ||
        state.busy ||
        state.pendingCommand != null ||
        state.requiresReadRetry ||
        (state.acknowledged && state.confirmedAction == action) ||
        !_visible) {
      return false;
    }
    return _isEligibleAction(task, action);
  }

  /// Submits a confirmation bound to the complete detail snapshot and the
  /// auth/session revision captured when the confirmation UI opened.
  ///
  /// The command key is generated only after those guards are rechecked. A
  /// command that crossed the repository boundary is never replaced with a
  /// new key by retry or by a detail/list reload.
  Future<void> submit(
    OutboundTaskAction action, {
    required DeliveryTaskSnapshot expectedTask,
    required int sessionRevision,
  }) async {
    if (!_isMounted ||
        !_visible ||
        state.busy ||
        state.pendingCommand != null) {
      return;
    }

    final session = _activeSession;
    if (session == null || !_isSessionUsable(session) || state.actionsDenied) {
      return;
    }
    if (sessionRevision != _sessionRevision) {
      _setValidationError(OutboundCommandFailureCode.staleState);
      return;
    }
    if (state.requiresReadRetry) {
      _setValidationError(OutboundCommandFailureCode.staleState);
      return;
    }

    final details = _readCurrentDetails();
    if (details == null ||
        !_sameTaskSnapshot(details.task, expectedTask) ||
        !_sameUuid(details.task.taskId, taskId) ||
        (state.acknowledged && state.confirmedAction == action) ||
        !_isEligibleAction(details.task, action)) {
      _setValidationError(OutboundCommandFailureCode.staleState);
      return;
    }

    final revision = _sessionRevision;
    final operation = _operationGeneration;
    late final OutboundTaskCommand command;
    try {
      final requestId = ref.read(outboundTaskRequestIdProvider)();
      command = OutboundTaskCommand(
        taskId: taskId,
        requestId: requestId,
        action: action,
      );
      if (!command.hasNonEmptyIds || !command.isUuidShaped) {
        throw const FormatException('Invalid outbound command key');
      }
    } on Object {
      _setValidationError(OutboundCommandFailureCode.invalidData);
      return;
    }

    _acknowledgedCommand = null;
    _acknowledgedAttempt = details.task.attemptNumber;
    _ackReadDeferred = false;
    _rejectedReadDeferred = false;
    state = state.copyWith(
      busy: true,
      error: null,
      pendingCommand: command,
      requiresReadRetry: false,
      acknowledged: false,
      confirmedAction: null,
    );
    _retainPendingOperation();
    await _executeWrite(command, session, revision, operation);
  }

  /// Retries a frozen write with the exact same command/key, or retries only
  /// the authoritative detail/list reconciliation after an ACK.
  Future<void> retry() async {
    if (!_isMounted || !_visible || state.busy) return;
    final session = _activeSession;
    if (session == null || !_isSessionUsable(session) || state.actionsDenied) {
      return;
    }
    final revision = _sessionRevision;
    final operation = _operationGeneration;

    final pending = state.pendingCommand;
    if (pending != null) {
      await _executeWrite(pending, session, revision, operation);
      return;
    }

    final acknowledged = _acknowledgedCommand;
    if (state.acknowledged && acknowledged != null) {
      await _reconcileAcknowledged(acknowledged, session, revision, operation);
      return;
    }

    if (_rejectedReadDeferred || state.requiresReadRetry) {
      await _reloadAfterDefinitiveFailure(
        session,
        revision,
        operation,
        preserveError: state.error,
      );
    }
  }

  Future<void> _executeWrite(
    OutboundTaskCommand command,
    OperationalSession session,
    int revision,
    int operation,
  ) async {
    if (!_isCurrent(session, revision, operation) || !_visible) return;

    state = state.copyWith(
      busy: true,
      error: null,
      pendingCommand: command,
      requiresReadRetry: false,
      acknowledged: false,
      confirmedAction: null,
    );
    _retainPendingOperation();

    try {
      await ref.read(outboundTaskCommandRepositoryProvider).execute(command);
    } on Object catch (error) {
      if (!_isCurrent(session, revision, operation)) return;
      final failure = _mapFailure(error);
      if (_isAuthInvalidation(failure)) {
        _clearForAuth(failure);
        return;
      }

      if (_isUncertainWrite(failure)) {
        // The server may already have committed. Keep the exact envelope and
        // do not issue a read or generate another request ID automatically.
        state = state.copyWith(
          busy: false,
          error: failure,
          pendingCommand: command,
          requiresReadRetry: false,
          acknowledged: false,
        );
        _retainPendingOperation();
        return;
      }

      // Closed server business failures (including staleState) are surfaced
      // as typed safe errors, then reconciled against a fresh detail read.
      state = state.copyWith(
        busy: false,
        error: failure,
        pendingCommand: null,
        requiresReadRetry: true,
        acknowledged: false,
        confirmedAction: null,
      );
      _acknowledgedCommand = null;
      _acknowledgedAttempt = null;
      _retainPendingOperation();
      if (_visible) {
        await _reloadAfterDefinitiveFailure(
          session,
          revision,
          operation,
          preserveError: failure,
        );
      } else {
        _rejectedReadDeferred = true;
      }
      return;
    }

    if (!_isCurrent(session, revision, operation)) return;

    // An ACK is only a write acknowledgement. The detail and list reads are
    // the source of truth for visible state and are deliberately serialized.
    _acknowledgedCommand = command;
    state = state.copyWith(
      busy: true,
      error: null,
      pendingCommand: null,
      requiresReadRetry: false,
      acknowledged: true,
      confirmedAction: null,
    );
    _retainPendingOperation();
    await _reconcileAcknowledged(command, session, revision, operation);
  }

  Future<void> _reconcileAcknowledged(
    OutboundTaskCommand command,
    OperationalSession session,
    int revision,
    int operation,
  ) async {
    if (!_isCurrent(session, revision, operation)) return;
    if (!_visible) {
      _ackReadDeferred = true;
      state = state.copyWith(
        busy: false,
        error: null,
        requiresReadRetry: true,
        acknowledged: true,
      );
      _retainPendingOperation();
      return;
    }

    _ackReadDeferred = false;
    _rejectedReadDeferred = false;
    state = state.copyWith(busy: true, error: null);
    final detailsReload = ref.read(outboundTaskDetailsReloadProvider);
    DeliveryTaskDetails details;
    try {
      details = await detailsReload(taskId);
      if (!_isCurrent(session, revision, operation)) return;
      _validateAcknowledgedDetails(command, details);
      _currentDetails = details;
    } on Object catch (error) {
      if (!_isCurrent(session, revision, operation)) return;
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
        confirmedAction: null,
      );
      _retainPendingOperation();
      return;
    }

    if (!_isCurrent(session, revision, operation)) return;
    if (!_visible) {
      _ackReadDeferred = true;
      state = state.copyWith(
        busy: false,
        requiresReadRetry: true,
        acknowledged: true,
        confirmedAction: null,
      );
      _retainPendingOperation();
      return;
    }
    try {
      await ref.read(outboundTaskListReloadProvider)();
    } on Object catch (error) {
      if (!_isCurrent(session, revision, operation)) return;
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
        confirmedAction: null,
      );
      _retainPendingOperation();
      return;
    }

    if (!_isCurrent(session, revision, operation)) return;
    state = state.copyWith(
      busy: false,
      error: null,
      pendingCommand: null,
      requiresReadRetry: false,
      acknowledged: true,
      confirmedAction: command.action,
    );
    _releasePendingOperationIfIdle();
  }

  Future<void> _reloadAfterDefinitiveFailure(
    OperationalSession session,
    int revision,
    int operation, {
    OutboundCommandFailure? preserveError,
  }) async {
    if (!_isCurrent(session, revision, operation)) return;
    if (!_visible) {
      _rejectedReadDeferred = true;
      state = state.copyWith(busy: false, requiresReadRetry: true);
      _retainPendingOperation();
      return;
    }

    _rejectedReadDeferred = false;
    state = state.copyWith(busy: true);
    try {
      final details = await ref.read(outboundTaskDetailsReloadProvider)(taskId);
      if (!_isCurrent(session, revision, operation)) return;
      if (!_sameUuid(details.task.taskId, taskId)) {
        throw const OutboundCommandFailure(
          OutboundCommandFailureCode.invalidData,
        );
      }
      _currentDetails = details;
      if (_visible) {
        await ref.read(outboundTaskListReloadProvider)();
        if (!_isCurrent(session, revision, operation)) return;
      } else {
        _rejectedReadDeferred = true;
        state = state.copyWith(busy: false, requiresReadRetry: true);
        return;
      }
      state = state.copyWith(
        busy: false,
        error: preserveError,
        requiresReadRetry: false,
        pendingCommand: null,
        acknowledged: false,
        confirmedAction: null,
      );
      _releasePendingOperationIfIdle();
    } on Object catch (error) {
      if (!_isCurrent(session, revision, operation)) return;
      final failure = _mapFailure(error);
      if (_isAuthInvalidation(failure)) {
        _clearForAuth(failure);
        return;
      }
      state = state.copyWith(
        busy: false,
        // Keep the original safe business error visible when its follow-up
        // read fails; retry still performs a read and never a write.
        error: preserveError ?? failure,
        requiresReadRetry: true,
        pendingCommand: null,
        acknowledged: false,
        confirmedAction: null,
      );
      _retainPendingOperation();
    }
  }

  DeliveryTaskDetails? _readCurrentDetails() {
    if (!_isMounted) return null;
    try {
      final current = ref.read(deliveryTaskDetailViewModelProvider(taskId));
      if (!current.hasValue) {
        _currentDetails = null;
        return null;
      }
      final details = current.requireValue;
      if (!identical(_currentDetails, details)) {
        _currentDetails = details;
      }
      if (!_sameUuid(details.task.taskId, taskId)) return null;
      return details;
    } on Object {
      return null;
    }
  }

  void _validateAcknowledgedDetails(
    OutboundTaskCommand command,
    DeliveryTaskDetails details,
  ) {
    final task = details.task;
    if (!_sameUuid(task.taskId, command.taskId) ||
        _acknowledgedAttempt == null ||
        task.attemptNumber != _acknowledgedAttempt) {
      throw const OutboundCommandFailure(
        OutboundCommandFailureCode.invalidData,
      );
    }
    if (task.kind != DeliveryTaskKind.outbound ||
        task.scope != DeliverySnapshotScope.current) {
      throw const OutboundCommandFailure(OutboundCommandFailureCode.staleState);
    }

    switch (command.action) {
      case OutboundTaskAction.acceptGoods:
        // Accept may race with the next server transition. Seeing inTransit
        // is therefore valid, but the server must have recorded acceptance.
        if ((task.status != DeliveryTaskStatus.accepted &&
                task.status != DeliveryTaskStatus.inTransit) ||
            task.acceptedAt == null) {
          throw const OutboundCommandFailure(
            OutboundCommandFailureCode.staleState,
          );
        }
      case OutboundTaskAction.startDelivery:
        if (task.status != DeliveryTaskStatus.inTransit ||
            task.acceptedAt == null ||
            task.startedAt == null) {
          throw const OutboundCommandFailure(
            OutboundCommandFailureCode.staleState,
          );
        }
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
        bumpRevision: true,
      );
      return;
    }
    if (next.hasError) {
      _replaceSession(null, _mapFailure(next.error!), bumpRevision: true);
      return;
    }
    final session = next.requireValue;
    if (identical(session, _activeSession)) return;
    final previousSession = _activeSession;
    final sameActor =
        _isSessionUsable(previousSession) &&
        _isSessionUsable(session) &&
        previousSession!.userId == session.userId;
    final frozenCommand = state.pendingCommand;
    final acknowledgedCommand = _acknowledgedCommand;
    final acknowledgedAttempt = _acknowledgedAttempt;
    _activeSession = session;
    _sessionRevision++;
    _operationGeneration++;
    _currentDetails = null;
    _acknowledgedAttempt = null;
    _ackReadDeferred = false;
    _rejectedReadDeferred = false;
    _detailInvalidationDeferred = false;
    _invalidateDetailProjection();

    // A token refresh creates a new OperationalSession object. The old
    // access epoch can reject an in-flight response even when the server has
    // committed it, so retain the frozen command/key for the same actor. An
    // account switch or logout still clears it and redacts the detail.
    if (sameActor && frozenCommand != null) {
      _acknowledgedAttempt = acknowledgedAttempt;
      state = state.copyWith(
        busy: false,
        error:
            state.error ??
            const OutboundCommandFailure(
              OutboundCommandFailureCode.sessionExpired,
            ),
        pendingCommand: frozenCommand,
        requiresReadRetry: false,
        actionsDenied: false,
        acknowledged: false,
        confirmedAction: null,
      );
      _retainPendingOperation();
      return;
    }
    if (sameActor && acknowledgedCommand != null) {
      _acknowledgedCommand = acknowledgedCommand;
      _acknowledgedAttempt = acknowledgedAttempt;
      state = state.copyWith(
        busy: false,
        error: null,
        pendingCommand: null,
        requiresReadRetry: true,
        actionsDenied: false,
        acknowledged: true,
        confirmedAction: null,
      );
      _retainPendingOperation();
      return;
    }
    _acknowledgedCommand = null;

    final failure = session.failure == null
        ? (!_isSessionUsable(session)
              ? const OutboundCommandFailure(
                  OutboundCommandFailureCode.sessionExpired,
                )
              : null)
        : _mapFailure(session.failure!);
    if (failure != null) {
      _setAuthState(failure);
    } else {
      state = state.copyWith(
        busy: false,
        error: null,
        pendingCommand: null,
        requiresReadRetry: false,
        actionsDenied: false,
        acknowledged: false,
        confirmedAction: null,
      );
      _releasePendingOperationIfIdle();
    }
  }

  void _replaceSession(
    OperationalSession? session,
    OutboundCommandFailure failure, {
    required bool bumpRevision,
  }) {
    if (!_isMounted) return;
    _activeSession = session;
    if (bumpRevision) _sessionRevision++;
    _operationGeneration++;
    _currentDetails = null;
    _acknowledgedCommand = null;
    _acknowledgedAttempt = null;
    _ackReadDeferred = false;
    _rejectedReadDeferred = false;
    _detailInvalidationDeferred = false;
    _invalidateDetailProjection();
    _setAuthState(failure);
  }

  void _scheduleDetails(AsyncValue<DeliveryTaskDetails> next) {
    final version = ++_detailEventVersion;
    final operation = _operationGeneration;
    scheduleMicrotask(() {
      if (!_isMounted ||
          version != _detailEventVersion ||
          operation != _operationGeneration) {
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
      } else if (next.hasError) {
        _currentDetails = null;
        // The detail ViewModel remains the single read source. Surface its
        // typed failure here only when no write/reconciliation operation is
        // already responsible for mapping the same read failure.
        if (state.busy ||
            state.pendingCommand != null ||
            _acknowledgedCommand != null) {
          return;
        }
        final failure = _mapFailure(next.error!);
        if (_isAuthInvalidation(failure)) {
          _clearForAuth(failure);
          return;
        }
        state = state.copyWith(
          busy: false,
          error: failure,
          requiresReadRetry: true,
          acknowledged: false,
          confirmedAction: null,
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

  void _resumeVisibleWork() {
    if (!_isMounted || !_visible) return;
    if (_detailInvalidationDeferred) {
      _detailInvalidationDeferred = false;
      ref.invalidate(deliveryTaskDetailViewModelProvider(taskId));
    }
    final session = _activeSession;
    if (!_isSessionUsable(session) || state.actionsDenied || state.busy) return;
    final revision = _sessionRevision;
    final operation = _operationGeneration;
    if (_ackReadDeferred && _acknowledgedCommand != null) {
      _ackReadDeferred = false;
      unawaited(
        _reconcileAcknowledged(
          _acknowledgedCommand!,
          session!,
          revision,
          operation,
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
          operation,
          preserveError: state.error,
        ),
      );
    }
  }

  void _retainPendingOperation() {
    _closePendingKeepAlive ??= ref.keepAlive().close;
  }

  void _releasePendingOperationIfIdle() {
    if (state.pendingCommand != null ||
        state.busy ||
        state.requiresReadRetry ||
        _ackReadDeferred ||
        _rejectedReadDeferred) {
      return;
    }
    _closePendingKeepAlive?.call();
    _closePendingKeepAlive = null;
  }

  void _clearForAuth(OutboundCommandFailure failure) {
    if (!_isMounted) return;
    _sessionRevision++;
    _operationGeneration++;
    _currentDetails = null;
    _acknowledgedCommand = null;
    _acknowledgedAttempt = null;
    _ackReadDeferred = false;
    _rejectedReadDeferred = false;
    _detailInvalidationDeferred = false;
    _invalidateDetailProjection();
    _setAuthState(failure);
  }

  void _setAuthState(OutboundCommandFailure failure) {
    state = state.copyWith(
      busy: false,
      error: failure,
      pendingCommand: null,
      requiresReadRetry: false,
      actionsDenied: true,
      acknowledged: false,
      confirmedAction: null,
    );
    _releasePendingOperationIfIdle();
  }

  void _setValidationError(OutboundCommandFailureCode code) {
    if (!_isMounted) return;
    state = state.copyWith(
      busy: false,
      error: OutboundCommandFailure(code),
      pendingCommand: null,
      acknowledged: false,
      confirmedAction: null,
      requiresReadRetry: false,
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

  bool _isSessionUsable(OperationalSession? session) =>
      session != null && session.userId != null && session.failure == null;

  bool _isCurrent(OperationalSession session, int revision, int operation) =>
      _isMounted &&
      identical(session, _activeSession) &&
      revision == _sessionRevision &&
      operation == _operationGeneration &&
      _isSessionUsable(session);

  static bool _sameUuid(String left, String right) =>
      left.trim().toLowerCase() == right.trim().toLowerCase();

  static bool _isEligibleAction(
    DeliveryTaskSnapshot task,
    OutboundTaskAction action,
  ) {
    if (!canExecuteOutboundAction(task, action)) return false;
    // The timestamp is a client-side lifecycle guard only; custody and role
    // authorization remain server-owned. It still must be present before a
    // start confirmation can be submitted.
    return action != OutboundTaskAction.startDelivery ||
        task.acceptedAt != null;
  }

  static bool _sameTaskSnapshot(
    DeliveryTaskSnapshot left,
    DeliveryTaskSnapshot right,
  ) => left == right;

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
