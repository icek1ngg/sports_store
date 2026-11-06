import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/operational_providers.dart';
import '../../data/repositories/operational_read_access.dart';
import '../../domain/models/delivery_task.dart';
import '../../domain/models/delivery_task_details.dart';
import '../../domain/models/operational_failure.dart';
import '../../domain/models/outbound_failure_command.dart';
import '../../domain/models/outbound_task_command.dart';
import '../../domain/models/redelivery_command.dart';
import 'delivery_task_detail_view_model.dart';
import 'outbound_result_gate.dart';
import 'redelivery_providers.dart';

/// Screen-facing state for the production redelivery actions.
final class RedeliveryState {
  const RedeliveryState({
    required this.details,
    this.busy = false,
    this.error,
    this.pendingCommand,
    this.requiresReadRetry = false,
    this.actionsDenied = false,
    this.acknowledged = false,
    this.confirmed = false,
    this.confirmedOperation,
  });

  const RedeliveryState.initial()
    : this(details: const AsyncLoading<DeliveryTaskDetails>());

  final AsyncValue<DeliveryTaskDetails> details;
  final bool busy;
  final OutboundCommandFailure? error;
  final RedeliveryCommand? pendingCommand;
  final bool requiresReadRetry;
  final bool actionsDenied;
  final bool acknowledged;
  final bool confirmed;
  final RedeliveryOperation? confirmedOperation;

  bool get awaitingAuthoritativeRead =>
      acknowledged && (busy || requiresReadRetry);

  bool get actionBlocked =>
      busy ||
      pendingCommand != null ||
      requiresReadRetry ||
      actionsDenied ||
      (acknowledged && !confirmed);

  bool get canAccept =>
      !actionBlocked &&
      details.hasValue &&
      RedeliveryViewModel.canAcceptDetails(details.requireValue);

  bool get canStart =>
      !actionBlocked &&
      details.hasValue &&
      RedeliveryViewModel.canStartDetails(details.requireValue);

  bool get canComplete =>
      !actionBlocked &&
      details.hasValue &&
      RedeliveryViewModel.canOutcomeDetails(details.requireValue);

  bool get canFail => canComplete;

  static const _unset = Object();

  RedeliveryState copyWith({
    AsyncValue<DeliveryTaskDetails>? details,
    bool? busy,
    Object? error = _unset,
    Object? pendingCommand = _unset,
    bool? requiresReadRetry,
    bool? actionsDenied,
    bool? acknowledged,
    bool? confirmed,
    Object? confirmedOperation = _unset,
  }) => RedeliveryState(
    details: details ?? this.details,
    busy: busy ?? this.busy,
    error: identical(error, _unset)
        ? this.error
        : error as OutboundCommandFailure?,
    pendingCommand: identical(pendingCommand, _unset)
        ? this.pendingCommand
        : pendingCommand as RedeliveryCommand?,
    requiresReadRetry: requiresReadRetry ?? this.requiresReadRetry,
    actionsDenied: actionsDenied ?? this.actionsDenied,
    acknowledged: acknowledged ?? this.acknowledged,
    confirmed: confirmed ?? this.confirmed,
    confirmedOperation: identical(confirmedOperation, _unset)
        ? this.confirmedOperation
        : confirmedOperation as RedeliveryOperation?,
  );
}

final redeliveryViewModelProvider = NotifierProvider.autoDispose
    .family<RedeliveryViewModel, RedeliveryState, String>(
      RedeliveryViewModel.new,
    );

/// Coordinates idempotent redelivery writes and authoritative reads.
final class RedeliveryViewModel extends Notifier<RedeliveryState> {
  RedeliveryViewModel(this.taskId);

  final String taskId;
  OperationalSession? _activeSession;
  ProviderSubscription<AsyncValue<OperationalSession>>? _sessionSubscription;
  ProviderSubscription<AsyncValue<DeliveryTaskDetails>>? _detailSubscription;
  DeliveryTaskDetails? _currentDetails;
  RedeliveryCommand? _acknowledgedCommand;
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

  int get sessionRevisionForConfirmation => _sessionRevision;

  @override
  RedeliveryState build() {
    _disposed = false;
    _visible = true;
    _activeSession = null;
    _currentDetails = null;
    _acknowledgedCommand = null;
    _sessionRevision++;
    _sessionEventVersion++;
    _detailEventVersion++;
    _operationGeneration++;
    _ackReadDeferred = false;
    _rejectedReadDeferred = false;
    _detailInvalidationDeferred = false;
    final gate = ref.read(outboundResultGateProvider(taskId).notifier);

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
      scheduleMicrotask(() => gate.release(this));
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
    });
    return const RedeliveryState.initial();
  }

  Future<void> submitAccept({
    DeliveryTaskSnapshot? expectedTask,
    Iterable<DeliveryTaskItem>? expectedItems,
    int? sessionRevision,
  }) async {
    if (!_readyForSubmit(sessionRevision)) return;
    final details = _readCurrentDetails();
    if (details == null || !canAcceptDetails(details)) {
      _setValidationError(OutboundCommandFailureCode.staleState);
      return;
    }
    final task = details.task;
    if (expectedTask != null && expectedTask != task) {
      _setValidationError(OutboundCommandFailureCode.staleState);
      return;
    }
    final plan = (expectedItems ?? details.items).toList(growable: false);
    if (!_sameItems(plan, details.items)) {
      _setValidationError(OutboundCommandFailureCode.staleState);
      return;
    }
    late final RedeliveryCommand command;
    try {
      command = RedeliveryCommand.accept(
        taskId: task.taskId,
        requestId: ref.read(redeliveryRequestIdProvider)(),
        returnRequestId: task.returnRequestId!,
        orderId: task.orderId!,
        items: _canonicalItems(plan),
      );
      if (!command.isValid) {
        throw const FormatException('invalid redelivery plan');
      }
    } on Object {
      _setValidationError(OutboundCommandFailureCode.invalidData);
      return;
    }
    await _submitCommand(command);
  }

  Future<void> submitStart({
    DeliveryTaskSnapshot? expectedTask,
    int? sessionRevision,
  }) async {
    if (!_readyForSubmit(sessionRevision)) return;
    final details = _readCurrentDetails();
    if (details == null || !canStartDetails(details)) {
      _setValidationError(OutboundCommandFailureCode.staleState);
      return;
    }
    final task = details.task;
    if (expectedTask != null && expectedTask != task) {
      _setValidationError(OutboundCommandFailureCode.staleState);
      return;
    }
    late final RedeliveryCommand command;
    try {
      command = RedeliveryCommand.start(
        taskId: task.taskId,
        requestId: ref.read(redeliveryRequestIdProvider)(),
        returnRequestId: task.returnRequestId!,
        orderId: task.orderId!,
      );
      if (!command.isValid) {
        throw const FormatException('invalid redelivery start');
      }
    } on Object {
      _setValidationError(OutboundCommandFailureCode.invalidData);
      return;
    }
    await _submitCommand(command);
  }

  Future<void> submitComplete({
    DeliveryTaskSnapshot? expectedTask,
    Iterable<DeliveryTaskItem>? expectedItems,
    int? sessionRevision,
  }) async {
    if (!_readyForSubmit(sessionRevision)) return;
    final details = _readCurrentDetails();
    if (details == null || !canOutcomeDetails(details)) {
      _setValidationError(OutboundCommandFailureCode.staleState);
      return;
    }
    final task = details.task;
    final plan = (expectedItems ?? details.items).toList(growable: false);
    if ((expectedTask != null && expectedTask != task) ||
        !_sameItems(plan, details.items) ||
        !_isFullPlan(details.items)) {
      _setValidationError(OutboundCommandFailureCode.staleState);
      return;
    }
    late final RedeliveryCommand command;
    try {
      command = RedeliveryCommand.complete(
        taskId: task.taskId,
        requestId: ref.read(redeliveryRequestIdProvider)(),
        returnRequestId: task.returnRequestId!,
        orderId: task.orderId!,
      );
      if (!command.isValid) {
        throw const FormatException('invalid redelivery completion');
      }
    } on Object {
      _setValidationError(OutboundCommandFailureCode.invalidData);
      return;
    }
    await _submitCommand(command);
  }

  Future<void> submitFailure({
    required OutboundFailureReason reason,
    String? description,
    DeliveryTaskSnapshot? expectedTask,
    int? sessionRevision,
  }) async {
    if (!_readyForSubmit(sessionRevision)) return;
    final details = _readCurrentDetails();
    if (details == null || !canOutcomeDetails(details)) {
      _setValidationError(OutboundCommandFailureCode.staleState);
      return;
    }
    final task = details.task;
    if (expectedTask != null && expectedTask != task) {
      _setValidationError(OutboundCommandFailureCode.staleState);
      return;
    }
    late final RedeliveryCommand command;
    try {
      command = RedeliveryCommand.fail(
        taskId: task.taskId,
        requestId: ref.read(redeliveryRequestIdProvider)(),
        returnRequestId: task.returnRequestId!,
        orderId: task.orderId!,
        reason: reason,
        description: description,
      );
      if (!command.isValid) {
        throw const FormatException('invalid redelivery reason');
      }
    } on Object {
      _setValidationError(OutboundCommandFailureCode.invalidData);
      return;
    }
    await _submitCommand(command);
  }

  Future<void> submit({
    required RedeliveryOperation operation,
    DeliveryTaskSnapshot? expectedTask,
    Iterable<DeliveryTaskItem>? expectedItems,
    OutboundFailureReason? reason,
    String? description,
    int? sessionRevision,
  }) async {
    switch (operation) {
      case RedeliveryOperation.accept:
        await submitAccept(
          expectedTask: expectedTask,
          expectedItems: expectedItems,
          sessionRevision: sessionRevision,
        );
      case RedeliveryOperation.start:
        await submitStart(
          expectedTask: expectedTask,
          sessionRevision: sessionRevision,
        );
      case RedeliveryOperation.complete:
        await submitComplete(
          expectedTask: expectedTask,
          expectedItems: expectedItems,
          sessionRevision: sessionRevision,
        );
      case RedeliveryOperation.fail:
        if (reason == null) {
          _setValidationError(OutboundCommandFailureCode.invalidData);
          return;
        }
        await submitFailure(
          reason: reason,
          description: description,
          expectedTask: expectedTask,
          sessionRevision: sessionRevision,
        );
    }
  }

  Future<void> accept({
    DeliveryTaskSnapshot? expectedTask,
    Iterable<DeliveryTaskItem>? expectedItems,
    int? sessionRevision,
  }) => submitAccept(
    expectedTask: expectedTask,
    expectedItems: expectedItems,
    sessionRevision: sessionRevision,
  );

  Future<void> start({
    DeliveryTaskSnapshot? expectedTask,
    int? sessionRevision,
  }) =>
      submitStart(expectedTask: expectedTask, sessionRevision: sessionRevision);

  Future<void> complete({
    DeliveryTaskSnapshot? expectedTask,
    Iterable<DeliveryTaskItem>? expectedItems,
    int? sessionRevision,
  }) => submitComplete(
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

  /// Retry the same write envelope or the read/list reconciliation only.
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
    }
  }

  Future<void> _submitCommand(RedeliveryCommand command) async {
    if (!_isMounted ||
        !_visible ||
        state.busy ||
        state.pendingCommand != null ||
        (state.acknowledged && !state.confirmed)) {
      return;
    }
    final session = _activeSession;
    if (!_isSessionUsable(session) || state.actionsDenied) return;
    final revision = _sessionRevision;
    final generation = _operationGeneration;
    if (!ref.read(outboundResultGateProvider(taskId).notifier).acquire(this)) {
      return;
    }
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
    RedeliveryCommand command,
    OperationalSession session,
    int revision,
    int generation,
  ) async {
    if (!_isCurrent(session, revision, generation) || !_visible) return;
    try {
      final ack = await ref.read(redeliveryRepositoryProvider).execute(command);
      if (!ack.matches(command)) throw const OutboundAcknowledgementFailure();
    } on Object catch (error) {
      if (!_isCurrent(session, revision, generation)) return;
      final failure = _mapFailure(error);
      if (_isAuthInvalidation(failure)) {
        _clearForAuth(failure);
        return;
      }
      if (_isUncertainWrite(failure)) {
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
    RedeliveryCommand command,
    OperationalSession session,
    int revision,
    int generation,
  ) async {
    if (!_isCurrent(session, revision, generation)) return;
    if (!_visible) {
      _ackReadDeferred = true;
      state = state.copyWith(busy: false, requiresReadRetry: true);
      _retainPendingOperation();
      return;
    }
    _ackReadDeferred = false;
    state = state.copyWith(busy: true, error: null);
    late final DeliveryTaskDetails details;
    try {
      details = await ref.read(redeliveryDetailsReloadProvider)(taskId);
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

    if (!_isCurrent(session, revision, generation)) return;
    try {
      await ref.read(redeliveryTaskListReloadProvider)();
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
      final details = await ref.read(redeliveryDetailsReloadProvider)(taskId);
      if (!_isCurrent(session, revision, generation) ||
          !_sameUuid(details.task.taskId, taskId)) {
        throw const OutboundCommandFailure(
          OutboundCommandFailureCode.invalidData,
        );
      }
      _currentDetails = details;
      state = state.copyWith(details: AsyncData(details));
      await ref.read(redeliveryTaskListReloadProvider)();
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
    final frozen = state.pendingCommand;
    final acknowledged = _acknowledgedCommand;
    _activeSession = incoming;
    _sessionRevision++;
    _operationGeneration++;
    _currentDetails = null;
    _detailEventVersion++;
    _invalidateDetailProjection();

    if (sameActor && frozen != null) {
      state = state.copyWith(
        details: const AsyncLoading(),
        busy: false,
        pendingCommand: frozen,
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

  void _replaceSession(OperationalSession? session, Object failure) {
    if (!_isMounted) return;
    _activeSession = session;
    _sessionRevision++;
    _operationGeneration++;
    _currentDetails = null;
    _acknowledgedCommand = null;
    _detailEventVersion++;
    _invalidateDetailProjection();
    _setAuthState(_mapFailure(failure));
  }

  void _adoptCurrentProjectionIfReady() {
    if (!_isMounted || !_isSessionUsable(_activeSession)) return;
    final projected = ref.read(deliveryTaskDetailViewModelProvider(taskId));
    if (!projected.hasValue) return;
    final details = projected.requireValue;
    if (!_sameUuid(details.task.taskId, taskId)) return;
    _currentDetails = details;
    state = state.copyWith(details: AsyncData(details));
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
        !(state.acknowledged && !state.confirmed) &&
        (revision == null || revision == _sessionRevision);
  }

  DeliveryTaskDetails? _readCurrentDetails() {
    if (!_isMounted) return null;
    if (state.details.hasValue) {
      final details = state.details.requireValue;
      if (!_sameUuid(details.task.taskId, taskId)) return null;
      _currentDetails = details;
    }
    return _currentDetails;
  }

  void _validateAcknowledgedDetails(
    RedeliveryCommand command,
    DeliveryTaskDetails details,
  ) {
    final task = details.task;
    if (!_sameUuid(task.taskId, command.taskId) ||
        task.kind != DeliveryTaskKind.redelivery) {
      throw const OutboundCommandFailure(
        OutboundCommandFailureCode.invalidData,
      );
    }
    if (command.isAccept) {
      if (!canStartDetails(details) ||
          task.status != DeliveryTaskStatus.accepted) {
        throw const OutboundCommandFailure(
          OutboundCommandFailureCode.staleState,
        );
      }
      _checkPlanMatches(details.items, command.items);
      return;
    }
    if (command.isStart) {
      if (!canOutcomeDetails(details) ||
          task.status != DeliveryTaskStatus.inTransit) {
        throw const OutboundCommandFailure(
          OutboundCommandFailureCode.staleState,
        );
      }
      return;
    }
    if (command.isComplete) {
      if (task.status != DeliveryTaskStatus.delivered ||
          task.scope == DeliverySnapshotScope.current &&
              task.completedAt == null) {
        throw const OutboundCommandFailure(
          OutboundCommandFailureCode.staleState,
        );
      }
      return;
    }
    if (task.status != DeliveryTaskStatus.managerActionRequired ||
        task.completedAt != null) {
      throw const OutboundCommandFailure(OutboundCommandFailureCode.staleState);
    }
  }

  static bool canAcceptDetails(DeliveryTaskDetails details) {
    final task = details.task;
    return _baseCurrent(details) &&
        task.status == DeliveryTaskStatus.assigned &&
        task.assignedAt != null &&
        task.acceptedAt == null &&
        task.startedAt == null &&
        task.completedAt == null &&
        _isFullPlan(details.items);
  }

  static bool canStartDetails(DeliveryTaskDetails details) {
    final task = details.task;
    return _baseCurrent(details) &&
        task.status == DeliveryTaskStatus.accepted &&
        task.assignedAt != null &&
        task.acceptedAt != null &&
        task.startedAt == null &&
        task.completedAt == null &&
        _isFullPlan(details.items);
  }

  static bool canOutcomeDetails(DeliveryTaskDetails details) {
    final task = details.task;
    if (!_baseCurrent(details) ||
        task.status != DeliveryTaskStatus.inTransit ||
        task.assignedAt == null ||
        task.acceptedAt == null ||
        task.startedAt == null ||
        task.completedAt != null ||
        !_isFullPlan(details.items)) {
      return false;
    }
    // The server owns the physical custody timestamps; either an equal
    // transaction timestamp or a later start timestamp is valid.
    return !task.acceptedAt!.isAfter(task.startedAt!);
  }

  static bool _baseCurrent(DeliveryTaskDetails details) {
    final task = details.task;
    return task.kind == DeliveryTaskKind.redelivery &&
        task.scope == DeliverySnapshotScope.current &&
        task.amountToCollectVnd == 0 &&
        task.orderId != null &&
        task.returnRequestId != null &&
        _isUuid(task.taskId) &&
        _isUuid(task.orderId!) &&
        _isUuid(task.returnRequestId!);
  }

  static bool _isFullPlan(List<DeliveryTaskItem> items) {
    if (items.isEmpty) return false;
    String? previous;
    final seen = <String>{};
    for (final item in items) {
      final id = item.itemId.toLowerCase();
      if (!_isUuid(item.itemId) ||
          item.quantity < 1 ||
          item.quantity > _maxInt32 ||
          item.itemSource != DeliveryItemSource.returnPlan ||
          item.quantityCollected != item.quantity ||
          !seen.add(id) ||
          (previous != null && id.compareTo(previous) < 0)) {
        return false;
      }
      previous = id;
    }
    return true;
  }

  static List<RedeliveryItem> _canonicalItems(
    Iterable<DeliveryTaskItem> items,
  ) {
    final result = items
        .map(
          (item) =>
              RedeliveryItem(itemId: item.itemId, quantity: item.quantity),
        )
        .toList(growable: false);
    result.sort(
      (a, b) => a.itemId.toLowerCase().compareTo(b.itemId.toLowerCase()),
    );
    return List.unmodifiable(result);
  }

  static void _checkPlanMatches(
    List<DeliveryTaskItem> actual,
    List<RedeliveryItem> expected,
  ) {
    final canonical = _canonicalItems(actual);
    if (canonical.length != expected.length ||
        canonical.asMap().entries.any(
          (entry) => entry.value != expected[entry.key],
        )) {
      throw const OutboundCommandFailure(OutboundCommandFailureCode.staleState);
    }
  }

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
          left.itemSource != right.itemSource ||
          left.productName != right.productName) {
        return false;
      }
    }
    return true;
  }

  bool get _hasPendingWork =>
      state.pendingCommand != null ||
      state.busy ||
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
    _invalidateDetailProjection();
    _setAuthState(failure);
  }

  void _setAuthState(OutboundCommandFailure failure) {
    state = state.copyWith(
      details: AsyncError(failure, StackTrace.empty),
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
