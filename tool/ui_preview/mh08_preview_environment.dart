import 'package:flutter/foundation.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/orders/domain/models/order_details.dart';
import 'package:sports_store/features/orders/domain/models/order_page.dart';
import 'package:sports_store/features/orders/domain/models/order_query.dart';

import '../../test/fixtures/order_notification_fixtures.dart';
import 'mh07_preview_data.dart';
import 'mh08_manager_repository.dart';

/// Only owner of the active demo screen/scenario/session generation.
class Mh08PreviewEnvironment extends ChangeNotifier {
  Mh08PreviewEnvironment() {
    orders = Mh08PreviewRepository(this);
  }

  late final Mh08PreviewRepository orders;
  String screen = 'MH07';
  Mh08PreviewScenario scenario = Mh08PreviewScenario.data;
  int generation = 1;
  bool get managerActive => screen == 'MH08';
  Mh08ManagerRepository get manager => orders.manager;

  SessionScope get scope {
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
    if (value == scenario) return;
    _select(value);
  }

  void _select(Mh08PreviewScenario value) {
    scenario = value;
    generation++;
    manager.setManagerScenario(value);
    if (!managerActive) {
      orders.setScenario(PreviewScenario.values.byName(value.name));
    }
    notifyListeners();
  }
}

/// Delegates customer reads/actions unchanged; manager reads use their own data.
class Mh08PreviewRepository extends PreviewOrderRepository {
  Mh08PreviewRepository(this.environment);
  final Mh08PreviewEnvironment environment;
  final manager = Mh08ManagerRepository();

  @override
  Future<OrderPage> getManagerOrders(OrderQuery query) =>
      manager.getManagerOrders(query);

  @override
  Future<OrderDetails> getOrderDetails(String orderId) =>
      environment.managerActive
      ? manager.getOrderDetails(orderId)
      : super.getOrderDetails(orderId);
}
