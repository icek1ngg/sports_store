import 'dart:async';

import '../../../../core/errors/presentation_failure_message.dart';
import '../../domain/models/notification_item.dart';
import '../../domain/models/notification_query.dart';
import '../../domain/models/notification_target.dart';
import 'notification_interaction_view_model.dart';
import 'notification_page_read_coordinator.dart';
import 'notification_page_session_bridge.dart';

typedef NotificationActionPorts = ({
  bool Function() isActive,
  NotificationReadPorts reads,
  NotificationQuery Function() query,
  NotificationInteractionViewModel Function() interaction,
  NotificationInteractionState Function() state,
  Future<bool> Function(NotificationTargetDecision)? Function() navigation,
  void Function(String) message,
  // Synchronous handoff preserves canonical object identity for the UI guard.
  void Function(NotificationReadNamespace, NotificationItem) context,
});
typedef _ActionTicket = ({NotificationReadNamespace namespace, int revision});

/// UI orchestration only; canonical read/target authority remains in the VM.
class NotificationPageActions {
  NotificationPageActions({required this.session, required this.reads});
  final NotificationPageSessionBridge session;
  final NotificationPageReadCoordinator reads;
  bool _disposed = false;

  bool _current(
    NotificationReadNamespace submitted,
    NotificationActionPorts ports,
  ) {
    if (_disposed || !ports.isActive()) return false;
    final live = ports.reads.current();
    return !_disposed &&
        ports.isActive() &&
        live == submitted &&
        session.isCurrent(submitted.lease, live.scope, live.cache) &&
        reads.synchronize(live) &&
        reads.accessFailure == null;
  }

  ({_ActionTicket ticket, NotificationInteractionViewModel vm})? _begin(
    NotificationReadNamespace submitted,
    NotificationActionPorts ports,
  ) {
    if (!_current(submitted, ports)) return null;
    final query = ports.query();
    if (!_current(submitted, ports) || !reads.canInteract(ports.reads, query)) {
      return null;
    }
    final vm = ports.interaction();
    if (!_current(submitted, ports) || !reads.canInteract(ports.reads, query)) {
      return null;
    }
    return (ticket: (namespace: submitted, revision: reads.revision), vm: vm);
  }

  /// Non-async entry: no raw notification enters this adapter's continuations.
  Future<bool> markRead(
    NotificationItem item,
    NotificationReadNamespace submitted,
    NotificationActionPorts ports,
  ) {
    final start = _begin(submitted, ports);
    if (start == null) return Future.value(false);
    return _finishRead(
      item.id,
      start.ticket,
      start.vm.markRead(item),
      ports,
      reportFailure: true,
    );
  }

  /// Read and open remain independent, with VM-owned per-ID read deduplication.
  Future<bool> open(
    NotificationItem item,
    NotificationReadNamespace submitted,
    NotificationActionPorts ports,
  ) {
    final start = _begin(submitted, ports);
    if (start == null) return Future.value(false);
    final read = item.isRead
        ? Future<bool>.value(true)
        : start.vm.markRead(item);
    unawaited(_finishRead(item.id, start.ticket, read, ports));
    if (!_current(submitted, ports)) return Future.value(false);
    final navigate = _navigator(submitted, ports);
    if (!_current(submitted, ports)) return Future.value(false);
    final opening = start.vm.openNotification(item, onNavigate: navigate);
    final informational =
        item.subjectType.rawValue ==
        NotificationSubjectType.notificationOnly.rawValue;
    if (informational &&
        item.recipientId == submitted.scope.userId &&
        _current(submitted, ports)) {
      ports.context(submitted, item);
    }
    return _finishOpen(item.id, submitted, opening, ports, informational);
  }

  Future<bool> _finishRead(
    String id,
    _ActionTicket ticket,
    Future<bool> pending,
    NotificationActionPorts ports, {
    bool reportFailure = false,
  }) async {
    final acknowledged = await pending;
    if (!_current(ticket.namespace, ports)) return false;
    if (acknowledged) {
      reads.afterCanonicalRead(true, ticket.revision, ports.reads);
      return _current(ticket.namespace, ports);
    }
    if (reportFailure) {
      final state = ports.state();
      if (_current(ticket.namespace, ports)) {
        ports.message(failureMessage(state.failureFor(id)));
      }
    }
    return false;
  }

  Future<bool> _finishOpen(
    String id,
    NotificationReadNamespace submitted,
    Future<bool> pending,
    NotificationActionPorts ports,
    bool informational,
  ) async {
    final navigated = await pending;
    if (!_current(submitted, ports)) return false;
    if (!navigated && !informational) {
      final state = ports.state();
      if (!_current(submitted, ports)) return false;
      ports.message(
        state.lastUnavailableMessageKey != null || state.failureFor(id) == null
            ? 'Mục tiêu thông báo hiện chưa khả dụng.'
            : failureMessage(state.failureFor(id)),
      );
    }
    return navigated;
  }

  Future<bool> Function(NotificationTargetDecision)? _navigator(
    NotificationReadNamespace submitted,
    NotificationActionPorts ports,
  ) {
    if (!_current(submitted, ports) || ports.navigation() == null) return null;
    // This closure has no item/title/body in its lexical scope.
    return (decision) => _navigate(submitted, decision, ports);
  }

  Future<bool> _navigate(
    NotificationReadNamespace submitted,
    NotificationTargetDecision decision,
    NotificationActionPorts ports,
  ) async {
    if (!_current(submitted, ports)) return false;
    final navigate = ports.navigation();
    if (navigate == null || !_current(submitted, ports)) return false;
    final navigated = await navigate(decision);
    return _current(submitted, ports) && navigated;
  }

  void dispose() => _disposed = true;
}
