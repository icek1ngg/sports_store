import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/features/orders/domain/models/order_details.dart';
import 'package:sports_store/features/orders/domain/models/order_query.dart';

import '../../tool/ui_preview/mh08_preview_environment.dart';
import '../../tool/ui_preview/mh09_preview_details.dart';
import '../../tool/ui_preview/mh09_preview_scenario.dart';

void main() {
  for (final scene in [
    Mh09PreviewScenario.expired,
    Mh09PreviewScenario.unauthorized,
    Mh09PreviewScenario.unresolved,
    Mh09PreviewScenario.accountSwitch,
  ]) {
    test(
      'canonical inflight manager head rejects scope change to ${scene.name}',
      () async {
        final env = Mh08PreviewEnvironment()..selectScreen('MH08');
        final old = env.orders.getManagerOrders(OrderQuery());
        final rejected = expectLater(
          old,
          throwsA(
            isA<AppFailure>().having(
              (e) => e.code,
              'code',
              AppFailure.stateChanged,
            ),
          ),
        );
        env.selectMh09Scenario(scene);
        await rejected;
        if (scene == Mh09PreviewScenario.accountSwitch) {
          expect(
            (await env.orders.getManagerOrders(OrderQuery())).totalCount,
            10,
          );
        } else {
          final reads = env.manager.managerReads.length;
          await expectLater(
            env.orders.getManagerOrders(OrderQuery()),
            throwsA(isA<AppFailure>()),
          );
          expect(env.manager.managerReads.length, reads);
        }
        env.dispose();
      },
    );
  }

  test(
    'denied owner never materializes a seed or starts detail transport',
    () async {
      final env = Mh08PreviewEnvironment();
      final base = env.manager.canonicalDetails(
        env.manager.summaries.first.order.id,
      );
      var lookups = 0;
      var transports = 0;
      final controller = Mh09PreviewDetails((_) {
        lookups++;
        return base;
      }, canRead: () => false);
      controller.open(base.order.id);
      controller.select(Mh09PreviewScenario.large);
      await expectLater(
        controller.read(base.order.id, (_) async {
          transports++;
          return base;
        }),
        throwsA(isA<AppFailure>()),
      );
      expect(lookups, 0);
      expect(transports, 0);
      expect(controller.activeOrderId, isNull);
      controller.dispose();
      env.dispose();
    },
  );

  for (final dispose in [false, true]) {
    test(
      'base loader completing after ${dispose ? 'dispose' : 'reset'} cannot create a held gate',
      () async {
        final env = Mh08PreviewEnvironment()..selectScreen('MH08');
        final id = env.manager.summaries.first.order.id;
        final base = env.manager.canonicalDetails(id);
        final controller = env.mh09..open(id);
        controller.holdLoading = true;
        controller.select(Mh09PreviewScenario.loading);
        final gate = Completer<OrderDetails>();
        final read = controller.read(id, (_) => gate.future);
        final rejected = expectLater(
          read,
          throwsA(
            isA<AppFailure>().having(
              (e) => e.code,
              'code',
              AppFailure.stateChanged,
            ),
          ),
        );
        if (dispose) {
          env.dispose();
        } else {
          controller.reset();
        }
        gate.complete(base);
        await rejected;
        expect(controller.holdLoading, isFalse);
        if (!dispose) {
          controller.open(id);
          final current = await controller.read(id, (_) async => base);
          expect(current.order, same(base.order));
          expect(current.items, orderedEquals(base.items));
          env.dispose();
        }
      },
    );
  }

  test('default list remains canonical ten records, page three and cursors unchanged', () async {
    final env = Mh08PreviewEnvironment()..selectScreen('MH08');
    try {
      final page = await env.orders.getManagerOrders(OrderQuery());
      expect(page.totalCount, 10);
      expect(page.items, hasLength(3));
      expect(page.nextCursor, isNotNull);
      final id = page.items.first.order.id;
      env.mh09.open(id);
      env.selectMh09Scenario(Mh09PreviewScenario.large);
      final projected = await env.orders.getManagerOrders(OrderQuery());
      final detail = await env.orders.getOrderDetails(id);
      expect(projected.items.first.order, same(detail.order));
      expect(projected.items.first.itemLineCount, detail.items.length);
      expect(projected.items.first.itemPreview.first, same(detail.items.first));
      expect(projected.totalCount, page.totalCount);
      expect(projected.statusCounts, page.statusCounts);
      expect(projected.nextCursor, page.nextCursor);
      expect(projected.asOf, page.asOf);
      env.mh09.reset();
      final restored = await env.orders.getManagerOrders(OrderQuery());
      expect(
        restored.items.first.itemLineCount,
        page.items.first.itemLineCount,
      );
      final next = await env.orders.getManagerOrders(
        OrderQuery(cursor: page.nextCursor),
      );
      expect(next.items, hasLength(3));
      expect(
        next.items
            .map((s) => s.order.id)
            .toSet()
            .intersection(page.items.map((s) => s.order.id).toSet()),
        isEmpty,
      );
    } finally {
      env.dispose();
    }
  });

  test('inflight head cannot publish a conflicting fixture world', () async {
    final env = Mh08PreviewEnvironment()..selectScreen('MH08');
    try {
      env.mh09.open(env.manager.summaries.first.order.id);
      final oldHead = env.orders.getManagerOrders(OrderQuery());
      final rejected = expectLater(
        oldHead,
        throwsA(
          isA<AppFailure>().having(
            (e) => e.code,
            'code',
            AppFailure.stateChanged,
          ),
        ),
      );
      env.selectMh09Scenario(Mh09PreviewScenario.large);
      await rejected;
      final fresh = await env.orders.getManagerOrders(OrderQuery());
      expect(fresh.items.first.itemLineCount, 40);
    } finally {
      env.dispose();
    }
  });

  test(
    'old account detail completion fails closed after scope invalidation',
    () async {
      final env = Mh08PreviewEnvironment()..selectScreen('MH08');
      try {
        final id = env.manager.summaries.first.order.id;
        env.mh09.open(id);
        env.selectMh09Scenario(Mh09PreviewScenario.large);
        final oldWorld = await env.orders.getOrderDetails(id);
        final gate = Completer<OrderDetails>();
        final oldRead = env.mh09.read(id, (_) => gate.future);
        final rejected = expectLater(
          oldRead,
          throwsA(
            isA<AppFailure>().having(
              (e) => e.code,
              'code',
              AppFailure.stateChanged,
            ),
          ),
        );
        final oldScope = env.scope;
        env.selectMh09Scenario(Mh09PreviewScenario.accountSwitch);
        expect(env.scope.userId, isNot(oldScope.userId));
        expect(env.scope.generation, greaterThan(oldScope.generation));
        gate.complete(oldWorld);
        await rejected;
        final current = await env.orders.getOrderDetails(id);
        expect(current.items.length, isNot(40));
        expect(current.order.id, id);
      } finally {
        env.dispose();
      }
    },
  );
}
