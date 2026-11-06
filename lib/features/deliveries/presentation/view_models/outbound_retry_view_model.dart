import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/operational_providers.dart';
import '../../data/repositories/operational_read_access.dart';
import '../../domain/models/delivery_task.dart';
import '../../domain/models/delivery_task_details.dart';
import '../../domain/models/operational_failure.dart';
import '../../domain/models/outbound_task_command.dart';
import '../../domain/models/outbound_retry_command.dart';
import 'outbound_retry_providers.dart';
import 'outbound_result_gate.dart';

/// State for the explicit shipper-owned second-attempt transition.
///
/// The failed task remains the source of truth until the server creates task
/// 2 and a fresh detail read proves that task 2 is assigned to this shipper.
class OutboundRetryState {
  const OutboundRetryState({
    this.busy = false,
    this.error,
    this.pendingCommand,
    this.acknowledgement,
    this.retryDetails,
    this.requiresReadRetry = false,
    this.awaitingAuthoritativeRead = false,
    this.actionsDenied = false,
    this.confirmed = false,
  });

  final bool busy;
  final OutboundCommandFailure? error;
  final OutboundRetryCommand? pendingCommand;
  final OutboundRetryAck? acknowledgement;
  final DeliveryTaskDetails? retryDetails;
  final bool requiresReadRetry;
  final bool awaitingAuthoritativeRead;
  final bool actionsDenied;
  final bool confirmed;

  String? get retryTaskId => acknowledgement?.retryTaskId;

  OutboundRetryState copyWith({
    bool? busy,
    Object? error = _unset,
    Object? pendingCommand = _unset,
    Object? acknowledgement = _unset,
    Object? retryDetails = _unset,
    bool? requiresReadRetry,
    bool? awaitingAuthoritativeRead,
    bool? actionsDenied,
    bool? confirmed,
  }) => OutboundRetryState(
    busy: busy ?? this.busy,
    error: identical(error, _unset)
        ? this.error
        : error as OutboundCommandFailure?,
    pendingCommand: identical(pendingCommand, _unset)
        ? this.pendingCommand
        : pendingCommand as OutboundRetryCommand?,
    acknowledgement: identical(acknowledgement, _unset)
        ? this.acknowledgement
        : acknowledgement as OutboundRetryAck?,
    retryDetails: identical(retryDetails, _unset)
        ? this.retryDetails
        : retryDetails as DeliveryTaskDetails?,
    requiresReadRetry: requiresReadRetry ?? this.requiresReadRetry,
    awaitingAuthoritativeRead:
        awaitingAuthoritativeRead ?? this.awaitingAuthoritativeRead,
    actionsDenied: actionsDenied ?? this.actionsDenied,
    confirmed: confirmed ?? this.confirmed,
  );
}

const _unset = Object();

final outboundRetryViewModelProvider = NotifierProvider.autoDispose
    .family<OutboundRetryViewModel, OutboundRetryState, String>(
      OutboundRetryViewModel.new,
    );

class OutboundRetryViewModel extends Notifier<OutboundRetryState> {
  OutboundRetryViewModel(this.failedTaskId);

  final String failedTaskId;
  OperationalSession? _session;
  ProviderSubscription<AsyncValue<OperationalSession>>? _sessionSubscription;
  var _disposed = false;
  var _visible = true;
  var _initialized = false;
  var _sessionRevision = 0;
  var _generation = 0;
  var _awaitingRead = false;
  var _taskListRefreshNeeded = false;
  void Function()? _closeKeepAlive;

  @override
  OutboundRetryState build() {
    final resultGate = ref.read(
      outboundResultGateProvider(failedTaskId).notifier,
    );
    _disposed = false;
    _visible = true;
    _initialized = false;
    _sessionRevision++;
    _generation++;
    _sessionSubscription = ref.container.listen<AsyncValue<OperationalSession>>(
      operationalSessionProvider,
      (_, next) => _scheduleSession(next),
      fireImmediately: true,
    );
    ref.onCancel(() {
      scheduleMicrotask(() {
        if (_disposed) return;
        _visible = false;
        final needsRecovery =
            state.pendingCommand != null ||
            state.awaitingAuthoritativeRead ||
            state.acknowledgement != null && !state.confirmed;
        if (needsRecovery) {
          state = state.copyWith(busy: false, requiresReadRetry: true);
          _retainPendingOperation();
        } else {
          _releasePendingOperationIfIdle();
        }
      });
    });
    ref.onResume(() {
      scheduleMicrotask(() {
        _visible = true;
        if (!_disposed &&
            _session != null &&
            (state.pendingCommand != null ||
                (state.acknowledgement != null && state.requiresReadRetry))) {
          unawaited(retry());
        }
      });
    });
    ref.onDispose(() {
      scheduleMicrotask(() => resultGate.release(this));
      _disposed = true;
      _generation++;
      _sessionRevision++;
      _sessionSubscription?.close();
      _sessionSubscription = null;
      _closeKeepAlive?.call();
      _closeKeepAlive = null;
    });
    scheduleMicrotask(_loadSession);
    return const OutboundRetryState();
  }

  Future<void> _loadSession() async {
    if (_disposed) return;
    _handleSession(ref.read(operationalSessionProvider));
    _initialized = true;
  }

  void _scheduleSession(AsyncValue<OperationalSession> next) {
    scheduleMicrotask(() {
      if (!_disposed) _handleSession(next);
    });
  }

  void _handleSession(AsyncValue<OperationalSession> next) {
    if (_disposed || next.isLoading) return;
    if (next.hasError) {
      _setDenied(
        const OutboundCommandFailure(OutboundCommandFailureCode.sessionExpired),
      );
      return;
    }
    final incoming = next.requireValue;
    if (identical(incoming, _session)) return;
    final old = _session;
    final sameActor =
        _usable(old) && _usable(incoming) && old!.userId == incoming.userId;
    _session = incoming;
    _sessionRevision++;
    _generation++;
    if (sameActor) {
      state = state.copyWith(
        busy: false,
        requiresReadRetry:
            state.requiresReadRetry || state.awaitingAuthoritativeRead,
      );
      if (state.pendingCommand != null || state.awaitingAuthoritativeRead) {
        _retainPendingOperation();
      }
      return;
    }
    // A task detail route can outlive an auth switch. Never carry a request
    // envelope, ACK or freshly created task ID from actor A into actor B.
    // The new actor must start from its own detail/list projection.
    if (_usable(incoming)) {
      ref.read(outboundResultGateProvider(failedTaskId).notifier).release(this);
      _awaitingRead = false;
      _taskListRefreshNeeded = false;
      state = state.copyWith(
        busy: false,
        error: null,
        pendingCommand: null,
        acknowledgement: null,
        retryDetails: null,
        requiresReadRetry: false,
        awaitingAuthoritativeRead: false,
        actionsDenied: false,
        confirmed: false,
      );
      _releasePendingOperationIfIdle();
      return;
    }
    if (!_usable(incoming)) {
      ref.read(outboundResultGateProvider(failedTaskId).notifier).release(this);
      state = state.copyWith(
        busy: false,
        error: const OutboundCommandFailure(
          OutboundCommandFailureCode.sessionExpired,
        ),
        pendingCommand: null,
        acknowledgement: null,
        retryDetails: null,
        requiresReadRetry: false,
        awaitingAuthoritativeRead: false,
        actionsDenied: true,
        confirmed: false,
      );
      _releasePendingOperationIfIdle();
      return;
    }
    if (_initialized && state.pendingCommand != null) {
      _retainPendingOperation();
    }
  }

  /// Starts the server transition after the caller has shown the explicit
  /// confirmation. The failed task identity is the only business input.
  Future<String?> submit({
    required DeliveryTaskSnapshot task,
    bool canRetry = false,
  }) async {
    final session = _session;
    if (_disposed ||
        !_visible ||
        session == null ||
        !_usable(session) ||
        state.busy ||
        state.pendingCommand != null ||
        state.acknowledgement != null ||
        state.requiresReadRetry ||
        !_eligible(task, canRetry: canRetry)) {
      if (!_eligible(task, canRetry: canRetry) && !_disposed) {
        _validation(OutboundCommandFailureCode.staleState);
      }
      return null;
    }
    final command = OutboundRetryCommand(
      taskId: failedTaskId,
      requestId: ref.read(outboundRetryRequestIdProvider)(),
    );
    if (!command.isValid) {
      _validation(OutboundCommandFailureCode.invalidData);
      return null;
    }
    _retainPendingOperation();
    await _execute(command, session, _sessionRevision);
    return state.confirmed ? state.retryTaskId : null;
  }

  /// Retries the exact write envelope after an uncertain RPC response, or
  /// performs only the authoritative read after an ACK whose read failed.
  Future<String?> retry() async {
    final session = _session;
    if (_disposed ||
        !_visible ||
        session == null ||
        !_usable(session) ||
        state.busy) {
      return null;
    }
    final revision = _sessionRevision;
    final pending = state.pendingCommand;
    if (pending != null) {
      await _execute(pending, session, revision);
      return state.confirmed ? state.retryTaskId : null;
    }
    if (state.acknowledgement != null) {
      final readOk = await _readRetryTask(
        session,
        revision,
        preserveError: state.error,
      );
      if (readOk && _epochCurrent(session, revision)) {
        await _refreshList(session, revision);
        return state.confirmed ? state.retryTaskId : null;
      }
    }
    return null;
  }

  Future<void> _execute(
    OutboundRetryCommand command,
    OperationalSession session,
    int revision,
  ) async {
    if (!_epochCurrent(session, revision)) return;
    final gate = ref.read(outboundResultGateProvider(failedTaskId).notifier);
    if (!gate.acquire(this)) return;
    state = state.copyWith(
      busy: true,
      error: null,
      pendingCommand: command,
      requiresReadRetry: false,
    );
    try {
      final ack = await ref
          .read(outboundRetryRepositoryProvider)
          .execute(command);
      if (!_epochCurrent(session, revision) ||
          !ack.isValid ||
          !ack.matches(command)) {
        throw const OutboundAcknowledgementFailure();
      }
      state = state.copyWith(
        acknowledgement: ack,
        pendingCommand: null,
        awaitingAuthoritativeRead: true,
        requiresReadRetry: !_visible,
        busy: _visible,
        error: null,
      );
      _awaitingRead = true;
      _taskListRefreshNeeded = true;
      _retainPendingOperation();
      if (!_visible) return;
      final readOk = await _readRetryTask(session, revision);
      if (readOk && _epochCurrent(session, revision)) {
        await _refreshList(session, revision);
      }
    } catch (error) {
      if (!_epochCurrent(session, revision)) return;
      final failure = _map(error);
      final uncertain =
          failure is OutboundAcknowledgementFailure ||
          failure.code == OutboundCommandFailureCode.timeout ||
          failure.code == OutboundCommandFailureCode.network ||
          failure.code == OutboundCommandFailureCode.dependencyUnavailable ||
          failure.code == OutboundCommandFailureCode.unexpected;
      if (failure.code == OutboundCommandFailureCode.permissionDenied ||
          failure.code == OutboundCommandFailureCode.sessionExpired ||
          failure.code == OutboundCommandFailureCode.staleAssignment) {
        _setDenied(failure);
        return;
      }
      state = state.copyWith(
        busy: false,
        error: failure,
        pendingCommand: uncertain ? command : null,
        requiresReadRetry: false,
      );
      if (!uncertain) _releasePendingOperationIfIdle();
    }
  }

  Future<bool> _readRetryTask(
    OperationalSession session,
    int revision, {
    OutboundCommandFailure? preserveError,
  }) async {
    final ack = state.acknowledgement;
    if (ack == null || !_current(session, revision)) return false;
    final generation = ++_generation;
    state = state.copyWith(
      busy: true,
      error: preserveError,
      awaitingAuthoritativeRead: true,
      requiresReadRetry: false,
    );
    try {
      final details = await ref.read(outboundRetryDetailsReloadProvider)(
        ack.retryTaskId,
      );
      if (!_current(session, revision) || generation != _generation) {
        return false;
      }
      final task = details.task;
      if (task.taskId.toLowerCase() != ack.retryTaskId.toLowerCase() ||
          task.kind != DeliveryTaskKind.outbound ||
          task.status != DeliveryTaskStatus.assigned ||
          task.attemptNumber != 2 ||
          task.scope != DeliverySnapshotScope.current ||
          task.acceptedAt != null ||
          task.startedAt != null) {
        throw const OutboundCommandFailure(
          OutboundCommandFailureCode.staleState,
        );
      }
      _awaitingRead = false;
      state = state.copyWith(
        busy: false,
        error: preserveError,
        retryDetails: details,
        awaitingAuthoritativeRead: false,
        requiresReadRetry: false,
        confirmed: true,
      );
      return true;
    } catch (error) {
      if (!_current(session, revision)) return false;
      final failure = _map(error);
      state = state.copyWith(
        busy: false,
        error: preserveError ?? failure,
        requiresReadRetry: true,
        awaitingAuthoritativeRead: _awaitingRead,
      );
      _retainPendingOperation();
      return false;
    }
  }

  Future<void> _refreshList(OperationalSession session, int revision) async {
    if (!_epochCurrent(session, revision) || !_taskListRefreshNeeded) return;
    if (!_visible) {
      state = state.copyWith(busy: false, requiresReadRetry: true);
      _retainPendingOperation();
      return;
    }
    state = state.copyWith(busy: true);
    try {
      await ref.read(outboundRetryTaskListReloadProvider)();
      if (!_epochCurrent(session, revision)) return;
      _taskListRefreshNeeded = false;
      state = state.copyWith(busy: false, error: null);
      _releasePendingOperationIfIdle();
    } catch (error) {
      if (!_epochCurrent(session, revision)) return;
      state = state.copyWith(
        busy: false,
        error: _map(error),
        requiresReadRetry: true,
      );
      _retainPendingOperation();
    }
  }

  void _validation(OutboundCommandFailureCode code) {
    if (!_disposed) state = state.copyWith(error: OutboundCommandFailure(code));
  }

  void _setDenied(OutboundCommandFailure failure) {
    if (_disposed) return;
    ref.read(outboundResultGateProvider(failedTaskId).notifier).release(this);
    state = state.copyWith(
      busy: false,
      error: failure,
      pendingCommand: null,
      acknowledgement: null,
      retryDetails: null,
      actionsDenied: true,
      awaitingAuthoritativeRead: false,
      requiresReadRetry: false,
      confirmed: false,
    );
    _closeKeepAlive?.call();
    _closeKeepAlive = null;
  }

  bool _epochCurrent(OperationalSession session, int revision) =>
      !_disposed &&
      ref.mounted &&
      identical(session, _session) &&
      revision == _sessionRevision &&
      _usable(session);

  bool _current(OperationalSession session, int revision) =>
      _epochCurrent(session, revision) && _visible;

  void _retainPendingOperation() {
    _closeKeepAlive ??= ref.keepAlive().close;
  }

  void _releasePendingOperationIfIdle() {
    if (state.pendingCommand != null ||
        state.busy ||
        state.awaitingAuthoritativeRead ||
        state.requiresReadRetry ||
        _taskListRefreshNeeded) {
      return;
    }
    ref.read(outboundResultGateProvider(failedTaskId).notifier).release(this);
    _closeKeepAlive?.call();
    _closeKeepAlive = null;
  }

  static bool _eligible(DeliveryTaskSnapshot task, {required bool canRetry}) =>
      task.taskId.isNotEmpty &&
      task.kind == DeliveryTaskKind.outbound &&
      task.status == DeliveryTaskStatus.failed &&
      task.attemptNumber == 1 &&
      (task.scope == DeliverySnapshotScope.restricted ||
          task.scope == DeliverySnapshotScope.current ||
          (task.scope == DeliverySnapshotScope.history && canRetry));

  static bool _usable(OperationalSession? value) =>
      value != null && value.userId != null && value.failure == null;

  static OutboundCommandFailure _map(Object error) {
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
