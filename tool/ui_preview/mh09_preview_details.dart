import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/features/orders/domain/models/order_details.dart';
import 'package:sports_store/features/orders/domain/models/order_page.dart';

import 'mh09_preview_fixtures.dart';
import 'mh09_preview_scenario.dart';

/// Debug fixture world only. Production canonical state stays in Riverpod.
class Mh09PreviewDetails extends ChangeNotifier {
  Mh09PreviewDetails(this.canonicalDetails, {required this.canRead});
  final OrderDetails Function(String) canonicalDetails;
  final bool Function() canRead;
  Mh09PreviewScenario scenario = Mh09PreviewScenario.canonical;
  String? activeOrderId;
  OrderDetails? _world;
  int revision = 0;
  int _readNumber = 0;
  final reads = <String>[];
  final _pending = <Completer<void>>{};
  bool holdLoading = false;
  bool refreshRequested = true;

  int? get projectionRevision =>
      activeOrderId != null &&
          scenario != Mh09PreviewScenario.canonical &&
          _world != null
      ? revision
      : null;

  void open(String id) {
    reset();
    if (!canRead()) return;
    activeOrderId = id;
    _world = canonicalDetails(id);
  }

  void reset({bool keepRoute = false}) {
    revision++;
    _releasePending();
    _readNumber = 0;
    _world = null;
    holdLoading = false;
    refreshRequested = true;
    scenario = Mh09PreviewScenario.canonical;
    if (!keepRoute) activeOrderId = null;
  }

  void select(Mh09PreviewScenario value, {bool refresh = true}) {
    refreshRequested = refresh;
    revision++;
    _releasePending();
    scenario = value;
    _readNumber = 0;
    final id = activeOrderId;
    if (!canRead()) _world = null;
    if (id != null && canRead() && !_sessionScene(value)) {
      final transport = {
        Mh09PreviewScenario.loading,
        Mh09PreviewScenario.error,
        Mh09PreviewScenario.stale,
      }.contains(value);
      if (!transport || _world == null) {
        _world = Mh09PreviewFixtures.detail(canonicalDetails(id), value);
      }
    }
    notifyListeners();
  }

  static bool _sessionScene(Mh09PreviewScenario value) => {
    Mh09PreviewScenario.expired,
    Mh09PreviewScenario.unauthorized,
    Mh09PreviewScenario.unresolved,
    Mh09PreviewScenario.accountSwitch,
  }.contains(value);

  Future<OrderDetails> read(
    String id,
    Future<OrderDetails> Function(String) load,
  ) async {
    reads.add(id);
    final stamp = revision;
    final scene = id == activeOrderId
        ? scenario
        : Mh09PreviewScenario.canonical;
    final world = id == activeOrderId ? _world : null;
    final number = ++_readNumber;
    if (!canRead()) {
      throw const AppFailure(code: AppFailure.forbiddenOrUnavailable);
    }
    final base = await load(id);
    if (stamp != revision || !canRead()) {
      throw const AppFailure(code: AppFailure.stateChanged);
    }
    if (scene == Mh09PreviewScenario.loading) {
      if (holdLoading) {
        final pending = Completer<void>();
        _pending.add(pending);
        try {
          await pending.future;
        } finally {
          _pending.remove(pending);
        }
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
    }
    if (stamp != revision) {
      throw const AppFailure(code: AppFailure.stateChanged);
    }
    if (scene == Mh09PreviewScenario.stale ||
        (scene == Mh09PreviewScenario.error && number == 1)) {
      throw const AppFailure(code: AppFailure.network, retryable: true);
    }
    return world ?? base;
  }

  OrderPage projectPage(OrderPage page, int? stamp) {
    final current = projectionRevision;
    if (stamp != current && (stamp != null || current != null)) {
      throw const AppFailure(code: AppFailure.stateChanged);
    }
    final world = _world;
    if (current == null || world == null) return page;
    return OrderPage(
      items: page.items
          .map(
            (item) => item.order.id == world.order.id
                ? Mh09PreviewFixtures.summary(item, world)
                : item,
          )
          .toList(growable: false),
      nextCursor: page.nextCursor,
      totalCount: page.totalCount,
      statusCounts: page.statusCounts,
      asOf: page.asOf,
    );
  }

  void releaseLoading() {
    holdLoading = false;
    _releasePending();
  }

  void _releasePending() {
    for (final pending in _pending.toList()) {
      if (!pending.isCompleted) pending.complete();
    }
  }

  @override
  void dispose() {
    reset();
    super.dispose();
  }
}
