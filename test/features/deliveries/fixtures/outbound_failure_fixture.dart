// P07.3 TEST-ONLY failure-reporting harness. Runtime code must not import it.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_failure_command.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';
import 'package:sports_store/features/deliveries/domain/repositories/outbound_failure_repository.dart';

import 'outbound_action_fixture.dart';

export 'outbound_action_fixture.dart' show FixtureOutboundSession;

/// Dependencies for the P07.3 failure fixture.
///
/// [assignedActorId] is fixture metadata only. The production task projection
/// intentionally does not expose a client-controlled shipper ID; this seam
/// uses the metadata to exercise owner/session invalidation without pretending
/// to prove custody or authorization. If omitted, the initial session user is
/// used as the fixture owner.
class FixtureOutboundFailureDependencies {
  const FixtureOutboundFailureDependencies({
    required this.initialSession,
    required this.readTask,
    required this.failureRepository,
    required this.createRequestId,
    this.assignedActorId,
    this.refreshTaskList,
  });

  final FixtureOutboundSession initialSession;
  final Future<DeliveryTaskDetails> Function(String taskId) readTask;
  final OutboundFailureRepository failureRepository;
  final String Function() createRequestId;

  /// Fixture-only owner metadata; never copied into a command.
  final String? assignedActorId;

  /// Callback used to reload the MH10 task list after an authoritative read.
  final Future<void> Function()? refreshTaskList;

  String? get effectiveAssignedActorId =>
      assignedActorId ?? initialSession.userId;

  Future<void> Function()? get mh10Reload => refreshTaskList;
}

final fixtureOutboundFailureDependenciesProvider =
    Provider<FixtureOutboundFailureDependencies>((ref) {
      throw StateError(
        'Override fixtureOutboundFailureDependenciesProvider in tests',
      );
    });

/// A deterministic repository script for widget/provider tests.
///
/// The default script only returns a matching acknowledgement; tests can set
/// [handler] to delay, throw a typed failure, or return a deliberately wrong
/// acknowledgement. Every call is retained so duplicate writes and idempotent
/// retries are observable.
class ScriptedOutboundFailureRepository implements OutboundFailureRepository {
  final commands = <OutboundFailureCommand>[];

  FutureOr<OutboundFailureAck> Function(OutboundFailureCommand command)?
  handler;

  List<OutboundFailureCommand> get calls => commands;

  @override
  Future<OutboundFailureAck> execute(OutboundFailureCommand command) async {
    commands.add(command);
    final script = handler;
    if (script != null) return await script(command);
    return OutboundFailureAck(
      taskId: command.taskId,
      requestId: command.requestId,
      attemptNumber: command.attemptNumber,
      disposition: OutboundFailureDisposition.forAttempt(command.attemptNumber),
    );
  }
}

typedef FixtureOutboundFailureRepository = ScriptedOutboundFailureRepository;

/// Provider state for the test-only P07.3 failure flow.
class FixtureOutboundFailureState {
  const FixtureOutboundFailureState({
    required this.details,
    required this.session,
    this.assignedActorId,
    this.busy = false,
    this.error,
    this.pendingCommand,
    this.acknowledgement,
    this.requiresReadRetry = false,
    this.actionsDenied = false,
    this.awaitingAuthoritativeRead = false,
    this.reported = false,
  });

  const FixtureOutboundFailureState.initial(
    FixtureOutboundSession session, {
    String? assignedActorId,
  }) : this(
         details: const AsyncLoading(),
         session: session,
         assignedActorId: assignedActorId,
       );

  final AsyncValue<DeliveryTaskDetails> details;
  final FixtureOutboundSession session;
  final String? assignedActorId;
  final bool busy;
  final OutboundCommandFailure? error;
  final OutboundFailureCommand? pendingCommand;
  final OutboundFailureAck? acknowledgement;
  final bool requiresReadRetry;
  final bool actionsDenied;
  final bool awaitingAuthoritativeRead;
  final bool reported;

  bool get failureReported => reported;

  OutboundFailureDisposition? get disposition => acknowledgement?.disposition;

  /// Presentation guard only. It does not prove custody, RLS authorization or
  /// the server's transition transaction.
  bool get eligible =>
      _isLiveFailureTask(details.hasValue ? details.requireValue.task : null) &&
      session.active &&
      assignedActorId != null &&
      assignedActorId == session.userId &&
      !busy &&
      !actionsDenied &&
      !requiresReadRetry &&
      !awaitingAuthoritativeRead &&
      !reported &&
      pendingCommand == null;

  bool get canReport => eligible;
  bool get canFail => eligible;

  FixtureOutboundFailureState copyWith({
    AsyncValue<DeliveryTaskDetails>? details,
    FixtureOutboundSession? session,
    String? assignedActorId,
    bool? busy,
    Object? error = _unset,
    Object? pendingCommand = _unset,
    Object? acknowledgement = _unset,
    bool? requiresReadRetry,
    bool? actionsDenied,
    bool? awaitingAuthoritativeRead,
    bool? reported,
  }) {
    return FixtureOutboundFailureState(
      details: details ?? this.details,
      session: session ?? this.session,
      assignedActorId: assignedActorId ?? this.assignedActorId,
      busy: busy ?? this.busy,
      error: identical(error, _unset)
          ? this.error
          : error as OutboundCommandFailure?,
      pendingCommand: identical(pendingCommand, _unset)
          ? this.pendingCommand
          : pendingCommand as OutboundFailureCommand?,
      acknowledgement: identical(acknowledgement, _unset)
          ? this.acknowledgement
          : acknowledgement as OutboundFailureAck?,
      requiresReadRetry: requiresReadRetry ?? this.requiresReadRetry,
      actionsDenied: actionsDenied ?? this.actionsDenied,
      awaitingAuthoritativeRead:
          awaitingAuthoritativeRead ?? this.awaitingAuthoritativeRead,
      reported: reported ?? this.reported,
    );
  }
}

const _unset = Object();

bool _isLiveFailureTask(DeliveryTaskSnapshot? task) {
  if (task == null ||
      task.taskId.isEmpty ||
      task.kind != DeliveryTaskKind.outbound ||
      task.scope != DeliverySnapshotScope.current ||
      task.status != DeliveryTaskStatus.inTransit ||
      (task.attemptNumber != 1 && task.attemptNumber != 2) ||
      task.assignedAt == null ||
      task.acceptedAt == null ||
      task.startedAt == null) {
    return false;
  }
  return true;
}

final fixtureOutboundFailureViewModelProvider = NotifierProvider.autoDispose
    .family<
      FixtureOutboundFailureViewModel,
      FixtureOutboundFailureState,
      String
    >(FixtureOutboundFailureViewModel.new);

/// Test-only ViewModel for P07.3 failure semantics.
///
/// This intentionally mirrors the existing completion fixture pattern:
/// command ACKs are never task state, uncertain writes retain one immutable
/// command, and only an authoritative restricted/failed detail read can
/// complete the flow.
class FixtureOutboundFailureViewModel
    extends Notifier<FixtureOutboundFailureState> {
  FixtureOutboundFailureViewModel(this.taskId);

  final String taskId;
  late FixtureOutboundFailureDependencies _dependencies;
  late FixtureOutboundSession _session;
  late String? _assignedActorId;

  bool _disposed = false;
  bool _expired = false;
  int _sessionRevision = 0;
  int _readGeneration = 0;
  bool _awaitingAuthoritativeRead = false;
  bool _taskListRefreshNeeded = false;
  OutboundFailureCommand? _acknowledgedCommand;

  /// A test-only epoch for a confirmation dialog/widget bridge.
  int get sessionRevisionForFixture => _sessionRevision;

  @override
  FixtureOutboundFailureState build() {
    _disposed = false;
    _expired = false;
    _sessionRevision++;
    _readGeneration++;
    _awaitingAuthoritativeRead = false;
    _taskListRefreshNeeded = false;
    _acknowledgedCommand = null;
    _dependencies = ref.watch(fixtureOutboundFailureDependenciesProvider);
    final session = _session = _dependencies.initialSession;
    _assignedActorId = _dependencies.effectiveAssignedActorId;
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

  FixtureOutboundFailureState _initialState(FixtureOutboundSession session) {
    if (session.active) {
      return FixtureOutboundFailureState.initial(
        session,
        assignedActorId: _assignedActorId,
      );
    }
    final failure = OutboundCommandFailure(
      session.userId == null
          ? OutboundCommandFailureCode.sessionExpired
          : OutboundCommandFailureCode.permissionDenied,
    );
    return FixtureOutboundFailureState(
      details: AsyncError(failure, StackTrace.empty),
      session: session,
      assignedActorId: _assignedActorId,
      error: failure,
      actionsDenied: true,
    );
  }

  /// Clears old details and invalidates every callback from the old account or
  /// access epoch before reading the new session.
  void updateSession(FixtureOutboundSession next) {
    if (_disposed || identical(_session, next)) return;
    _sessionRevision++;
    _readGeneration++;
    _expired = false;
    _awaitingAuthoritativeRead = false;
    _taskListRefreshNeeded = false;
    _acknowledgedCommand = null;
    _session = next;
    state = _initialState(next);
    if (next.active) {
      if (_assignedActorId != null && _assignedActorId != next.userId) {
        _clearForAuth(
          const OutboundCommandFailure(
            OutboundCommandFailureCode.staleAssignment,
          ),
        );
        return;
      }
      final revision = _sessionRevision;
      unawaited(_read(next, revision));
    }
  }

  /// Read-only refresh. An uncertain command/ACK is never replaced or
  /// resubmitted by this method.
  Future<void> refresh() async {
    if (_disposed || state.busy || !_session.active || _expired) return;
    final session = _session;
    final revision = _sessionRevision;
    state = state.copyWith(busy: true);
    await _reload(session, revision, preserveError: state.error);
  }

  /// Confirm the failure draft. The request ID is generated once, before the
  /// first write, and all timeout/network retries reuse the exact command.
  Future<void> submit({
    required OutboundFailureReason reason,
    String? description,
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
        state.reported ||
        state.requiresReadRetry) {
      _setValidationError(OutboundCommandFailureCode.staleState);
      return;
    }

    if (!state.details.hasValue ||
        state.details.isLoading ||
        !_isEligibleTask(state.details.requireValue.task)) {
      _setValidationError(OutboundCommandFailureCode.staleState);
      return;
    }

    final trimmed = description?.trim();
    final normalizedDescription = trimmed == null || trimmed.isEmpty
        ? null
        : trimmed;
    late final OutboundFailureCommand command;
    try {
      command = OutboundFailureCommand(
        taskId: taskId,
        requestId: _dependencies.createRequestId(),
        attemptNumber: state.details.requireValue.task.attemptNumber,
        reason: reason,
        description: normalizedDescription,
      );
      if (!command.isValid) throw const FormatException('Invalid command');
    } catch (_) {
      _setValidationError(OutboundCommandFailureCode.invalidData);
      return;
    }
    await _execute(command, session, revision);
  }

  /// Alias used by MH11 test panels.
  Future<void> reportFailure(
    OutboundFailureReason reason, {
    String? description,
  }) => submit(reason: reason, description: description);

  /// Alias used by confirmation dialog tests.
  Future<void> confirm(OutboundFailureReason reason, {String? description}) =>
      submit(reason: reason, description: description);

  /// Retry a pending write, an ACK detail read, or an MH10 reload. At no point
  /// does this method create a new request ID or send a changed draft.
  Future<void> retry() async {
    if (_disposed || state.busy || !_session.active || _expired) return;
    final session = _session;
    final revision = _sessionRevision;
    final pending = state.pendingCommand;
    if (pending != null) {
      await _execute(pending, session, revision);
      return;
    }
    if (_taskListRefreshNeeded &&
        state.reported &&
        !_awaitingAuthoritativeRead) {
      state = state.copyWith(busy: true);
      await _refreshTaskList(session, revision);
      if (_isCurrent(session, revision)) {
        state = state.copyWith(busy: false);
      }
      return;
    }
    state = state.copyWith(busy: true);
    await _reload(session, revision, preserveError: state.error);
  }

  Future<void> _execute(
    OutboundFailureCommand command,
    FixtureOutboundSession session,
    int revision,
  ) async {
    if (!_isCurrent(session, revision) || !session.active || _expired) return;
    state = state.copyWith(
      busy: true,
      error: null,
      pendingCommand: command,
      acknowledgement: null,
      requiresReadRetry: false,
      awaitingAuthoritativeRead: false,
      reported: false,
    );
    try {
      final acknowledgement = await _dependencies.failureRepository.execute(
        command,
      );
      if (!acknowledgement.isValid || !acknowledgement.matches(command)) {
        // A malformed/mismatched acknowledgement may mean the server
        // committed but the response could not be correlated. Retain the
        // exact command/key and require reconciliation with that same key;
        // never release it for a fresh local request.
        if (_isCurrent(session, revision)) {
          state = state.copyWith(
            busy: false,
            error: const OutboundCommandFailure(
              OutboundCommandFailureCode.invalidData,
            ),
            pendingCommand: command,
            requiresReadRetry: true,
          );
        }
        return;
      }
      if (!_isCurrent(session, revision)) return;
      _acknowledgedCommand = command;
      _awaitingAuthoritativeRead = true;
      _taskListRefreshNeeded = true;
      state = state.copyWith(
        busy: true,
        error: null,
        pendingCommand: null,
        acknowledgement: acknowledgement,
        requiresReadRetry: false,
        awaitingAuthoritativeRead: true,
        reported: false,
      );
      await _reload(session, revision);
    } catch (error) {
      if (!_isCurrent(session, revision)) return;
      final failure = _mapFailure(error);
      if (_isAuthInvalidation(failure)) {
        _clearForAuth(failure);
        return;
      }
      final uncertain = _isUncertain(failure);
      state = state.copyWith(
        busy: false,
        error: failure,
        pendingCommand: uncertain ? command : null,
        requiresReadRetry: false,
      );
      // A definite server rejection is followed by a fresh authoritative
      // read; an uncertain write is frozen until the user explicitly retries
      // the same command/key.
      if (!uncertain) {
        await _reload(session, revision, preserveError: failure);
      }
    }
  }

  Future<void> _reload(
    FixtureOutboundSession session,
    int revision, {
    OutboundCommandFailure? preserveError,
  }) async {
    final readOk = await _read(session, revision, preserveError: preserveError);
    if (!_isCurrent(session, revision)) return;
    if (_expired || state.actionsDenied) {
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
    if (_taskListRefreshNeeded) {
      await _refreshTaskList(session, revision);
      if (!_isCurrent(session, revision)) return;
      if (state.actionsDenied || _expired) {
        state = state.copyWith(busy: false);
        return;
      }
    }
    if (_isCurrent(session, revision)) {
      state = state.copyWith(
        busy: false,
        requiresReadRetry: state.requiresReadRetry || _taskListRefreshNeeded,
      );
    }
  }

  Future<bool> _read(
    FixtureOutboundSession session,
    int revision, {
    OutboundCommandFailure? preserveError,
  }) async {
    if (!_isCurrent(session, revision) || !session.active || _expired) {
      return false;
    }
    if (_assignedActorId != null && _assignedActorId != session.userId) {
      _clearForAuth(
        const OutboundCommandFailure(
          OutboundCommandFailureCode.staleAssignment,
        ),
      );
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
        final command = _acknowledgedCommand;
        final task = details.task;
        final isAuthoritative =
            command != null &&
            task.kind == DeliveryTaskKind.outbound &&
            task.status == DeliveryTaskStatus.failed &&
            task.scope == DeliverySnapshotScope.restricted &&
            task.completedAt != null &&
            task.attemptNumber == command.attemptNumber;
        if (!isAuthoritative) {
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
        state = state.copyWith(
          details: AsyncData(details),
          error: preserveError,
          acknowledgement: state.acknowledgement,
          awaitingAuthoritativeRead: false,
          reported: true,
          requiresReadRetry: false,
        );
        return true;
      }
      if (state.reported &&
          !_isAuthoritativeFailed(details.task, state.acknowledgement)) {
        final failure = const OutboundCommandFailure(
          OutboundCommandFailureCode.staleState,
        );
        state = state.copyWith(
          details: AsyncError(failure, StackTrace.empty),
          error: failure,
          requiresReadRetry: true,
          reported: false,
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
      if (_isAuthInvalidation(failure)) {
        _clearForAuth(failure);
        return false;
      }
      state = state.copyWith(
        details: AsyncError(failure, StackTrace.empty),
        error: preserveError ?? failure,
        requiresReadRetry: true,
        pendingCommand: state.pendingCommand,
        acknowledgement: state.acknowledgement,
        reported: state.reported,
      );
      return false;
    }
  }

  Future<void> _refreshTaskList(
    FixtureOutboundSession session,
    int revision,
  ) async {
    if (!_isCurrent(session, revision)) return;
    final refresh = _dependencies.mh10Reload;
    if (refresh == null) {
      _taskListRefreshNeeded = false;
      return;
    }
    try {
      await refresh();
      if (!_isCurrent(session, revision)) return;
      _taskListRefreshNeeded = false;
      state = state.copyWith(error: null, requiresReadRetry: false);
    } catch (error) {
      if (!_isCurrent(session, revision)) return;
      final failure = _mapFailure(error);
      if (_isAuthInvalidation(failure)) {
        _clearForAuth(failure);
        return;
      }
      state = state.copyWith(
        error: failure,
        requiresReadRetry: true,
        reported: state.reported,
      );
    }
  }

  void _clearForAuth(OutboundCommandFailure failure) {
    if (_disposed || !ref.mounted) return;
    _expired = failure.code == OutboundCommandFailureCode.sessionExpired;
    _awaitingAuthoritativeRead = false;
    _taskListRefreshNeeded = false;
    _acknowledgedCommand = null;
    state = state.copyWith(
      details: AsyncError(failure, StackTrace.empty),
      busy: false,
      error: failure,
      pendingCommand: null,
      acknowledgement: null,
      requiresReadRetry: true,
      actionsDenied: true,
      awaitingAuthoritativeRead: false,
      reported: false,
    );
  }

  void _setValidationError(OutboundCommandFailureCode code) {
    if (_disposed || !ref.mounted) return;
    state = state.copyWith(
      busy: false,
      error: OutboundCommandFailure(code),
      requiresReadRetry: code == OutboundCommandFailureCode.staleState,
    );
  }

  bool _isEligibleTask(DeliveryTaskSnapshot? task) {
    if (task == null ||
        !taskId.isNotEmpty ||
        task.taskId != taskId ||
        task.kind != DeliveryTaskKind.outbound ||
        task.scope != DeliverySnapshotScope.current ||
        task.status != DeliveryTaskStatus.inTransit ||
        (task.attemptNumber != 1 && task.attemptNumber != 2) ||
        task.assignedAt == null ||
        task.acceptedAt == null ||
        task.startedAt == null) {
      return false;
    }
    return _session.userId != null &&
        _assignedActorId != null &&
        _assignedActorId == _session.userId;
  }

  static bool _isAuthoritativeFailed(
    DeliveryTaskSnapshot task,
    OutboundFailureAck? acknowledgement,
  ) {
    return task.kind == DeliveryTaskKind.outbound &&
        task.status == DeliveryTaskStatus.failed &&
        task.scope == DeliverySnapshotScope.restricted &&
        task.completedAt != null &&
        acknowledgement != null &&
        task.attemptNumber == acknowledgement.attemptNumber;
  }

  bool _isCurrent(FixtureOutboundSession session, int revision) =>
      !_disposed &&
      ref.mounted &&
      identical(_session, session) &&
      _sessionRevision == revision;

  static bool _isUncertain(OutboundCommandFailure failure) =>
      failure.code == OutboundCommandFailureCode.timeout ||
      failure.code == OutboundCommandFailureCode.network ||
      // The command has already crossed the repository boundary. A typed
      // invalid-data/decode failure at this point may be a committed write
      // whose ACK could not be decoded, so retain the same idempotency key.
      failure.code == OutboundCommandFailureCode.invalidData ||
      // Unclassified transport/dependency failures are also ambiguous after
      // dispatch. Retrying the same key is safer than releasing a fresh key.
      failure.code == OutboundCommandFailureCode.dependencyUnavailable ||
      failure.code == OutboundCommandFailureCode.unexpected;

  static bool _isAuthInvalidation(OutboundCommandFailure failure) =>
      failure.code == OutboundCommandFailureCode.sessionExpired ||
      failure.code == OutboundCommandFailureCode.permissionDenied ||
      failure.code == OutboundCommandFailureCode.staleAssignment;

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
    if (error is FormatException) {
      return const OutboundCommandFailure(
        OutboundCommandFailureCode.invalidData,
      );
    }
    return const OutboundCommandFailure(OutboundCommandFailureCode.unexpected);
  }
}
