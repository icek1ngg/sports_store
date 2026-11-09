import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/notifications/data/repositories/supabase_notification_target_resolver.dart';
import 'package:sports_store/features/notifications/domain/models/notification_target.dart';
import 'package:sports_store/features/orders/data/models/order_dto.dart';
import 'package:sports_store/features/orders/domain/models/order_details.dart';
import 'package:sports_store/features/orders/domain/repositories/order_repository.dart';

import 'notification_supabase_test_support.dart';

class _Orders implements OrderRepository {
  int reads = 0;
  Future<OrderDetails> Function() read = () async =>
      OrderDetailsDto.fromJson(fixtureOrderDetailsJson()).domain;
  @override
  Future<OrderDetails> getOrderDetails(String orderId) {
    expect(orderId, fixtureOrderId);
    reads++;
    return read();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late NotificationSupabaseHarness harness;
  late _Orders orders;
  late SupabaseNotificationTargetResolver resolver;
  setUp(() async {
    harness = NotificationSupabaseHarness();
    await harness.supplySession();
    orders = _Orders();
    resolver = SupabaseNotificationTargetResolver(
      client: harness.client,
      orders: orders,
      readSession: () => harness.scope,
    );
    harness.handle = (_) async => harness.rows(inboxRow(1));
  });
  tearDown(() => harness.dispose());

  for (final role in ['customer', 'manager']) {
    test(
      '$role resolves persisted order after fresh permission read',
      () async {
        harness.scope = SessionScope(
          userId: fixtureCustomerId,
          role: role,
          generation: 1,
        );
        final decision = await resolver.resolve(fixtureNotificationId);
        expect(decision.available, isTrue);
        expect(decision.entityId, fixtureOrderId);
        expect(
          decision.screen,
          role == 'manager'
              ? NotificationTargetScreen.managerOrder
              : NotificationTargetScreen.customerOrder,
        );
        expect(orders.reads, 1);
        expect(harness.requests.single.method, 'GET');
        expect(
          harness.requests.single.url.queryParameters['recipient_id'],
          'eq.$fixtureCustomerId',
        );
        expect(
          harness.requests.single.url.queryParameters['id'],
          'eq.$fixtureNotificationId',
        );
      },
    );
  }
  test('foreign recipient never reaches OrderRepository', () async {
    harness.handle = (_) async =>
        harness.rows(inboxRow(1, recipient: otherRecipient));
    expect((await resolver.resolve(fixtureNotificationId)).available, isFalse);
    expect(orders.reads, 0);
  });
  test('unsupported subject cannot be inferred from title or body', () async {
    harness.handle = (_) async => harness.rows({
      ...inboxRow(1),
      'subject_type': 'unknown',
      'title': 'Order $fixtureOrderId',
    });
    expect((await resolver.resolve(fixtureNotificationId)).available, isFalse);
    expect(orders.reads, 0);
  });
  test('missing row and malformed subject fail closed', () async {
    harness.handle = (_) async => harness.rows([]);
    expect((await resolver.resolve(fixtureNotificationId)).available, isFalse);
    harness.handle = (_) async =>
        harness.rows({...inboxRow(1), 'subject_id': 'not-uuid'});
    expect((await resolver.resolve(fixtureNotificationId)).available, isFalse);
    expect(orders.reads, 0);
  });
  test('target permission denial propagates without navigation', () async {
    orders.read = () async =>
        throw const AppFailure(code: AppFailure.forbiddenOrUnavailable);
    await expectLater(
      resolver.resolve(fixtureNotificationId),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.code,
          'code',
          AppFailure.forbiddenOrUnavailable,
        ),
      ),
    );
  });
  test(
    'account generation change during target read rejects late result',
    () async {
      orders.read = () async {
        harness.scope = const SessionScope.unresolved();
        return OrderDetailsDto.fromJson(fixtureOrderDetailsJson()).domain;
      };
      await expectLater(
        resolver.resolve(fixtureNotificationId),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.code,
            'code',
            AppFailure.unauthenticated,
          ),
        ),
      );
    },
  );
  test(
    'shipper and malformed notification ID do not issue target reads',
    () async {
      expect((await resolver.resolve('bad')).available, isFalse);
      harness.scope = const SessionScope(
        userId: fixtureCustomerId,
        role: 'shipper',
        generation: 1,
      );
      expect(
        (await resolver.resolve(fixtureNotificationId)).available,
        isFalse,
      );
      expect(harness.requests, isEmpty);
      expect(orders.reads, 0);
    },
  );
}
