import 'package:flutter/foundation.dart';
import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/orders/domain/models/order_details.dart';
import 'package:sports_store/features/orders/domain/models/order_page.dart';
import 'package:sports_store/features/orders/domain/models/order_query.dart';

import '../../test/fixtures/order_notification_fixtures.dart';
import 'mh07_preview_data.dart';
import 'mh08_manager_repository.dart';
import 'mh09_preview_details.dart';
import 'mh09_preview_scenario.dart';

/// Only owner of the active demo screen/scenario/session generation.
class Mh08PreviewEnvironment extends ChangeNotifier {
  Mh08PreviewEnvironment() {
    orders = Mh08PreviewRepository(this);
    mh09 = Mh09PreviewDetails(
      manager.canonicalDetails,
      canRead: () =>
          managerActive && scope.role == 'manager' && scope.canReadPrivateData,
    );
  }

  late final Mh08PreviewRepository orders;
  late final Mh09PreviewDetails mh09;
  SessionScope? _detailScope;
  String screen = 'MH07';
  Mh08PreviewScenario scenario = Mh08PreviewScenario.data;
  int generation = 1;
  bool get managerActive => screen == 'MH08';
  Mh08ManagerRepository get manager => orders.manager;

  SessionScope get scope {
    if (managerActive && _detailScope != null) return _detailScope!;
    if (scenario == Mh08PreviewScenario.expired) {
      return SessionScope(userId: null, role: null, generation: generation);
    }
    if (scenario == Mh08PreviewScenario.sessionUnavailable) {
      return SessionScope(
        userId: null,
        role: null,
        generation: generation,
        roleResolved: false,
      );
    }
    final managerRole =
        managerActive && scenario != Mh08PreviewScenario.unauthorized;
    return SessionScope(
      userId: managerRole ? fixtureManagerId : fixtureCustomerId,
      role: managerRole ? 'manager' : 'customer',
      generation: generation,
    );
  }

  void selectScreen(String value) {
    if (value != 'MH07' && value != 'MH08') {
      throw ArgumentError.value(value, 'screen');
    }
    if (value == screen) return;
    screen = value;
    _select(Mh08PreviewScenario.data);
  }

  void selectScenario(Mh08PreviewScenario value) {
    if (!managerActive &&
        !PreviewScenario.values.any(
          (scenario) => scenario.name == value.name,
        )) {
      throw ArgumentError.value(value, 'scenario');
    }
    if (value == scenario && _detailScope == null) return;
    _select(value);
  }

  void _select(Mh08PreviewScenario value) {
    mh09.reset();
    _detailScope = null;
    scenario = value;
    generation++;
    manager.setManagerScenario(value);
    if (!managerActive) {
      orders.setScenario(PreviewScenario.values.byName(value.name));
    }
    notifyListeners();
  }

  void selectMh09Scenario(Mh09PreviewScenario value) {
    final auth = {
      Mh09PreviewScenario.expired,
      Mh09PreviewScenario.unauthorized,
      Mh09PreviewScenario.unresolved,
      Mh09PreviewScenario.accountSwitch,
    }.contains(value);
    final sessionChange = auth || _detailScope != null;
    if (sessionChange) {
      mh09.reset(keepRoute: true);
      generation++;
      _detailScope = switch (value) {
        Mh09PreviewScenario.expired => SessionScope(
          userId: null,
          role: null,
          generation: generation,
        ),
        Mh09PreviewScenario.unresolved => SessionScope(
          userId: null,
          role: null,
          generation: generation,
          roleResolved: false,
        ),
        Mh09PreviewScenario.unauthorized => SessionScope(
          userId: fixtureCustomerId,
          role: 'customer',
          generation: generation,
        ),
        Mh09PreviewScenario.accountSwitch => SessionScope(
          userId: '20000000-0000-4000-8000-000000000099',
          role: 'manager',
          generation: generation,
        ),
        _ => null,
      };
      notifyListeners();
    }
    mh09.select(value, refresh: !sessionChange);
  }

  @override
  void dispose() {
    mh09.dispose();
    super.dispose();
  }
}

/// Delegates customer reads/actions unchanged; manager reads use their own data.
class Mh08PreviewRepository extends PreviewOrderRepository {
  Mh08PreviewRepository(this.environment);
  final Mh08PreviewEnvironment environment;
  final manager = Mh08ManagerRepository();

  @override
  Future<OrderPage> getManagerOrders(OrderQuery query) async {
    final scope = environment.scope;
    if (!scope.canReadPrivateData || scope.role != 'manager') {
      throw const AppFailure(code: AppFailure.forbiddenOrUnavailable);
    }
    final stamp = environment.mh09.projectionRevision;
    final page = await manager.getManagerOrders(query);
    if (scope != environment.scope) {
      throw const AppFailure(code: AppFailure.stateChanged);
    }
    return environment.mh09.projectPage(page, stamp);
  }

  @override
  Future<OrderDetails> getOrderDetails(String orderId) {
    if (!environment.managerActive) return super.getOrderDetails(orderId);
    final scope = environment.scope;
    if (!scope.canReadPrivateData || scope.role != 'manager') {
      return Future.error(
        const AppFailure(code: AppFailure.forbiddenOrUnavailable),
      );
    }
    return environment.mh09.read(orderId, manager.getOrderDetails);
  }
}
