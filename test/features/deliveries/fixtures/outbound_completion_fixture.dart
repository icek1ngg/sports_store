import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_completion_command.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';
import 'package:sports_store/features/deliveries/domain/repositories/outbound_completion_repository.dart';

import 'outbound_action_fixture.dart';

// Re-export the existing test-only session seam so completion tests do not
// need to depend on P04.2's fixture path directly.
export 'outbound_action_fixture.dart' show FixtureOutboundSession;

/// Dependencies for the P05.2 fixture. This type deliberately lives under
/// `test/`: it is a seam for provider/widget tests, not a runtime service
/// locator or a substitute Supabase implementation.
class FixtureOutboundCompletionDependencies {
  const FixtureOutboundCompletionDependencies({
    required this.initialSession,
    required this.readTask,
    required this.commandRepository,
    required this.createRequestId,
    this.refreshTaskList,
    this.refreshCod,
  });

  final FixtureOutboundSession initialSession;
  final Future<DeliveryTaskDetails> Function(String taskId) readTask;
  final OutboundCompletionRepository commandRepository;
  final String Function() createRequestId;
  final Future<void> Function()? refreshTaskList;
  final Future<void> Function()? refreshCod;
}

final fixtureOutboundCompletionDependenciesProvider =
    Provider<FixtureOutboundCompletionDependencies>((ref) {
      throw StateError(
        'Override fixtureOutboundCompletionDependenciesProvider in tests',
      );
    });

/// Test-only state for successful-outbound completion.
///
/// [confirmed] is set only after an ACK followed by a read containing the
/// authoritative `delivered` status. An ACK alone never changes the visible
/// task state.
class FixtureOutboundCompletionState {
  const FixtureOutboundCompletionState({
    required this.details,
    required this.session,
    this.busy = false,
    this.error,
    this.pendingCommand,
    this.requiresReadRetry = false,
    this.actionsDenied = false,
    this.awaitingAuthoritativeRead = false,
    this.confirmed = false,
  });

  const FixtureOutboundCompletionState.initial(FixtureOutboundSession session)
    : this(details: const AsyncLoading(), session: session);

  final AsyncValue<DeliveryTaskDetails> details;
  final FixtureOutboundSession session;
  final bool busy;
  final OutboundCommandFailure? error;
  final OutboundCompletionCommand? pendingCommand;
  final bool requiresReadRetry;
  final bool actionsDenied;
  final bool awaitingAuthoritativeRead;
  final bool confirmed;

  /// Backend-provided amount only. The UI must not add the delivery fee or
  /// derive this amount from item lines.
  int? get authoritativeAmountVnd =>
      details.hasValue ? details.requireValue.task.amountToCollectVnd : null;

  bool get completionConfirmed => confirmed;

  bool get canComplete {
    if (!session.active ||
        busy ||
        actionsDenied ||
        requiresReadRetry ||
        awaitingAuthoritativeRead ||
        confirmed ||
        pendingCommand != null ||
        details.isLoading ||
        !details.hasValue) {
      return false;
    }
    final task = details.requireValue.task;
    final amount = task.amountToCollectVnd;
    return task.taskId.isNotEmpty &&
        task.kind == DeliveryTaskKind.outbound &&
        task.scope == DeliverySnapshotScope.current &&
        task.status == DeliveryTaskStatus.inTransit &&
        amount != null &&
        amount > 0;
  }

  FixtureOutboundCompletionState copyWith({
    AsyncValue<DeliveryTaskDetails>? details,
    FixtureOutboundSession? session,
    bool? busy,
    Object? error = _unset,
    Object? pendingCommand = _unset,
    bool? requiresReadRetry,
    bool? actionsDenied,
    bool? awaitingAuthoritativeRead,
    bool? confirmed,
  }) {
    return FixtureOutboundCompletionState(
      details: details ?? this.details,
      session: session ?? this.session,
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
}

const _unset = Object();

final fixtureOutboundCompletionViewModelProvider = NotifierProvider.autoDispose
    .family<
      FixtureOutboundCompletionViewModel,
      FixtureOutboundCompletionState,
      String
    >(FixtureOutboundCompletionViewModel.new);

/// Test-only ViewModel for P05.2 confirmation semantics. It deliberately has
/// no Supabase dependency and must never be imported by runtime UI.
class FixtureOutboundCompletionViewModel
    extends Notifier<FixtureOutboundCompletionState> {
  FixtureOutboundCompletionViewModel(this.taskId);

  final String taskId;
  late FixtureOutboundCompletionDependencies _dependencies;
  late FixtureOutboundSession _session;
  bool _disposed = false;
  bool _expired = false;
  int _sessionRevision = 0;
  int _readGeneration = 0;
  bool _awaitingAuthoritativeRead = false;
  bool _taskListRefreshNeeded = false;
  bool _codRefreshNeeded = false;

  /// A test-only epoch for confirmation bridges that open a dialog and must
  /// reject an account switch before submitting the dialog's stale payload.
  int get sessionRevisionForFixture => _sessionRevision;

  @override
  FixtureOutboundCompletionState build() {
    _disposed = false;
    _expired = false;
    _sessionRevision++;
    _readGeneration++;
    _awaitingAuthoritativeRead = false;
    _taskListRefreshNeeded = false;
    _codRefreshNeeded = false;
    _dependencies = ref.watch(fixtureOutboundCompletionDependenciesProvider);
    final session = _session = _dependencies.initialSession;
    final revision = _sessionRevision;
    ref.onDispose(() {
      _disposed = true;
      _sessionRevision++;
      _readGeneration++;
    });
    scheduleMicrotask(() {
      if (_isCurrent(session, revision)) unawaited(_read(session, revision));
    });
    return _initialState(session);
  }

  FixtureOutboundCompletionState _initialState(FixtureOutboundSession session) {
    if (session.active) return FixtureOutboundCompletionState.initial(session);
    final failure = OutboundCommandFailure(
      session.userId == null
          ? OutboundCommandFailureCode.sessionExpired
          : OutboundCommandFailureCode.permissionDenied,
    );
    return FixtureOutboundCompletionState(
      details: AsyncError(failure, StackTrace.empty),
      session: session,
      error: failure,
      actionsDenied: true,
    );
  }

  /// Test seam for account switching. It clears old details and invalidates
  /// every in-flight read/callback before loading the new account.
  void updateSession(FixtureOutboundSession next) {
    if (_disposed || identical(_session, next)) return;
    _sessionRevision++;
    _readGeneration++;
    _expired = false;
    _awaitingAuthoritativeRead = false;
    _taskListRefreshNeeded = false;
    _codRefreshNeeded = false;
    _session = next;
    state = _initialState(next);
    if (next.active) {
      final revision = _sessionRevision;
      unawaited(_read(next, revision));
    }
  }

  /// Manual refresh never submits an uncertain command. It may refresh the
  /// detail and, after an already acknowledged completion, retry only failed
  /// cache invalidations.
  Future<void> refresh() async {
    if (_disposed || state.busy || !_session.active || _expired) return;
    final session = _session;
    final revision = _sessionRevision;
    state = state.copyWith(busy: true);
    await _reload(session, revision, preserveError: state.error);
  }

  /// Submit confirmation after both UI confirmations have been accepted. The
  /// [receivedFullCod] boolean is a guard only; it is intentionally not
  /// included in the command sent to the future RPC.
  Future<void> submit({
    required bool receivedAllItems,
    required bool receivedFullCod,
    required int displayedAmountVnd,
  }) async {
    if (_disposed || state.busy || state.actionsDenied || _expired) return;
    final session = _session;
    final revision = _sessionRevision;
    if (!session.active) {
      state = _initialState(session);
      return;
    }
    if (state.pendingCommand != null ||
        state.awaitingAuthoritativeRead ||
        state.confirmed ||
        state.requiresReadRetry) {
      _setValidationError(OutboundCommandFailureCode.staleState);
      return;
    }

    final details = state.details;
    if (!details.hasValue || details.isLoading) {
      _setValidationError(OutboundCommandFailureCode.staleState);
      return;
    }
    final task = details.requireValue.task;
    if (task.taskId != taskId ||
        task.kind != DeliveryTaskKind.outbound ||
        task.scope != DeliverySnapshotScope.current ||
        task.status != DeliveryTaskStatus.inTransit) {
      _setValidationError(OutboundCommandFailureCode.staleState);
      return;
    }
    final authoritativeAmount = task.amountToCollectVnd;
    if (authoritativeAmount == null || authoritativeAmount <= 0) {
      _setValidationError(OutboundCommandFailureCode.invalidData);
      return;
    }
    if (!receivedAllItems || !receivedFullCod) {
      _setValidationError(OutboundCommandFailureCode.invalidData);
      return;
    }
    if (displayedAmountVnd != authoritativeAmount ||
        displayedAmountVnd <= 0 ||
        displayedAmountVnd > 9007199254740991) {
      _setValidationError(OutboundCommandFailureCode.invalidData);
      return;
    }
    await _createAndExecute(
      session,
      revision,
      receivedAllItems: receivedAllItems,
      amountVnd: authoritativeAmount,
    );
  }

  Future<void> _createAndExecute(
    FixtureOutboundSession session,
    int revision, {
    required bool receivedAllItems,
    required int amountVnd,
  }) async {
    late final OutboundCompletionCommand command;
    try {
      command = OutboundCompletionCommand(
        taskId: taskId,
        requestId: _dependencies.createRequestId(),
        receivedAllItems: receivedAllItems,
        reportedCollectedAmountVnd: amountVnd,
      );
      if (!command.isValid) throw const FormatException('Invalid command');
    } catch (_) {
      _setValidationError(OutboundCommandFailureCode.invalidData);
      return;
    }
    await _execute(command, session, revision);
  }

  /// Retries the exact pending command after timeout/network uncertainty. It
  /// bypasses a fresh detail-state check, but never bypasses current-session
  /// validation.
  Future<void> retry() async {
    if (_disposed || state.busy || !_session.active || _expired) return;
    final pending = state.pendingCommand;
    if (pending != null) {
      final session = _session;
      final revision = _sessionRevision;
      await _execute(pending, session, revision);
      return;
    }
    final session = _session;
    final revision = _sessionRevision;
    state = state.copyWith(busy: true);
    await _reload(session, revision, preserveError: state.error);
  }

  Future<void> _execute(
    OutboundCompletionCommand command,
    FixtureOutboundSession session,
    int revision,
  ) async {
    if (!_isCurrent(session, revision) || !session.active || _expired) return;
    state = state.copyWith(
      busy: true,
      error: null,
      pendingCommand: command,
      requiresReadRetry: false,
    );
    try {
      await _dependencies.commandRepository.execute(command);
    } catch (error) {
      if (!_isCurrent(session, revision)) return;
      final failure = _mapFailure(error);
      final uncertain =
          failure.code == OutboundCommandFailureCode.timeout ||
          failure.code == OutboundCommandFailureCode.network;
      final terminal = _terminal(failure);
      state = state.copyWith(
        error: failure,
        pendingCommand: uncertain ? command : null,
        actionsDenied: terminal || state.actionsDenied,
      );
      if (failure.code == OutboundCommandFailureCode.sessionExpired) {
        _expired = true;
      }
      if (_expired) {
        state = state.copyWith(
          busy: false,
          details: AsyncError(failure, StackTrace.empty),
          actionsDenied: true,
        );
        return;
      }
      await _reload(session, revision, preserveError: failure);
      return;
    }
    if (!_isCurrent(session, revision)) return;

    // A write ACK is not a task snapshot. Keep the UI busy until a read
    // proves that the server state is delivered.
    _awaitingAuthoritativeRead = true;
    state = state.copyWith(
      busy: true,
      pendingCommand: null,
      error: null,
      awaitingAuthoritativeRead: true,
      confirmed: false,
    );
    await _reload(session, revision);
  }

  Future<void> _reload(
    FixtureOutboundSession session,
    int revision, {
    OutboundCommandFailure? preserveError,
  }) async {
    final readOk = await _read(session, revision, preserveError: preserveError);
    if (!_isCurrent(session, revision)) return;
    if (_expired || (state.actionsDenied && !state.confirmed)) {
      state = state.copyWith(busy: false);
      return;
    }
    if (!readOk) {
      state = state.copyWith(busy: false, requiresReadRetry: true);
      return;
    }
    if (_awaitingAuthoritativeRead) {
      state = state.copyWith(busy: false, requiresReadRetry: true);
      return;
    }
    if (state.confirmed) {
      await _refreshCaches(session, revision);
      if (!_isCurrent(session, revision)) return;
    }
    state = state.copyWith(
      busy: false,
      requiresReadRetry:
          state.requiresReadRetry ||
          _taskListRefreshNeeded ||
          _codRefreshNeeded,
    );
  }

  Future<bool> _read(
    FixtureOutboundSession session,
    int revision, {
    OutboundCommandFailure? preserveError,
  }) async {
    if (!_isCurrent(session, revision) || !session.active || _expired) {
      return false;
    }
    final generation = ++_readGeneration;
    state = state.copyWith(
      details: const AsyncLoading(),
      error: preserveError,
      requiresReadRetry: false,
    );
    try {
      final details = await _dependencies.readTask(taskId);
      if (!_isCurrent(session, revision) || generation != _readGeneration) {
        return false;
      }
      if (details.task.taskId != taskId) {
        throw const OutboundCommandFailure(
          OutboundCommandFailureCode.invalidData,
        );
      }
      if (_awaitingAuthoritativeRead) {
        // A successful outbound completion is allowed to become a masked
        // historical snapshot. The delivered status and history scope, not a
        // client-supplied amount, are the authoritative proof of completion.
        if (details.task.kind != DeliveryTaskKind.outbound ||
            details.task.status != DeliveryTaskStatus.delivered ||
            details.task.scope != DeliverySnapshotScope.history) {
          state = state.copyWith(
            details: AsyncData(details),
            error: const OutboundCommandFailure(
              OutboundCommandFailureCode.staleState,
            ),
            requiresReadRetry: true,
          );
          return false;
        }
        _awaitingAuthoritativeRead = false;
        _taskListRefreshNeeded = true;
        _codRefreshNeeded = true;
        state = state.copyWith(
          details: AsyncData(details),
          error: preserveError,
          awaitingAuthoritativeRead: false,
          confirmed: true,
          requiresReadRetry: false,
        );
        return true;
      }
      if (state.confirmed &&
          (details.task.kind != DeliveryTaskKind.outbound ||
              details.task.status != DeliveryTaskStatus.delivered ||
              details.task.scope != DeliverySnapshotScope.history)) {
        // Never surface a regressed/current snapshot after confirmation. The
        // old masked details are cleared so a transient backend regression
        // cannot reveal stale recipient PII or re-enable completion.
        state = state.copyWith(
          details: const AsyncError(
            OutboundCommandFailure(OutboundCommandFailureCode.staleState),
            StackTrace.empty,
          ),
          error: const OutboundCommandFailure(
            OutboundCommandFailureCode.staleState,
          ),
          requiresReadRetry: true,
          confirmed: false,
        );
        return false;
      }
      state = state.copyWith(details: AsyncData(details), error: preserveError);
      return true;
    } catch (error) {
      if (!_isCurrent(session, revision) || generation != _readGeneration) {
        return false;
      }
      final failure = _mapFailure(error);
      final terminal = _terminal(failure);
      if (failure.code == OutboundCommandFailureCode.sessionExpired) {
        _expired = true;
      }
      state = state.copyWith(
        details: AsyncError(failure, StackTrace.empty),
        error: terminal ? failure : preserveError ?? failure,
        requiresReadRetry: true,
        actionsDenied: state.actionsDenied || terminal,
        pendingCommand: terminal ? null : state.pendingCommand,
        confirmed: _expired ? false : state.confirmed,
      );
      return false;
    }
  }

  Future<void> _refreshCaches(
    FixtureOutboundSession session,
    int revision,
  ) async {
    OutboundCommandFailure? firstFailure;
    OutboundCommandFailure? terminalFailure;

    void recordFailure(Object error) {
      final failure = _mapFailure(error);
      if (_terminal(failure)) {
        terminalFailure = failure;
      } else {
        firstFailure ??= failure;
      }
    }

    if (_taskListRefreshNeeded) {
      try {
        final refresh = _dependencies.refreshTaskList;
        if (refresh == null) {
          throw const OutboundCommandFailure(
            OutboundCommandFailureCode.dependencyUnavailable,
          );
        }
        await refresh();
        if (!_isCurrent(session, revision)) return;
        _taskListRefreshNeeded = false;
      } catch (error) {
        if (!_isCurrent(session, revision)) return;
        recordFailure(error);
      }
    }
    // A session-expiry failure invalidates the account and must stop the
    // remaining callback. Other terminal-looking cache failures (permission,
    // stale assignment, dependency unavailable) remain retry-only and must
    // not suppress the independent COD invalidation.
    if (terminalFailure?.code != OutboundCommandFailureCode.sessionExpired &&
        _codRefreshNeeded) {
      try {
        final refresh = _dependencies.refreshCod;
        if (refresh == null) {
          throw const OutboundCommandFailure(
            OutboundCommandFailureCode.dependencyUnavailable,
          );
        }
        await refresh();
        if (!_isCurrent(session, revision)) return;
        _codRefreshNeeded = false;
      } catch (error) {
        if (!_isCurrent(session, revision)) return;
        recordFailure(error);
      }
    }
    if (!_isCurrent(session, revision)) return;
    final failure = terminalFailure ?? firstFailure;
    if (failure != null) {
      if (failure.code == OutboundCommandFailureCode.sessionExpired) {
        _expired = true;
      }
      state = state.copyWith(
        error: failure,
        requiresReadRetry: true,
        actionsDenied:
            state.actionsDenied ||
            failure.code == OutboundCommandFailureCode.sessionExpired,
        confirmed: _expired ? false : state.confirmed,
        details: _expired
            ? AsyncError(failure, StackTrace.empty)
            : state.details,
      );
    } else {
      state = state.copyWith(error: null, requiresReadRetry: false);
    }
  }

  void _setValidationError(OutboundCommandFailureCode code) {
    if (_disposed) return;
    state = state.copyWith(
      busy: false,
      error: OutboundCommandFailure(code),
      requiresReadRetry: code == OutboundCommandFailureCode.staleState,
    );
  }

  bool _isCurrent(FixtureOutboundSession session, int revision) =>
      !_disposed &&
      ref.mounted &&
      identical(_session, session) &&
      _sessionRevision == revision;

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
    return const OutboundCommandFailure(OutboundCommandFailureCode.unexpected);
  }

  static bool _terminal(OutboundCommandFailure failure) =>
      switch (failure.code) {
        OutboundCommandFailureCode.sessionExpired ||
        OutboundCommandFailureCode.permissionDenied ||
        OutboundCommandFailureCode.staleAssignment ||
        OutboundCommandFailureCode.dependencyUnavailable => true,
        _ => false,
      };
}
