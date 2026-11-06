import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/operational_providers.dart';
import '../../data/repositories/operational_read_access.dart';
import '../../domain/models/delivery_reporting.dart';
import '../../domain/models/delivery_task.dart';
import '../../domain/models/operational_failure.dart';
import '../../domain/models/outbound_task_command.dart';
import 'delivery_reporting_providers.dart';
import 'outbound_result_gate.dart';

/// Presentation state for the two P07.4 outbound reporting actions.
///
/// A report is an event/notification only.  It is intentionally not modelled
/// as a task completion or a manager receipt.  [acknowledgement] is retained
/// solely as a safe receipt for the user while the authoritative context,
/// detail and list projections are re-read.
class DeliveryReportingState {
  const DeliveryReportingState({
    required this.context,
    this.busy = false,
    this.error,
    this.pendingCommand,
    this.requiresReadRetry = false,
    this.actionsDenied = false,
    this.awaitingAuthoritativeRead = false,
    this.acknowledgement,
  });

  const DeliveryReportingState.initial()
    : this(context: const AsyncLoading<ReportingContext>());

  final AsyncValue<ReportingContext> context;
  final bool busy;
  final OutboundCommandFailure? error;

  /// The exact command envelope to reuse after an uncertain response.
  final ReportingCommand? pendingCommand;
  final bool requiresReadRetry;
  final bool actionsDenied;
  final bool awaitingAuthoritativeRead;
  final ReportingAck? acknowledgement;

  /// Effective UI eligibility. The server flags remain authoritative; the
  /// item check only prevents constructing an obviously invalid full-handover
  /// payload when a malformed/empty projection is returned.
  bool get canHandover {
    if (_blockedForAction || !context.hasValue) return false;
    final value = context.requireValue;
    return value.kind == DeliveryTaskKind.outbound &&
        value.canHandover &&
        !value.handoverReported &&
        value.items.isNotEmpty;
  }

  bool get canIncident {
    if (_blockedForAction || !context.hasValue) return false;
    return context.requireValue.kind == DeliveryTaskKind.outbound &&
        context.requireValue.canIncident;
  }

  String? get handoverBlockReason =>
      context.hasValue ? context.requireValue.handoverBlockReason : null;

  String? get incidentBlockReason =>
      context.hasValue ? context.requireValue.incidentBlockReason : null;

  bool get handoverReported =>
      context.hasValue && context.requireValue.handoverReported;

  bool get _blockedForAction =>
      busy ||
      actionsDenied ||
      requiresReadRetry ||
      awaitingAuthoritativeRead ||
      pendingCommand != null;

  DeliveryReportingState copyWith({
    AsyncValue<ReportingContext>? context,
    bool? busy,
    Object? error = _unset,
    Object? pendingCommand = _unset,
    bool? requiresReadRetry,
    bool? actionsDenied,
    bool? awaitingAuthoritativeRead,
    Object? acknowledgement = _unset,
  }) => DeliveryReportingState(
    context: context ?? this.context,
    busy: busy ?? this.busy,
    error: identical(error, _unset)
        ? this.error
        : error as OutboundCommandFailure?,
    pendingCommand: identical(pendingCommand, _unset)
        ? this.pendingCommand
        : pendingCommand as ReportingCommand?,
    requiresReadRetry: requiresReadRetry ?? this.requiresReadRetry,
    actionsDenied: actionsDenied ?? this.actionsDenied,
    awaitingAuthoritativeRead:
        awaitingAuthoritativeRead ?? this.awaitingAuthoritativeRead,
    acknowledgement: identical(acknowledgement, _unset)
        ? this.acknowledgement
        : acknowledgement as ReportingAck?,
  );
}

const _unset = Object();

final deliveryReportingViewModelProvider = NotifierProvider.autoDispose
    .family<DeliveryReportingViewModel, DeliveryReportingState, String>(
      DeliveryReportingViewModel.new,
    );

/// Alias retained for callers that name the provider after the outbound
/// screen instead of the repository feature.
final outboundDeliveryReportingViewModelProvider =
    deliveryReportingViewModelProvider;

class DeliveryReportingViewModel extends Notifier<DeliveryReportingState> {
  DeliveryReportingViewModel(this.taskId);

  final String taskId;
  OperationalSession? _session;
  ProviderSubscription<AsyncValue<OperationalSession>>? _sessionSubscription;
  var _disposed = false;
  var _sessionRevision = 0;
  var _generation = 0;
  var _visible = true;
  var _awaitingAuthoritativeContext = false;
  var _taskRefreshNeeded = false;
  var _listRefreshNeeded = false;
  var _initialized = false;
  void Function()? _closeKeepAlive;

  int get sessionRevisionForConfirmation => _sessionRevision;

  @override
  DeliveryReportingState build() {
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

    // Auto-dispose can cancel a provider while a dialog or a refresh is
    // hidden. Keep an uncertain command and its exact payload alive, but do
    // not retain a successful/idle account projection unnecessarily.
    ref.onCancel(() {
      scheduleMicrotask(() {
        if (_disposed) return;
        _visible = false;
        state = state.copyWith(
          context: const AsyncLoading(),
          busy: false,
          requiresReadRetry:
              state.requiresReadRetry ||
              state.busy ||
              state.pendingCommand != null ||
              _awaitingAuthoritativeContext ||
              _taskRefreshNeeded ||
              _listRefreshNeeded,
        );
        if (state.pendingCommand != null ||
            _awaitingAuthoritativeContext ||
            _taskRefreshNeeded ||
            _listRefreshNeeded) {
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
            (state.requiresReadRetry || _awaitingAuthoritativeContext)) {
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
      _session = null;
      _awaitingAuthoritativeContext = false;
      _taskRefreshNeeded = false;
      _listRefreshNeeded = false;
    });

    scheduleMicrotask(_loadInitial);
    return const DeliveryReportingState.initial();
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
      // A refreshed token is a new authorization epoch. Keep an uncertain
      // command, but force a fresh minimal context read before showing actions.
      state = state.copyWith(
        context: const AsyncLoading(),
        busy: false,
        requiresReadRetry:
            state.requiresReadRetry ||
            state.pendingCommand != null ||
            _awaitingAuthoritativeContext,
      );
      if (state.pendingCommand != null ||
          _awaitingAuthoritativeContext ||
          state.requiresReadRetry ||
          _taskRefreshNeeded ||
          _listRefreshNeeded) {
        _retainPendingOperation();
      } else {
        _releasePendingOperationIfIdle();
      }
      if (_initialized && _visible) {
        if (state.pendingCommand == null &&
            (_awaitingAuthoritativeContext ||
                state.requiresReadRetry ||
                _taskRefreshNeeded ||
                _listRefreshNeeded)) {
          // A token refresh can race with the post-ACK context/detail/list
          // reconciliation. Re-run the whole reconciliation so the gate and
          // refresh flags cannot remain stuck after a raw context read.
          unawaited(
            _reconcile(incoming, _sessionRevision, preserveError: state.error),
          );
        } else if (state.pendingCommand == null) {
          unawaited(_read(incoming, _sessionRevision));
        } else {
          // Refresh the minimal context for display, but never execute the
          // pending command automatically after a token refresh.
          unawaited(_read(incoming, _sessionRevision));
        }
      }
      return;
    }

    // A different account must never see the previous account's item names,
    // ACK or pending reason/key. The gate is released only for this owner.
    ref.read(outboundResultGateProvider(taskId).notifier).release(this);
    _awaitingAuthoritativeContext = false;
    _taskRefreshNeeded = false;
    _listRefreshNeeded = false;
    final usable = _usable(incoming);
    state = state.copyWith(
      context: usable
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
      actionsDenied: !usable,
      awaitingAuthoritativeRead: false,
      acknowledgement: null,
    );
    _releasePendingOperationIfIdle();
    if (_initialized && usable && _visible) {
      unawaited(_read(incoming, _sessionRevision));
    }
  }

  /// Submit a full exact item snapshot from the server-authorized context.
  Future<void> submitHandover({required int sessionRevision}) async {
    final session = _session;
    if (!_canSubmit(session, sessionRevision) || !state.canHandover) return;
    final context = state.context.requireValue;
    final command = ReportingCommand.handover(
      taskId: taskId,
      requestId: ref.read(deliveryReportingRequestIdProvider)(),
      // Copy the immutable projection so later context refreshes cannot alter
      // the payload retained for an uncertain retry.
      items: List<ReportItem>.unmodifiable(context.items),
    );
    if (!_validCommand(command)) {
      _validation(OutboundCommandFailureCode.invalidData);
      return;
    }
    await _execute(command, session!, _sessionRevision);
  }

  /// Submit a damaged/lost/other incident. Reason is required for every kind.
  Future<void> submitIncident({
    required ReportingIncidentKind kind,
    required String reason,
    required int sessionRevision,
  }) async {
    final session = _session;
    final trimmed = reason.trim();
    if (!_canSubmit(session, sessionRevision) ||
        !state.canIncident ||
        trimmed.isEmpty) {
      if (trimmed.isEmpty && !_disposed) {
        _validation(OutboundCommandFailureCode.invalidData);
      }
      return;
    }
    final command = ReportingCommand.incident(
      taskId: taskId,
      requestId: ref.read(deliveryReportingRequestIdProvider)(),
      incidentKind: kind,
      reason: trimmed,
    );
    if (!_validCommand(command)) {
      _validation(OutboundCommandFailureCode.invalidData);
      return;
    }
    await _execute(command, session!, _sessionRevision);
  }

  /// Reuse a pending command after an uncertain response, or re-read all
  /// projections after a failed/partial reconciliation. No new request ID is
  /// generated on this path.
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
    await _reconcile(session, revision, preserveError: state.error);
  }

  /// Re-read only the minimal reporting context when MH11's normal task
  /// projection changes (for example assigned → accepted → in transit or a
  /// manager decision). A pending uncertain command is deliberately not
  /// executed here: its request ID and exact payload remain gated for the
  /// explicit retry action.
  Future<void> refreshContext() async {
    final session = _session;
    if (_disposed ||
        !_visible ||
        session == null ||
        !_usable(session) ||
        state.busy ||
        _awaitingAuthoritativeContext) {
      return;
    }
    await _read(session, _sessionRevision, preserveError: state.error);
  }

  bool _canSubmit(OperationalSession? session, int revision) =>
      !_disposed &&
      _visible &&
      session != null &&
      _usable(session) &&
      revision == _sessionRevision &&
      state.context.hasValue &&
      !state.busy &&
      !state.actionsDenied &&
      !state.requiresReadRetry &&
      !state.awaitingAuthoritativeRead &&
      state.pendingCommand == null;

  Future<void> _execute(
    ReportingCommand command,
    OperationalSession session,
    int revision,
  ) async {
    if (!_epochCurrent(session, revision)) return;
    if (!ref.read(outboundResultGateProvider(taskId).notifier).acquire(this)) {
      return;
    }
    _retainPendingOperation();
    state = state.copyWith(
      busy: true,
      error: null,
      pendingCommand: command,
      requiresReadRetry: false,
      acknowledgement: null,
    );
    try {
      final ack = await ref
          .read(deliveryReportingRepositoryProvider)
          .execute(command);
      if (!_validAck(ack, command)) {
        throw const OutboundAcknowledgementFailure();
      }
      if (!_epochCurrent(session, revision)) return;
      _awaitingAuthoritativeContext = true;
      _taskRefreshNeeded = true;
      _listRefreshNeeded = true;
      state = state.copyWith(
        busy: _visible,
        pendingCommand: null,
        awaitingAuthoritativeRead: true,
        requiresReadRetry: !_visible,
        acknowledgement: ack,
      );
      _retainPendingOperation();
      if (!_visible) return;
      await _reconcile(session, revision);
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
        awaitingAuthoritativeRead: false,
      );
      if (uncertain) {
        // Keep the gate and command envelope until the user explicitly retries
        // with the same key/payload.
        _retainPendingOperation();
        return;
      }
      _taskRefreshNeeded = true;
      _listRefreshNeeded = true;
      await _reconcile(session, revision, preserveError: failure);
    }
  }

  Future<void> _reconcile(
    OperationalSession session,
    int revision, {
    OutboundCommandFailure? preserveError,
  }) async {
    if (!_epochCurrent(session, revision) || !_visible) return;
    final readOk = await _read(session, revision, preserveError: preserveError);
    if (!readOk || !_epochCurrent(session, revision) || !_visible) return;
    if (_awaitingAuthoritativeContext) {
      _awaitingAuthoritativeContext = false;
      state = state.copyWith(awaitingAuthoritativeRead: false);
    }
    await _refreshCaches(session, revision, preserveError: preserveError);
  }

  Future<bool> _read(
    OperationalSession session,
    int revision, {
    OutboundCommandFailure? preserveError,
  }) async {
    if (!_epochCurrent(session, revision) || !_visible) return false;
    final generation = ++_generation;
    state = state.copyWith(
      context: const AsyncLoading(),
      error: preserveError,
      busy: state.busy,
    );
    try {
      final value = await ref.read(deliveryReportingContextReloadProvider)(
        taskId,
      );
      if (!_current(session, revision) || generation != _generation) {
        return false;
      }
      if (value.taskId.toLowerCase() != taskId.toLowerCase()) {
        throw const FormatException('Reporting context task mismatch');
      }
      state = state.copyWith(
        context: AsyncData(value),
        error: preserveError,
        requiresReadRetry: false,
      );
      return true;
    } catch (error) {
      if (!_current(session, revision) || generation != _generation) {
        return false;
      }
      final failure = _map(error);
      state = state.copyWith(
        context: AsyncError(failure, StackTrace.current),
        busy: false,
        error: preserveError ?? failure,
        requiresReadRetry: true,
        awaitingAuthoritativeRead: _awaitingAuthoritativeContext,
      );
      _retainPendingOperationIfNeeded();
      return false;
    }
  }

  Future<void> _refreshCaches(
    OperationalSession session,
    int revision, {
    OutboundCommandFailure? preserveError,
  }) async {
    if (!_epochCurrent(session, revision) || !_visible) return;
    state = state.copyWith(busy: true);
    OutboundCommandFailure? first;
    if (_taskRefreshNeeded) {
      try {
        await ref.read(deliveryReportingDetailsReloadProvider)(taskId);
        if (!_epochCurrent(session, revision)) return;
        _taskRefreshNeeded = false;
      } catch (error) {
        if (!_epochCurrent(session, revision)) return;
        first = _map(error);
      }
    }
    if (_listRefreshNeeded) {
      try {
        await ref.read(deliveryReportingTaskListReloadProvider)();
        if (!_epochCurrent(session, revision)) return;
        _listRefreshNeeded = false;
      } catch (error) {
        if (!_epochCurrent(session, revision)) return;
        first ??= _map(error);
      }
    }
    if (!_epochCurrent(session, revision)) return;
    final reconciliationError = first ?? preserveError;
    state = state.copyWith(
      busy: false,
      error: reconciliationError,
      requiresReadRetry:
          first != null || _taskRefreshNeeded || _listRefreshNeeded,
    );
    _releasePendingOperationIfIdle();
  }

  void _validation(OutboundCommandFailureCode code) {
    if (_disposed) return;
    state = state.copyWith(busy: false, error: OutboundCommandFailure(code));
  }

  void _setDenied(OutboundCommandFailure failure) {
    if (_disposed) return;
    ref.read(outboundResultGateProvider(taskId).notifier).release(this);
    _awaitingAuthoritativeContext = false;
    _taskRefreshNeeded = false;
    _listRefreshNeeded = false;
    state = state.copyWith(
      context: AsyncError(failure, StackTrace.empty),
      busy: false,
      error: failure,
      pendingCommand: null,
      actionsDenied: true,
      awaitingAuthoritativeRead: false,
      requiresReadRetry: false,
      acknowledgement: null,
    );
    _closeKeepAlive?.call();
    _closeKeepAlive = null;
  }

  void _retainPendingOperationIfNeeded() {
    if (state.pendingCommand != null ||
        state.busy ||
        state.requiresReadRetry ||
        state.awaitingAuthoritativeRead ||
        _awaitingAuthoritativeContext ||
        _taskRefreshNeeded ||
        _listRefreshNeeded) {
      _retainPendingOperation();
    }
  }

  void _retainPendingOperation() {
    _closeKeepAlive ??= ref.keepAlive().close;
  }

  void _releasePendingOperationIfIdle() {
    if (state.pendingCommand != null ||
        state.busy ||
        state.requiresReadRetry ||
        state.awaitingAuthoritativeRead ||
        _awaitingAuthoritativeContext ||
        _taskRefreshNeeded ||
        _listRefreshNeeded) {
      return;
    }
    ref.read(outboundResultGateProvider(taskId).notifier).release(this);
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

  static bool _usable(OperationalSession? value) =>
      value != null && value.userId != null && value.failure == null;

  static bool _validCommand(ReportingCommand command) {
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    if (!uuid.hasMatch(command.taskId) || !uuid.hasMatch(command.requestId)) {
      return false;
    }
    if (command.operation == ReportingOperation.handover) {
      if (command.items.isEmpty ||
          command.incidentKind != null ||
          command.reason != null) {
        return false;
      }
      String? previous;
      final seen = <String>{};
      for (final item in command.items) {
        if (!uuid.hasMatch(item.orderItemId) ||
            item.quantity <= 0 ||
            !seen.add(item.orderItemId.toLowerCase())) {
          return false;
        }
        final current = item.orderItemId.toLowerCase();
        if (previous != null && current.compareTo(previous) < 0) return false;
        previous = current;
      }
      return true;
    }
    return command.items.isEmpty &&
        command.incidentKind != null &&
        command.reason != null &&
        command.reason!.trim().isNotEmpty;
  }

  static bool _validAck(ReportingAck ack, ReportingCommand command) {
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    try {
      // Accessing operationKind rejects an unknown operation without trusting
      // a fake/partial ACK from a test seam or an unexpected server response.
      final operationKind = ack.operationKind;
      return uuid.hasMatch(ack.taskId) &&
          uuid.hasMatch(ack.orderId) &&
          uuid.hasMatch(ack.requestId) &&
          uuid.hasMatch(ack.eventId) &&
          ack.taskId.toLowerCase() == command.taskId.toLowerCase() &&
          ack.requestId.toLowerCase() == command.requestId.toLowerCase() &&
          operationKind == command.operation &&
          ack.operation == command.operation.rpcName &&
          ack.reportedAt.isUtc &&
          ack.taskStatus.trim().isNotEmpty &&
          ack.orderStatus.trim().isNotEmpty;
    } on Object {
      return false;
    }
  }

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
