import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../features/cod/domain/repositories/cod_repository.dart';
import '../../features/deliveries/data/repositories/operational_read_access.dart';
import '../../features/deliveries/domain/models/delivery_task.dart';
import '../../features/deliveries/domain/models/operational_failure.dart';
import '../../features/deliveries/domain/repositories/delivery_repository.dart';

class OperationalRouteLocation {
  const OperationalRouteLocation({
    required this.protected,
    this.taskId,
    this.orderId,
    this.map = false,
    this.invalidId = false,
    this.customerOnly = false,
  });

  final bool protected;
  final String? taskId;
  final String? orderId;
  final bool map;
  final bool invalidId;
  // Only routes that require the customer role without an entity-specific
  // route check may share this authorization scope.
  final bool customerOnly;
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static OperationalRouteLocation parse(Uri uri) {
    try {
      return _parse(uri);
    } on FormatException {
      return const OperationalRouteLocation(protected: true, invalidId: true);
    }
  }

  static OperationalRouteLocation _parse(Uri uri) {
    final parts = uri.pathSegments;
    if (uri.path == '/customer/cart' || uri.path == '/customer/checkout') {
      return const OperationalRouteLocation(
        protected: true,
        customerOnly: true,
      );
    }
    if (uri.path == '/customer/products') {
      return const OperationalRouteLocation(
        protected: true,
        customerOnly: true,
      );
    }
    if (parts.length >= 3 && parts[0] == 'customer' && parts[1] == 'products') {
      return OperationalRouteLocation(
        protected: true,
        customerOnly: true,
        invalidId: parts.length != 3 || !_uuid.hasMatch(parts[2]),
      );
    }
    if (uri.path == '/cod') {
      final ids = uri.queryParametersAll['orderId'];
      final order = ids?.first;
      return OperationalRouteLocation(
        protected: true,
        orderId: order,
        invalidId: ids != null && (ids.length != 1 || !_uuid.hasMatch(order!)),
      );
    }
    if (uri.path == '/notifications' || uri.path == '/shipper/tasks') {
      return const OperationalRouteLocation(protected: true);
    }
    if (parts.length >= 3 && parts[0] == 'shipper' && parts[1] == 'tasks') {
      final isMap = parts.length == 4 && parts[3] == 'map';
      final exact = parts.length == 3 || isMap;
      return OperationalRouteLocation(
        protected: true,
        taskId: parts[2],
        map: isMap,
        invalidId: !exact || !_uuid.hasMatch(parts[2]),
      );
    }
    return const OperationalRouteLocation(protected: false);
  }
}

class OperationalRouteDecision {
  const OperationalRouteDecision({
    required this.location,
    required this.session,
    this.role,
    this.failure,
    this.invalidId = false,
  });
  final String location;
  final OperationalSession session;
  final String? role;
  final OperationalFailure? failure;
  final bool invalidId;
  bool get allowed => role != null && failure == null && !invalidId;
}

/// Uses the existing P01.2 session lifecycle and backend read contracts.
/// Missing auth/MH17 screens remain integration dependencies, not fake screens.
class OperationalRouteGuard extends ChangeNotifier {
  OperationalRouteGuard({
    required this.access,
    required this.deliveries,
    required this.cod,
  }) {
    _lastUserId = access.currentSession.userId;
    _subscription = access.watchSession().listen((session) {
      if (!identical(_observed, session)) {
        if (_lastUserId != session.userId) _resetAccountNavigation = true;
        _lastUserId = session.userId;
        _observed = session;
        _sequence++;
        _decision = null;
        notifyListeners();
      }
    });
    _observed = access.currentSession;
  }

  final OperationalReadAccess access;
  final DeliveryRepository deliveries;
  final CodRepository cod;
  late final StreamSubscription<OperationalSession> _subscription;
  OperationalSession? _observed;
  final decisionChanges = ValueNotifier<OperationalRouteDecision?>(null);
  OperationalRouteDecision? get _decision => decisionChanges.value;
  set _decision(OperationalRouteDecision? value) =>
      decisionChanges.value = value;
  int _sequence = 0;
  bool _disposed = false;
  String? _lastUserId;
  bool _resetAccountNavigation = false;

  OperationalRouteDecision? decisionFor(Uri uri) {
    final decision = _decision;
    if (decision == null ||
        !identical(decision.session, access.currentSession)) {
      return null;
    }
    if (decision.location == uri.toString()) return decision;

    // go_router 18 restores an imperative stack by redirecting its base URI,
    // while the shell receives the visible leaf URI. These four customer
    // routes have the same role-only guard; repositories still authorize each
    // read/write. Never reuse task/COD decisions or invalid route IDs here.
    final source = OperationalRouteLocation.parse(Uri.parse(decision.location));
    final target = OperationalRouteLocation.parse(uri);
    final customerOutcome =
        decision.failure != null ||
        (decision.allowed && decision.role == 'customer');
    if (!customerOutcome ||
        decision.invalidId ||
        !source.customerOnly ||
        source.invalidId ||
        !target.customerOnly ||
        target.invalidId) {
      return null;
    }
    return OperationalRouteDecision(
      location: uri.toString(),
      session: decision.session,
      role: decision.role,
      failure: decision.failure,
    );
  }

  Future<String?> redirect(GoRouterState state) async {
    final request = ++_sequence;
    final target = OperationalRouteLocation.parse(state.uri);
    if (!target.protected) {
      _decision = null;
      _resetAccountNavigation = false;
      return null;
    }
    // Tear down the protected navigator on account changes, including shipper
    // A -> shipper B. Token refresh for the same user instead rechecks the URL.
    if (_resetAccountNavigation) {
      _resetAccountNavigation = false;
      _decision = null;
      return '/';
    }
    final session = access.currentSession;
    if (target.invalidId) {
      _decision = OperationalRouteDecision(
        location: state.uri.toString(),
        session: session,
        invalidId: true,
      );
      return null;
    }
    try {
      final String role;
      if (target.taskId != null) {
        // The repository checks current profile role AND exact task permission.
        final task = await deliveries.getTask(target.taskId!);
        if (target.map &&
            (task.scope != DeliverySnapshotScope.current ||
                task.destination == null)) {
          throw const OperationalFailure(
            OperationalFailureCode.permissionDenied,
          );
        }
        role = 'shipper';
      } else {
        final allowed = target.customerOnly
            ? const {'customer'}
            : state.uri.path == '/shipper/tasks'
            ? const {'shipper'}
            : state.uri.path == '/cod'
            ? const {'shipper', 'manager'}
            : const {'customer', 'shipper', 'manager'};
        role = await access.run(
          roles: allowed,
          action: (identity) async => identity.role,
        );
        if (state.uri.path == '/cod' && target.orderId != null) {
          final rows = await cod.listCollections(orderId: target.orderId);
          if (rows.isEmpty) {
            throw const OperationalFailure(
              OperationalFailureCode.permissionDenied,
            );
          }
        }
      }
      if (_disposed ||
          request != _sequence ||
          !identical(session, access.currentSession)) {
        return null;
      }
      _decision = OperationalRouteDecision(
        location: state.uri.toString(),
        session: session,
        role: role,
      );
      return null;
    } catch (error) {
      if (_disposed ||
          request != _sequence ||
          !identical(session, access.currentSession)) {
        return null;
      }
      final failure = mapOperationalFailure(error);
      _decision = OperationalRouteDecision(
        location: state.uri.toString(),
        session: session,
        failure: failure,
      );
      // Only local constants are redirect targets; URL query strings never
      // become destinations, and denied UUIDs are not reflected in messages.
      return switch (failure.code) {
        OperationalFailureCode.sessionExpired ||
        OperationalFailureCode.permissionDenied ||
        OperationalFailureCode.staleAssignment => '/',
        _ => null,
      };
    }
  }

  @override
  void dispose() {
    _disposed = true;
    decisionChanges.dispose();
    _sequence++;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
