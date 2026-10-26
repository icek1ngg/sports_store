import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/outbound_task_command.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';
import 'package:sports_store/features/deliveries/domain/repositories/outbound_task_command_repository.dart';

/// A test-only session identity. It intentionally does not model Supabase
/// claims or RLS; production code must obtain those from the shared session.
class FixtureOutboundSession {
  const FixtureOutboundSession({
    required this.userId,
    required this.epoch,
    required this.isShipper,
  });

  final String? userId;
  final int epoch;
  final bool isShipper;

  bool get active => userId != null && isShipper;
}

/// Dependencies used only by the P04.2 action fixture tests.
class FixtureOutboundActionDependencies {
  const FixtureOutboundActionDependencies({
    required this.initialSession,
    required this.readTask,
    required this.commandRepository,
    required this.createRequestId,
    this.refreshTaskList,
  });

  final FixtureOutboundSession initialSession;
  final Future<DeliveryTaskDetails> Function(String taskId) readTask;
  final OutboundTaskCommandRepository commandRepository;
  final String Function() createRequestId;
  final Future<void> Function()? refreshTaskList;
}

final fixtureOutboundActionDependenciesProvider =
    Provider<FixtureOutboundActionDependencies>((ref) {
      throw StateError(
        'Override fixtureOutboundActionDependenciesProvider in tests',
      );
    });

class FixtureOutboundActionState {
  const FixtureOutboundActionState({
    required this.details,
    required this.session,
    this.busy = false,
    this.error,
    this.pendingCommand,
    this.requiresReadRetry = false,
    this.actionsDenied = false,
  });

  const FixtureOutboundActionState.initial(FixtureOutboundSession session)
    : this(details: const AsyncLoading(), session: session);

  final AsyncValue<DeliveryTaskDetails> details;
  final FixtureOutboundSession session;
  final bool busy;
  final OutboundCommandFailure? error;
  final OutboundTaskCommand? pendingCommand;
  final bool requiresReadRetry;
  final bool actionsDenied;

  bool get canAccept =>
      _can(OutboundTaskAction.acceptGoods) && !busy && pendingCommand == null;

  bool get canStart =>
      _can(OutboundTaskAction.startDelivery) && !busy && pendingCommand == null;

  bool _can(OutboundTaskAction action) {
    if (!session.active ||
        actionsDenied ||
        requiresReadRetry ||
        details.isLoading ||
        !details.hasValue) {
      return false;
    }
    return canExecuteOutboundAction(details.requireValue.task, action);
  }

  FixtureOutboundActionState copyWith({
    AsyncValue<DeliveryTaskDetails>? details,
    FixtureOutboundSession? session,
    bool? busy,
    Object? error = _unset,
    Object? pendingCommand = _unset,
    bool? requiresReadRetry,
    bool? actionsDenied,
  }) {
    return FixtureOutboundActionState(
      details: details ?? this.details,
      session: session ?? this.session,
      busy: busy ?? this.busy,
      error: identical(error, _unset)
          ? this.error
          : error as OutboundCommandFailure?,
      pendingCommand: identical(pendingCommand, _unset)
          ? this.pendingCommand
          : pendingCommand as OutboundTaskCommand?,
      requiresReadRetry: requiresReadRetry ?? this.requiresReadRetry,
      actionsDenied: actionsDenied ?? this.actionsDenied,
    );
  }
}

const _unset = Object();

final fixtureOutboundActionViewModelProvider = NotifierProvider.autoDispose
    .family<FixtureOutboundActionViewModel, FixtureOutboundActionState, String>(
      FixtureOutboundActionViewModel.new,
    );

/// Test-only ViewModel that exercises P04.2 ordering and retry semantics.
/// It is deliberately outside `lib/` and must never be imported by runtime UI.
class FixtureOutboundActionViewModel
    extends Notifier<FixtureOutboundActionState> {
  FixtureOutboundActionViewModel(this.taskId);

  final String taskId;
  late FixtureOutboundActionDependencies _dependencies;
  late FixtureOutboundSession _session;
  bool _disposed = false;
  int _sessionRevision = 0;
  int _readGeneration = 0;
  bool _listRefreshNeeded = false;
  OutboundTaskAction? _lastAcknowledgedAction;
  bool _expired = false;

  @override
  FixtureOutboundActionState build() {
    _disposed = false;
    final revision = ++_sessionRevision;
    _readGeneration++;
    _listRefreshNeeded = false;
    _lastAcknowledgedAction = null;
    _expired = false;
    _dependencies = ref.watch(fixtureOutboundActionDependenciesProvider);
    final session = _session = _dependencies.initialSession;
    ref.onDispose(() {
      _disposed = true;
      _sessionRevision++;
      _readGeneration++;
    });
    scheduleMicrotask(() {
      if (_isCurrent(session, revision)) unawaited(_read(session, revision));
    });
    return _initial(session);
  }

  FixtureOutboundActionState _initial(FixtureOutboundSession session) {
    if (session.active) return FixtureOutboundActionState.initial(session);
    final failure = OutboundCommandFailure(
      session.userId == null
          ? OutboundCommandFailureCode.sessionExpired
          : OutboundCommandFailureCode.permissionDenied,
    );
    return FixtureOutboundActionState(
      details: AsyncError(failure, StackTrace.empty),
      session: session,
      error: failure,
    );
  }

  void updateSession(FixtureOutboundSession next) {
    if (_disposed || identical(_session, next)) return;
    final revision = ++_sessionRevision;
    _readGeneration++;
    _listRefreshNeeded = false;
    _lastAcknowledgedAction = null;
    _expired = false;
    _session = next;
    state = _initial(next);
    if (next.active) unawaited(_read(next, revision));
  }

  /// Manual reads preserve uncertain command identity and never submit it.
  Future<void> refresh() async {
    if (_disposed || state.busy || !_session.active || _expired) return;
    final session = _session;
    final revision = _sessionRevision;
    state = state.copyWith(busy: true);
    await _reload(
      session,
      revision,
      preserveError: state.pendingCommand == null && !state.actionsDenied
          ? null
          : state.error,
    );
  }

  Future<void> submit(OutboundTaskAction action) async {
    if (_disposed || state.busy || state.actionsDenied || _expired) return;
    final session = _session;
    final revision = _sessionRevision;
    if (!session.active) {
      state = _initial(session);
      return;
    }
    final existing = state.pendingCommand;
    if (existing != null && existing.action != action) return;
    if (existing == null &&
        (state.requiresReadRetry ||
            !state.details.hasValue ||
            state.details.isLoading ||
            state.details.requireValue.task.taskId != taskId ||
            !canExecuteOutboundAction(
              state.details.requireValue.task,
              action,
            ))) {
      state = state.copyWith(
        error: const OutboundCommandFailure(
          OutboundCommandFailureCode.staleState,
        ),
      );
      return;
    }
    late OutboundTaskCommand command;
    try {
      command =
          existing ??
          OutboundTaskCommand(
            taskId: taskId,
            requestId: _dependencies.createRequestId(),
            action: action,
          );
      if (!command.isUuidShaped) {
        throw const FormatException('Invalid fixture command UUID');
      }
    } catch (_) {
      state = state.copyWith(
        error: const OutboundCommandFailure(
          OutboundCommandFailureCode.invalidData,
        ),
      );
      return;
    }
    state = state.copyWith(busy: true, error: null, pendingCommand: command);
    try {
      await _dependencies.commandRepository.execute(command);
    } catch (error) {
      if (!_isCurrent(session, revision)) return;
      final failure = _mapFailure(error);
      final uncertain =
          failure.code == OutboundCommandFailureCode.timeout ||
          failure.code == OutboundCommandFailureCode.network;
      state = state.copyWith(
        error: failure,
        pendingCommand: uncertain ? command : null,
        actionsDenied:
            failure.code == OutboundCommandFailureCode.permissionDenied ||
            failure.code == OutboundCommandFailureCode.sessionExpired ||
            failure.code == OutboundCommandFailureCode.staleAssignment ||
            failure.code == OutboundCommandFailureCode.dependencyUnavailable,
      );
      if (failure.code == OutboundCommandFailureCode.sessionExpired) {
        _expired = true;
        state = state.copyWith(
          busy: false,
          details: AsyncError(failure, StackTrace.empty),
        );
        return;
      }
      await _reload(session, revision, preserveError: failure);
      return;
    }
    if (!_isCurrent(session, revision)) return;
    // ACK is not a task snapshot. Only the separate read can change visible state.
    _listRefreshNeeded = true;
    _lastAcknowledgedAction = action;
    state = state.copyWith(pendingCommand: null, error: null);
    await _reload(session, revision);
  }

  Future<void> retry() async {
    if (_disposed || state.busy || !_session.active || _expired) return;
    final pending = state.pendingCommand;
    if (pending != null) {
      await submit(pending.action);
    } else {
      await refresh();
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
    if (_listRefreshNeeded) {
      try {
        await _dependencies.refreshTaskList?.call();
        if (!_isCurrent(session, revision)) return;
        _listRefreshNeeded = false;
      } catch (error) {
        if (!_isCurrent(session, revision)) return;
        final failure = _mapFailure(error);
        final terminal = _terminal(failure);
        if (failure.code == OutboundCommandFailureCode.sessionExpired) {
          _expired = true;
        }
        state = state.copyWith(
          busy: false,
          error: failure,
          requiresReadRetry: true,
          actionsDenied: terminal,
          pendingCommand: terminal ? null : state.pendingCommand,
          details: _expired
              ? AsyncError(failure, StackTrace.empty)
              : state.details,
        );
        return;
      }
    }
    if (_isCurrent(session, revision)) {
      state = state.copyWith(busy: false, requiresReadRetry: !readOk);
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
      final unchangedAfterAck = switch (_lastAcknowledgedAction) {
        OutboundTaskAction.acceptGoods =>
          details.task.status == DeliveryTaskStatus.assigned ||
              details.task.status == DeliveryTaskStatus.pendingAssignment,
        OutboundTaskAction.startDelivery =>
          details.task.status == DeliveryTaskStatus.accepted ||
              details.task.status == DeliveryTaskStatus.assigned ||
              details.task.status == DeliveryTaskStatus.pendingAssignment,
        null => false,
      };
      if (unchangedAfterAck) {
        throw const OutboundCommandFailure(
          OutboundCommandFailureCode.staleState,
        );
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
        pendingCommand: terminal ? null : state.pendingCommand,
        actionsDenied:
            state.actionsDenied ||
            failure.code == OutboundCommandFailureCode.permissionDenied ||
            failure.code == OutboundCommandFailureCode.staleAssignment ||
            failure.code == OutboundCommandFailureCode.sessionExpired ||
            failure.code == OutboundCommandFailureCode.dependencyUnavailable,
      );
      return false;
    }
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
      return OutboundCommandFailure(OutboundCommandFailureCode.timeout);
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
