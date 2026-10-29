import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/operational_providers.dart';
import '../../data/repositories/operational_read_access.dart';
import '../../domain/models/delivery_task.dart';
import '../../domain/models/delivery_task_details.dart';
import '../../domain/models/operational_failure.dart';
import '../../domain/models/outbound_completion_command.dart';
import '../../domain/models/outbound_task_command.dart';
import 'outbound_completion_providers.dart';
import 'outbound_result_gate.dart';

class OutboundCompletionState {
  const OutboundCompletionState({
    required this.details,
    this.busy = false,
    this.error,
    this.pendingCommand,
    this.requiresReadRetry = false,
    this.actionsDenied = false,
    this.awaitingAuthoritativeRead = false,
    this.confirmed = false,
  });

  const OutboundCompletionState.initial()
    : this(details: const AsyncLoading<DeliveryTaskDetails>());

  final AsyncValue<DeliveryTaskDetails> details;
  final bool busy;
  final OutboundCommandFailure? error;
  final OutboundCompletionCommand? pendingCommand;
  final bool requiresReadRetry;
  final bool actionsDenied;
  final bool awaitingAuthoritativeRead;
  final bool confirmed;

  int? get authoritativeAmountVnd =>
      details.hasValue ? details.requireValue.task.amountToCollectVnd : null;

  bool get canComplete {
    if (busy ||
        actionsDenied ||
        requiresReadRetry ||
        awaitingAuthoritativeRead ||
        confirmed ||
        pendingCommand != null ||
        !details.hasValue) {
      return false;
    }
    final task = details.requireValue.task;
    return task.kind == DeliveryTaskKind.outbound &&
        task.scope == DeliverySnapshotScope.current &&
        task.status == DeliveryTaskStatus.inTransit &&
        task.attemptNumber >= 1 &&
        task.attemptNumber <= 2 &&
        task.acceptedAt != null &&
        task.startedAt != null &&
        (task.amountToCollectVnd ?? 0) > 0;
  }

  OutboundCompletionState copyWith({
    AsyncValue<DeliveryTaskDetails>? details,
    bool? busy,
    Object? error = _unset,
    Object? pendingCommand = _unset,
    bool? requiresReadRetry,
    bool? actionsDenied,
    bool? awaitingAuthoritativeRead,
    bool? confirmed,
  }) => OutboundCompletionState(
    details: details ?? this.details,
    busy: busy ?? this.busy,
    error: identical(error, _unset)
        ? this.error
        : error as OutboundCommandFailure?,
    pendingCommand: identical(pendingCommand, _unset)
        ? this.pendingCommand
        : pendingCommand as OutboundCompletionCommand?,
    requiresReadRetry: requiresReadRetry ?? this.requiresReadRetry,
    actionsDenied: actionsDenied ?? this.actionsDenied,
    awaitingAuthoritativeRead:
        awaitingAuthoritativeRead ?? this.awaitingAuthoritativeRead,
    confirmed: confirmed ?? this.confirmed,
  );
}

const _unset = Object();

final outboundCompletionViewModelProvider = NotifierProvider.autoDispose
    .family<OutboundCompletionViewModel, OutboundCompletionState, String>(
      OutboundCompletionViewModel.new,
    );

class OutboundCompletionViewModel extends Notifier<OutboundCompletionState> {
  OutboundCompletionViewModel(this.taskId);

  final String taskId;
  OperationalSession? _session;
  ProviderSubscription<AsyncValue<OperationalSession>>? _sessionSubscription;
  var _disposed = false;
  var _sessionRevision = 0;
  var _generation = 0;
  var _visible = true;
  var _awaitingRead = false;
  var _taskRefreshNeeded = false;
  var _codRefreshNeeded = false;
  var _initialized = false;
  void Function()? _closeKeepAlive;

  int get sessionRevisionForConfirmation => _sessionRevision;

  @override
  OutboundCompletionState build() {
    final resultGate = ref.read(outboundResultGateProvider(taskId).notifier);
    _disposed = false;
    _visible = true;
    _sessionRevision++;
    _generation++;
    _initialized = false;
    _sessionSubscription = ref.container.listen<AsyncValue<OperationalSession>>(
      operationalSessionProvider,
      (_, next) => _scheduleSession(next),
      fireImmediately: true,
    );
    ref.onCancel(() {
      scheduleMicrotask(() {
        if (_disposed) return;
        _visible = false;
        state = state.copyWith(
          details: const AsyncLoading(),
          busy: false,
          requiresReadRetry:
              state.requiresReadRetry ||
              state.busy ||
              state.awaitingAuthoritativeRead ||
              _taskRefreshNeeded ||
              _codRefreshNeeded,
        );
        if (state.pendingCommand != null ||
            state.awaitingAuthoritativeRead ||
            _taskRefreshNeeded ||
            _codRefreshNeeded) {
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
            state.pendingCommand == null &&
            (state.requiresReadRetry || state.awaitingAuthoritativeRead)) {
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
    scheduleMicrotask(_loadInitial);
    return const OutboundCompletionState.initial();
  }

  Future<void> _loadInitial() async {
    if (_disposed) return;
    final current = ref.read(operationalSessionProvider);
    _handleSession(current);
    _initialized = true;
    final session = _session;
    if (session != null && _usable(session)) {
      await _read(session, _sessionRevision);
    }
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
      // A token refresh creates a new authorization epoch. Keep the pending
      // envelope or acknowledged read state, but stop the old busy indicator;
      // the same request ID can be retried after the new epoch is current.
      state = state.copyWith(
        busy: false,
        requiresReadRetry:
            state.requiresReadRetry || state.awaitingAuthoritativeRead,
      );
      if (state.pendingCommand != null ||
          state.awaitingAuthoritativeRead ||
          state.requiresReadRetry ||
          _taskRefreshNeeded ||
          _codRefreshNeeded) {
        _retainPendingOperation();
      } else {
        _releasePendingOperationIfIdle();
      }
      if (_initialized &&
          _visible &&
          state.pendingCommand == null &&
          !state.awaitingAuthoritativeRead) {
        unawaited(_read(incoming, _sessionRevision));
      }
      return;
    }
    if (!sameActor) {
      ref.read(outboundResultGateProvider(taskId).notifier).release(this);
      _awaitingRead = false;
      _taskRefreshNeeded = false;
      _codRefreshNeeded = false;
      state = state.copyWith(
        details: incoming.failure == null && _usable(incoming)
            ? const AsyncLoading()
            : AsyncError(
                const OutboundCommandFailure(
                  OutboundCommandFailureCode.sessionExpired,
                ),
                StackTrace.empty,
              ),
        busy: false,
        error: incoming.failure == null
            ? null
            : const OutboundCommandFailure(
                OutboundCommandFailureCode.sessionExpired,
              ),
        pendingCommand: null,
        requiresReadRetry: false,
        actionsDenied: !_usable(incoming),
        awaitingAuthoritativeRead: false,
        confirmed: false,
      );
      _releasePendingOperationIfIdle();
    }
    if (_initialized && _usable(incoming) && _visible) {
      unawaited(_read(incoming, _sessionRevision));
    }
  }

  Future<void> submit({
    required bool receivedAllItems,
    required bool receivedFullCod,
    required int displayedAmountVnd,
    required int sessionRevision,
  }) async {
    final session = _session;
    if (_disposed ||
        !_visible ||
        session == null ||
        !_usable(session) ||
        sessionRevision != _sessionRevision ||
        state.busy ||
        state.pendingCommand != null ||
        state.requiresReadRetry ||
        state.confirmed ||
        !receivedAllItems ||
        !receivedFullCod) {
      if (!_disposed && (!receivedAllItems || !receivedFullCod)) {
        _validation(OutboundCommandFailureCode.invalidData);
      }
      return;
    }
    if (!state.details.hasValue) {
      _validation(OutboundCommandFailureCode.staleState);
      return;
    }
    final task = state.details.requireValue.task;
    final amount = task.amountToCollectVnd;
    if (task.taskId != taskId ||
        task.kind != DeliveryTaskKind.outbound ||
        task.scope != DeliverySnapshotScope.current ||
        task.status != DeliveryTaskStatus.inTransit ||
        task.attemptNumber < 1 ||
        task.attemptNumber > 2 ||
        task.acceptedAt == null ||
        task.startedAt == null ||
        amount == null ||
        amount <= 0 ||
        displayedAmountVnd != amount) {
      _validation(OutboundCommandFailureCode.staleState);
      return;
    }
    late final OutboundCompletionCommand command;
    try {
      command = OutboundCompletionCommand(
        taskId: taskId,
        requestId: ref.read(outboundCompletionRequestIdProvider)(),
        receivedAllItems: true,
        reportedCollectedAmountVnd: amount,
      );
      if (!command.isValid) throw const FormatException();
    } catch (_) {
      _validation(OutboundCommandFailureCode.invalidData);
      return;
    }
    _retainPendingOperation();
    await _execute(command, session, _sessionRevision);
  }

  Future<void> retry() async {
    final session = _session;
    if (_disposed ||
        !_visible ||
        session == null ||
        !_usable(session) ||
        state.busy) {
      return;
    }
    final revision = _sessionRevision;
    final pending = state.pendingCommand;
    if (pending != null) {
      await _execute(pending, session, revision);
      return;
    }
    await _read(session, revision, preserveError: state.error);
    if (_awaitingRead && _visible) return;
    await _refreshCaches(session, revision);
  }

  Future<void> _execute(
    OutboundCompletionCommand command,
    OperationalSession session,
    int revision,
  ) async {
    if (!_epochCurrent(session, revision)) return;
    if (!ref.read(outboundResultGateProvider(taskId).notifier).acquire(this)) {
      return;
    }
    state = state.copyWith(
      busy: true,
      error: null,
      pendingCommand: command,
      requiresReadRetry: false,
    );
    try {
      await ref.read(outboundCompletionRepositoryProvider).execute(command);
    } catch (error) {
      if (!_epochCurrent(session, revision)) return;
      final failure = _map(error);
      final uncertain =
          failure is OutboundAcknowledgementFailure ||
          failure.code == OutboundCommandFailureCode.timeout ||
          failure.code == OutboundCommandFailureCode.network ||
          failure.code == OutboundCommandFailureCode.dependencyUnavailable ||
          failure.code == OutboundCommandFailureCode.unexpected;
      if (failure.code == OutboundCommandFailureCode.sessionExpired ||
          failure.code == OutboundCommandFailureCode.permissionDenied ||
          failure.code == OutboundCommandFailureCode.staleAssignment) {
        _setDenied(failure);
        return;
      }
      state = state.copyWith(
        busy: false,
        error: failure,
        pendingCommand: uncertain ? command : null,
        requiresReadRetry: !uncertain,
      );
      if (uncertain) return;
      _taskRefreshNeeded = true;
      _codRefreshNeeded = true;
      final readOk = await _read(session, revision, preserveError: failure);
      if (readOk && _epochCurrent(session, revision)) {
        await _refreshCaches(session, revision, preserveError: failure);
      }
      return;
    }
    if (!_epochCurrent(session, revision)) return;
    _awaitingRead = true;
    state = state.copyWith(
      busy: _visible,
      pendingCommand: null,
      awaitingAuthoritativeRead: true,
      confirmed: false,
      requiresReadRetry: !_visible,
    );
    _retainPendingOperation();
    if (!_visible) return;
    await _read(session, revision);
    if (_epochCurrent(session, revision) && !_awaitingRead) {
      await _refreshCaches(session, revision);
    }
  }

  Future<bool> _read(
    OperationalSession session,
    int revision, {
    OutboundCommandFailure? preserveError,
  }) async {
    if (!_current(session, revision) || !_visible) return false;
    final generation = ++_generation;
    state = state.copyWith(details: const AsyncLoading(), error: preserveError);
    try {
      final details = await ref.read(outboundCompletionDetailsReloadProvider)(
        taskId,
      );
      if (!_current(session, revision) || generation != _generation) {
        return false;
      }
      if (details.task.taskId != taskId) throw const FormatException();
      if (_awaitingRead) {
        final task = details.task;
        if (task.kind != DeliveryTaskKind.outbound ||
            task.status != DeliveryTaskStatus.delivered ||
            (task.scope != DeliverySnapshotScope.history &&
                task.scope != DeliverySnapshotScope.current)) {
          throw const OutboundCommandFailure(
            OutboundCommandFailureCode.staleState,
          );
        }
        _awaitingRead = false;
        _taskRefreshNeeded = true;
        _codRefreshNeeded = true;
        state = state.copyWith(
          details: AsyncData(details),
          busy: false,
          error: preserveError,
          awaitingAuthoritativeRead: false,
          confirmed: true,
          requiresReadRetry: false,
        );
        return true;
      }
      state = state.copyWith(
        details: AsyncData(details),
        busy: false,
        error: preserveError,
        requiresReadRetry: false,
      );
      _releasePendingOperationIfIdle();
      return true;
    } catch (error) {
      if (!_current(session, revision)) return false;
      final failure = _map(error);
      state = state.copyWith(
        details: AsyncError(failure, StackTrace.current),
        busy: false,
        error: preserveError ?? failure,
        requiresReadRetry: true,
        awaitingAuthoritativeRead: _awaitingRead,
      );
      return false;
    }
  }

  Future<void> _refreshCaches(
    OperationalSession session,
    int revision, {
    OutboundCommandFailure? preserveError,
  }) async {
    if (!_epochCurrent(session, revision)) return;
    if (!_visible) {
      state = state.copyWith(busy: false, requiresReadRetry: true);
      _retainPendingOperation();
      return;
    }
    state = state.copyWith(busy: true);
    OutboundCommandFailure? first;
    if (_taskRefreshNeeded) {
      try {
        await ref.read(outboundCompletionTaskListReloadProvider)();
        if (!_epochCurrent(session, revision)) return;
        _taskRefreshNeeded = false;
      } catch (error) {
        if (!_epochCurrent(session, revision)) return;
        first = _map(error);
      }
    }
    if (_codRefreshNeeded) {
      try {
        await ref.read(outboundCompletionCodReloadProvider)();
        if (!_epochCurrent(session, revision)) return;
        _codRefreshNeeded = false;
      } catch (error) {
        if (!_epochCurrent(session, revision)) return;
        first ??= _map(error);
      }
    }
    if (!_epochCurrent(session, revision)) return;
    if (!_visible) {
      state = state.copyWith(busy: false, requiresReadRetry: true);
      _retainPendingOperation();
      return;
    }
    state = state.copyWith(
      busy: false,
      error: first ?? preserveError,
      requiresReadRetry:
          first != null || _taskRefreshNeeded || _codRefreshNeeded,
    );
    _releasePendingOperationIfIdle();
  }

  void _validation(OutboundCommandFailureCode code) {
    if (!_disposed) {
      state = state.copyWith(busy: false, error: OutboundCommandFailure(code));
    }
  }

  void _setDenied(OutboundCommandFailure failure) {
    if (_disposed) return;
    ref.read(outboundResultGateProvider(taskId).notifier).release(this);
    state = state.copyWith(
      busy: false,
      error: failure,
      details: AsyncError(failure, StackTrace.empty),
      pendingCommand: null,
      actionsDenied: true,
      awaitingAuthoritativeRead: false,
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
        _taskRefreshNeeded ||
        _codRefreshNeeded) {
      return;
    }
    ref.read(outboundResultGateProvider(taskId).notifier).release(this);
    _closeKeepAlive?.call();
    _closeKeepAlive = null;
  }

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
