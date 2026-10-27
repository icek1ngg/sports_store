import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/features/orders/domain/models/order_query.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';

import '../../tool/ui_preview/mh08_manager_data.dart';
import '../../tool/ui_preview/mh08_manager_repository.dart';

void main() {
  test(
    'manager fixture exposes all rows and status-independent counts',
    () async {
      final repository = Mh08ManagerRepository(pageSize: 20);

      final page = await repository.getManagerOrders(OrderQuery(limit: 20));

      expect(page.items, hasLength(10));
      expect(page.totalCount, 10);
      expect(page.nextCursor, isNull);
      expect(page.statusCounts[OrderStatus.pendingConfirmation], 2);
      expect(page.statusCounts[OrderStatus.delivering], 2);
      expect(page.statusCounts[OrderStatus.awaitingRedelivery], 1);
      expect(page.statusCounts.length, OrderStatus.values.length);
      expect(page.asOf, mh08PreviewAsOf);
    },
  );

  test(
    'search is limited to normalized account name and full order UUID',
    () async {
      final repository = Mh08ManagerRepository(pageSize: 20);
      final first = repository.summaries.first;

      final byUuid = await repository.getManagerOrders(
        OrderQuery(search: first.order.id.toUpperCase(), limit: 20),
      );
      final byAccount = await repository.getManagerOrders(
        OrderQuery(search: '  NGUYỄN   MINH ANH ', limit: 20),
      );
      final byProduct = await repository.getManagerOrders(
        OrderQuery(search: first.itemPreview.first.productName, limit: 20),
      );
      final byPartialUuid = await repository.getManagerOrders(
        OrderQuery(
          search: first.order.id.substring(first.order.id.length - 6),
          limit: 20,
        ),
      );

      expect(byUuid.items.single.order.id, first.order.id);
      expect(byAccount.items.single.order.id, first.order.id);
      expect(byProduct.items, isEmpty);
      expect(byProduct.totalCount, 0);
      expect(byPartialUuid.items, isEmpty);
    },
  );

  test('opaque cursor is bound to query and preserves page size', () async {
    final repository = Mh08ManagerRepository();
    final head = await repository.getManagerOrders(OrderQuery(limit: 3));
    final cursor = head.nextCursor;

    expect(cursor, isNotNull);
    expect(cursor, isNot(matches(RegExp(r'^\d+$'))));
    final next = await repository.getManagerOrders(
      OrderQuery(limit: 3, cursor: cursor),
    );
    expect(next.items, hasLength(3));
    expect(next.items.first.order.id, isNot(head.items.first.order.id));

    await expectLater(
      repository.getManagerOrders(OrderQuery(limit: 4, cursor: cursor)),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.code,
          'code',
          AppFailure.invalidCursor,
        ),
      ),
    );
  });

  test(
    'same scenario reset invalidates old cursors and pending scope',
    () async {
      final repository = Mh08ManagerRepository();
      final head = await repository.getManagerOrders(OrderQuery(limit: 3));
      repository.setManagerScenario(Mh08PreviewScenario.data);

      await expectLater(
        repository.getManagerOrders(
          OrderQuery(limit: 3, cursor: head.nextCursor),
        ),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.code,
            'code',
            AppFailure.invalidCursor,
          ),
        ),
      );
    },
  );

  test(
    'demo next-page failure is one-shot and keeps the cursor valid',
    () async {
      final repository = Mh08ManagerRepository();
      final head = await repository.getManagerOrders(OrderQuery(limit: 3));
      final query = OrderQuery(limit: 3, cursor: head.nextCursor);
      repository.failNextPageForDemo();

      await expectLater(
        repository.getManagerOrders(query),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.code,
            'code',
            AppFailure.network,
          ),
        ),
      );
      expect((await repository.getManagerOrders(query)).items, isNotEmpty);
    },
  );

  test('status filter changes rows while counts remain search-wide', () async {
    final repository = Mh08ManagerRepository(pageSize: 20);

    final page = await repository.getManagerOrders(
      OrderQuery(statuses: [OrderStatus.pendingConfirmation], limit: 20),
    );

    expect(page.items, hasLength(2));
    expect(page.totalCount, 2);
    expect(page.statusCounts[OrderStatus.delivered], 2);
    expect(page.statusCounts[OrderStatus.preparing], 1);
  });

  test('detail returns snapshots and typed failed-delivery warning', () async {
    final repository = Mh08ManagerRepository();
    final summary = repository.summaries.firstWhere(
      (item) => item.order.status == OrderStatus.awaitingRedelivery,
    );

    final detail = await repository.getOrderDetails(summary.order.id);

    expect(detail.order.id, summary.order.id);
    expect(detail.items, isNotEmpty);
    expect(detail.timeline, isNotEmpty);
    expect(summary.warnings.single.code, WarningCode.outboundFailure);
    expect(
      summary.deliverySummary?.latestAttempt?.result,
      DeliveryAttemptResult.failed,
    );
    expect(summary.codSummary?.status, CodStatus.uncollected);
    expect(summary.codSummary?.collectedAmountVnd, 0);
    expect(
      detail.timeline.every((entry) => !entry.occurredAt.isAfter(detail.asOf)),
      isTrue,
    );

    final delivered = repository.summaries.firstWhere(
      (item) => item.order.status == OrderStatus.delivered,
    );
    expect(delivered.codSummary?.status, CodStatus.collected);
    expect(delivered.codSummary?.collectedAt, delivered.order.deliveredAt);
    expect(delivered.codSummary?.receivedAmountVnd, 0);
    expect(
      !detail.deliverySummary!.latestAttempt!.occurredAt.isAfter(detail.asOf),
      isTrue,
    );
  });

  test(
    'scenario failures are typed and stale rejects the second read',
    () async {
      final repository = Mh08ManagerRepository();
      repository.setManagerScenario(Mh08PreviewScenario.stale);
      await repository.getManagerOrders(OrderQuery(limit: 3));

      await expectLater(
        repository.getManagerOrders(OrderQuery(limit: 3)),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.code,
            'code',
            AppFailure.network,
          ),
        ),
      );

      repository.setManagerScenario(Mh08PreviewScenario.unauthorized);
      await expectLater(
        repository.getManagerOrders(OrderQuery(limit: 3)),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.code,
            'code',
            AppFailure.forbiddenOrUnavailable,
          ),
        ),
      );
    },
  );
}
