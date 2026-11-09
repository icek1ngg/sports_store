import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/demo/data/local_demo_store.dart';
import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/features/notifications/domain/models/notification_query.dart';
import 'package:sports_store/features/orders/domain/models/order_command.dart';
import 'package:sports_store/features/orders/domain/models/order_query.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';

StableOrderCommand command(
  int order,
  int request,
  OrderOperation operation, {
  String? reason,
}) => StableOrderCommand(
  orderId: LocalDemoStore.orderId(order),
  requestId: '30000000-0000-4000-8000-${request.toString().padLeft(12, '0')}',
  operation: operation,
  reason: reason,
);

Matcher failure(String code) =>
    isA<AppFailure>().having((e) => e.code, 'code', code);

void main() {
  test(
    'seed details, counts, status filters, search and cursors agree',
    () async {
      final store = LocalDemoStore();
      final first = await store.orders.getCustomerOrders(OrderQuery(limit: 2));
      expect(first.totalCount, 9);
      expect(first.statusCounts[OrderStatus.pendingConfirmation], 3);
      final second = await store.orders.getCustomerOrders(
        OrderQuery(limit: 2, cursor: first.nextCursor),
      );
      expect(second.items.first.order.id, LocalDemoStore.orderId(3));
      final filtered = await store.orders.getCustomerOrders(
        OrderQuery(statuses: [OrderStatus.delivered]),
      );
      expect(filtered.items.single.order.status, OrderStatus.delivered);
      expect(filtered.statusCounts[OrderStatus.pendingConfirmation], 3);
      final search = await store.orders.getCustomerOrders(
        OrderQuery(search: LocalDemoStore.orderId(2)),
      );
      expect(search.items.single.order.id, LocalDemoStore.orderId(2));
      for (final item in (await store.orders.getCustomerOrders(
        OrderQuery(),
      )).items) {
        final details = await store.orders.getOrderDetails(item.order.id);
        expect(details.order, item.order);
        expect(
          details.items.fold<int>(0, (sum, item) => sum + item.lineTotalVnd),
          details.order.subtotalVnd,
        );
        if (details.codSummary != null) {
          expect(
            details.codSummary!.expectedAmountVnd,
            details.order.totalCodVnd,
          );
        }
        expect(details.timeline, isNotEmpty);
      }
      store.switchAccount(DemoAccount.customerC);
      await expectLater(
        store.orders.getCustomerOrders(
          OrderQuery(limit: 2, cursor: first.nextCursor),
        ),
        throwsA(failure(AppFailure.invalidCursor)),
      );
      expect(
        (await store.orders.getCustomerOrders(OrderQuery())).totalCount,
        2,
      );
      await expectLater(
        store.orders.getOrderDetails(LocalDemoStore.orderId(1)),
        throwsA(failure(AppFailure.forbiddenOrUnavailable)),
      );
      await expectLater(
        store.orders.getManagerOrders(OrderQuery()),
        throwsA(failure(AppFailure.forbiddenOrUnavailable)),
      );
    },
  );

  test('confirm replay and operation recovery are stable across later cancellation', () async {
    final store = LocalDemoStore(account: DemoAccount.managerB);
    final initialManagerCount = await store.notifications.getUnreadCount();
    final cmd = command(1, 1, OrderOperation.confirm);
    final first = await store.orders.confirm(cmd);
    expect(first.order.status, OrderStatus.preparing);
    final beforeReplay = await store.notifications.getUnreadCount();
    expect(beforeReplay, initialManagerCount);
    final replay = await store.orders.confirm(cmd);
    expect(replay.replayed, isTrue);
    expect(replay.eventId, first.eventId);
    expect(replay.committedAt, first.committedAt);
    expect(await store.notifications.getUnreadCount(), beforeReplay);
    await expectLater(
      store.orders.reject(command(1, 1, OrderOperation.reject, reason: 'Khác')),
      throwsA(failure(AppFailure.idempotencyConflict)),
    );
    await store.orders.cancelManager(
      command(1, 2, OrderOperation.managerCancel, reason: 'Dừng xử lý demo'),
    );
    expect(await store.notifications.getUnreadCount(), initialManagerCount);
    final recovered = await store.orders.getOperationResult(
      requestId: cmd.requestId,
      orderId: cmd.orderId,
      operation: cmd.operation,
    );
    expect(recovered.isCommitted, isTrue);
    expect(recovered.receipt!.order.status, OrderStatus.preparing);
    expect(recovered.receipt!.eventId, first.eventId);
    final details = await store.orders.getOrderDetails(cmd.orderId);
    expect(details.order.status, OrderStatus.cancelled);
    expect(
      details.timeline.where((e) => e.eventId == first.eventId),
      hasLength(1),
    );
    store.switchAccount(DemoAccount.customerA);
    final customerNotifications = await store.notifications.getPage(
      NotificationQuery(),
    );
    expect(
      customerNotifications.items.where(
        (item) => item.eventId == first.eventId,
      ),
      hasLength(1),
    );
    expect(
      (await store.orders.getOrderDetails(cmd.orderId)).order.status,
      OrderStatus.cancelled,
    );
    expect(
      (await store.orders.getOperationResult(
        requestId: cmd.requestId,
        orderId: cmd.orderId,
        operation: cmd.operation,
      )).isNotFound,
      isTrue,
    );
  });

  test(
    'reject and customer cancel release once; illegal transitions remain typed',
    () async {
      final store = LocalDemoStore();
      final cancel = command(1, 1, OrderOperation.customerCancel);
      final results = await Future.wait([
        store.orders.cancelCustomer(cancel),
        store.orders.cancelCustomer(cancel),
      ]);
      expect(results.where((r) => r.replayed), hasLength(1));
      expect(results.map((r) => r.eventId).toSet(), hasLength(1));
      await expectLater(
        store.orders.cancelCustomer(
          command(4, 2, OrderOperation.customerCancel),
        ),
        throwsA(failure(AppFailure.cancellationNotAllowed)),
      );
      await expectLater(
        store.orders.confirm(command(2, 3, OrderOperation.confirm)),
        throwsA(failure(AppFailure.forbiddenOrUnavailable)),
      );
      store.switchAccount(DemoAccount.managerB);
      final reject = command(
        2,
        4,
        OrderOperation.reject,
        reason: 'Không còn hàng phù hợp',
      );
      await store.orders.reject(reject);
      await store.orders.reject(reject);
      expect(
        (await store.orders.getOrderDetails(reject.orderId)).timeline
            .where((e) => e.eventKind == 'order_rejected'),
        hasLength(1),
      );
      await expectLater(
        store.orders.confirm(command(2, 5, OrderOperation.confirm)),
        throwsA(failure(AppFailure.stateChanged)),
      );
      await expectLater(
        store.orders.cancelManager(
          command(6, 6, OrderOperation.managerCancel, reason: 'Dừng'),
        ),
        throwsA(failure(AppFailure.cancellationNotAllowed)),
      );
      final assigned = await store.orders.getOrderDetails(
        LocalDemoStore.orderId(5),
      );
      expect(assigned.deliverySummary!.taskStatus, DeliveryTaskStatus.assigned);
      expect(assigned.deliverySummary!.acceptedAt, isNull);
      expect(assigned.deliverySummary!.startedAt, isNull);
      expect(assigned.order.deliveryAttemptCount, 0);
      expect(assigned.capabilities.canCancelExceptional, isFalse);
      await expectLater(
        store.orders.cancelManager(
          command(5, 7, OrderOperation.managerCancel, reason: 'Dừng'),
        ),
        throwsA(failure(AppFailure.cancellationNotAllowed)),
      );
      final preparing = await store.orders.cancelManager(
        command(4, 8, OrderOperation.managerCancel, reason: 'Dừng'),
      );
      expect(preparing.order.status, OrderStatus.cancelled);
      expect(
        (await store.orders.getOrderDetails(preparing.order.id)).codSummary,
        isNull,
      );
      final delivered = await store.orders.getOrderDetails(
        LocalDemoStore.orderId(7),
      );
      expect(delivered.order.status, OrderStatus.delivered);
      expect(delivered.codSummary!.status, CodStatus.collected);
    },
  );

  test(
    'concurrent competing confirmation and cancellation have one winner',
    () async {
      final store = LocalDemoStore(account: DemoAccount.managerB);
      final outcomes = await Future.wait([
        store.orders
            .confirm(command(1, 1, OrderOperation.confirm))
            .then<Object>((r) => r)
            .catchError((Object e) => e),
        store.orders
            .reject(command(1, 2, OrderOperation.reject, reason: 'Từ chối'))
            .then<Object>((r) => r)
            .catchError((Object e) => e),
      ]);
      expect(outcomes.whereType<AppFailure>(), hasLength(1));
      expect(
        outcomes.whereType<AppFailure>().single.code,
        AppFailure.stateChanged,
      );
    },
  );

  test('recipient reads use canonical time, exact count, and current target permission', () async {
    final store = LocalDemoStore();
    final page = await store.notifications.getPage(NotificationQuery());
    final unread = page.items.firstWhere((n) => !n.isRead);
    final count = await store.notifications.getUnreadCount();
    final read = await store.notifications.markRead(unread.id);
    final replay = await store.notifications.markRead(unread.id);
    expect(read.readAt, replay.readAt);
    expect(await store.notifications.getUnreadCount(), count - 1);
    expect(
      (await store.notifications.getPage(
        NotificationQuery(filter: NotificationFilter.unread),
      )).items.any((n) => n.id == unread.id),
      isFalse,
    );
    expect((await store.targetResolver.resolve(unread.id)).available, isTrue);
    store.switchAccount(DemoAccount.customerC);
    await expectLater(
      store.notifications.markRead(unread.id),
      throwsA(failure(AppFailure.forbiddenOrUnavailable)),
    );
    expect((await store.targetResolver.resolve(unread.id)).available, isFalse);
    store.switchAccount(DemoAccount.customerA);
    expect((await store.notifications.markRead(unread.id)).readAt, read.readAt);
  });

  test('session switch and reset fence in-flight data, mutation and pending storage', () async {
    final store = LocalDemoStore();
    final pending = store.pendingCommands;
    final cmd = command(1, 1, OrderOperation.customerCancel);
    await pending.save(cmd);
    final read = store.orders.getCustomerOrders(OrderQuery());
    final mutation = store.orders.cancelCustomer(cmd);
    final notification = store.notifications.getPage(NotificationQuery());
    final assertions = [
      expectLater(read, throwsA(failure(AppFailure.unauthenticated))),
      expectLater(mutation, throwsA(failure(AppFailure.unauthenticated))),
      expectLater(notification, throwsA(failure(AppFailure.unauthenticated))),
    ];
    store.switchAccount(DemoAccount.customerC);
    await Future.wait(assertions);
    expect(await store.pendingCommands.list(), isEmpty);
    await expectLater(
      pending.list(),
      throwsA(failure(AppFailure.unauthenticated)),
    );
    store.switchAccount(DemoAccount.customerA);
    expect(await store.pendingCommands.list(), hasLength(1));
    expect(
      (await store.orders.getOrderDetails(cmd.orderId)).order.status,
      OrderStatus.pendingConfirmation,
    );
    await store.orders.cancelCustomer(cmd);
    final generation = store.session.generation;
    store.reset();
    expect(store.account, DemoAccount.customerA);
    expect(store.session.generation, greaterThan(generation));
    expect(await store.pendingCommands.list(), isEmpty);
    expect(
      (await store.orders.getOrderDetails(cmd.orderId)).order.status,
      OrderStatus.pendingConfirmation,
    );
  });
}
