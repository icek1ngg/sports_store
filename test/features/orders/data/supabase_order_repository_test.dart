import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/orders/data/repositories/supabase_order_repository.dart';
import 'package:sports_store/features/orders/domain/models/order_command.dart';
import 'package:sports_store/features/orders/domain/models/order_query.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../fixtures/order_notification_fixtures.dart';
import '../../support/operational_supabase_fixture.dart';

Matcher fails(String code) =>
    throwsA(isA<AppFailure>().having((failure) => failure.code, 'code', code));

Object envelope(Object? data) => {'ok': true, 'data': data, 'error': null};

void main() {
  late SupabaseClient client;
  late SupabaseOrderRepository repository;
  late SessionScope scope;
  late Future<http.Response> Function(http.Request) handle;
  final requests = <http.Request>[];

  setUp(() async {
    requests.clear();
    scope = const SessionScope(
      userId: fixtureCustomerId,
      role: 'customer',
      generation: 1,
    );
    handle = (request) async =>
        jsonResponse(request, envelope(fixtureOrderListJson()));
    client = await fixtureClient((request) async {
      requests.add(request);
      return handle(request);
    }, userId: fixtureCustomerId);
    repository = SupabaseOrderRepository(
      client: client,
      readSession: () => scope,
    );
  });
  tearDown(() => client.dispose());

  test(
    'customer list decodes canonical aggregate and sends exact RPC query',
    () async {
      final query = OrderQuery(
        search: '  Áo %_  ',
        statuses: [OrderStatus.pendingConfirmation],
        limit: 2,
        cursor: 'opaque-server-cursor',
      );
      final page = await repository.getCustomerOrders(query);
      expect(page.items.single.order.id, fixtureOrderId);
      expect(page.totalCount, 1);
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/rest/v1/rpc/get_customer_orders');
      expect(jsonDecode(request.body), query.toRpcParams());
      expect(
        request.headers['Authorization'],
        'Bearer ${client.auth.currentSession!.accessToken}',
      );
    },
  );

  test(
    'manager list uses manager RPC and server data without local filtering',
    () async {
      await recoverFixtureSession(client, fixtureManagerId);
      scope = const SessionScope(
        userId: fixtureManagerId,
        role: 'manager',
        generation: 1,
      );
      expect((await repository.getManagerOrders(OrderQuery())).totalCount, 1);
      expect(requests.single.url.path, '/rest/v1/rpc/get_manager_orders');
      await expectLater(
        repository.getCustomerOrders(OrderQuery()),
        fails(AppFailure.forbiddenOrUnavailable),
      );
      expect(requests, hasLength(1));
    },
  );

  test('detail uses UUID RPC and canonical full item snapshot', () async {
    handle = (request) async =>
        jsonResponse(request, envelope(fixtureOrderDetailsJson()));
    final details = await repository.getOrderDetails(fixtureOrderId);
    expect(details.order.id, fixtureOrderId);
    expect(details.items.single.lineTotalVnd, details.order.subtotalVnd);
    expect(jsonDecode(requests.single.body), {'p_order_id': fixtureOrderId});
  });

  test('shipper and unresolved roles cannot call Orders aggregate', () async {
    scope = const SessionScope(
      userId: fixtureCustomerId,
      role: 'shipper',
      generation: 1,
    );
    await expectLater(
      repository.getOrderDetails(fixtureOrderId),
      fails(AppFailure.forbiddenOrUnavailable),
    );
    scope = const SessionScope.unresolved();
    await expectLater(
      repository.getCustomerOrders(OrderQuery()),
      fails(AppFailure.unauthenticated),
    );
    expect(requests, isEmpty);
  });

  test(
    'customer cannot request manager list despite forged metadata manager',
    () async {
      await expectLater(
        repository.getManagerOrders(OrderQuery()),
        fails(AppFailure.forbiddenOrUnavailable),
      );
      expect(requests, isEmpty);
    },
  );

  test('malformed detail UUID fails before HTTP', () async {
    await expectLater(
      repository.getOrderDetails('not-a-uuid'),
      fails(AppFailure.invalidArgument),
    );
    expect(requests, isEmpty);
  });

  test('SDK user mismatch fails closed before HTTP', () async {
    scope = const SessionScope(
      userId: fixtureManagerId,
      role: 'manager',
      generation: 2,
    );
    await expectLater(
      repository.getManagerOrders(OrderQuery()),
      fails(AppFailure.unauthenticated),
    );
    expect(requests, isEmpty);
  });

  for (final detail in [false, true]) {
    test(
      'foreign customer order rejected for ${detail ? 'detail' : 'list'}',
      () async {
        final data = detail
            ? fixtureOrderDetailsJson()
            : fixtureOrderListJson();
        final order = detail
            ? data['order'] as Map
            : ((data['items'] as List).single as Map)['order'] as Map;
        order['customer_id'] = fixtureManagerId;
        handle = (request) async => jsonResponse(request, envelope(data));
        await expectLater(
          detail
              ? repository.getOrderDetails(fixtureOrderId)
              : repository.getCustomerOrders(OrderQuery()),
          fails(AppFailure.unsupportedData),
        );
      },
    );
  }

  test(
    'session generation change rejects a late successful response',
    () async {
      final gate = Completer<http.Response>();
      handle = (_) => gate.future;
      final pending = repository.getCustomerOrders(OrderQuery());
      final assertion = expectLater(pending, fails(AppFailure.unauthenticated));
      await Future<void>.delayed(Duration.zero);
      scope = const SessionScope(
        userId: fixtureCustomerId,
        role: 'customer',
        generation: 2,
      );
      gate.complete(
        jsonResponse(requests.single, envelope(fixtureOrderListJson())),
      );
      await assertion;
    },
  );

  test(
    'token replacement rejects a late error from the previous session',
    () async {
      final gate = Completer<http.Response>();
      handle = (_) => gate.future;
      final pending = repository.getCustomerOrders(OrderQuery());
      final assertion = expectLater(pending, fails(AppFailure.unauthenticated));
      await Future<void>.delayed(Duration.zero);
      await recoverFixtureSession(client, fixtureManagerId);
      gate.complete(
        jsonResponse(requests.single, {'code': '42501'}, status: 403),
      );
      await assertion;
    },
  );

  for (final error in [
    (404, 'PGRST202', AppFailure.externalDependencyUnavailable),
    (401, 'PGRST301', AppFailure.unauthenticated),
    (403, '42501', AppFailure.forbiddenOrUnavailable),
    (400, '22023', AppFailure.invalidArgument),
    (503, 'PGRST000', AppFailure.network),
  ]) {
    test(
      'RPC ${error.$2} maps safely without an empty-success fallback',
      () async {
        handle = (request) async => jsonResponse(request, {
          'code': error.$2,
          'message': 'server diagnostic',
        }, status: error.$1);
        await expectLater(
          repository.getCustomerOrders(OrderQuery()),
          fails(error.$3),
        );
        expect(requests, hasLength(1));
      },
    );
  }

  for (final raw in [
    <Object?>[],
    {'ok': true, 'data': null, 'error': null},
    {
      'ok': true,
      'data': {'items': []},
      'error': null,
    },
  ]) {
    test('malformed aggregate fails closed: $raw', () async {
      handle = (request) async => jsonResponse(request, raw);
      await expectLater(
        repository.getCustomerOrders(OrderQuery()),
        fails(AppFailure.unsupportedData),
      );
    });
  }

  test('HTTP 200 business error remains a failure', () async {
    handle = (request) async => jsonResponse(request, {
      'ok': false,
      'data': null,
      'error': {
        'code': AppFailure.invalidCursor,
        'message_key': null,
        'retryable': false,
        'current_order': null,
      },
    });
    await expectLater(
      repository.getCustomerOrders(OrderQuery(cursor: 'bad-cursor')),
      fails(AppFailure.invalidCursor),
    );
  });

  test(
    'count disagreement does not publish an inconsistent snapshot',
    () async {
      final page = fixtureOrderListJson()..['total_count'] = 2;
      handle = (request) async => jsonResponse(request, envelope(page));
      await expectLater(
        repository.getCustomerOrders(OrderQuery()),
        fails(AppFailure.unsupportedData),
      );
    },
  );

  test(
    'status counters exclude selected filter while total includes it',
    () async {
      final page = fixtureOrderListJson();
      (page['status_counts'] as Map)['preparing'] = 5;
      handle = (request) async => jsonResponse(request, envelope(page));
      final result = await repository.getCustomerOrders(
        OrderQuery(statuses: [OrderStatus.pendingConfirmation]),
      );
      expect(result.totalCount, 1);
      expect(result.statusCounts[OrderStatus.preparing], 5);
    },
  );

  for (final invalidCounts in ['missing', 'extra']) {
    test('status counters reject $invalidCounts enum key', () async {
      final page = fixtureOrderListJson();
      final counts = page['status_counts'] as Map;
      if (invalidCounts == 'missing') {
        counts.remove('delivered');
      } else {
        counts['future_status'] = 0;
      }
      handle = (request) async => jsonResponse(request, envelope(page));
      await expectLater(
        repository.getCustomerOrders(OrderQuery()),
        fails(AppFailure.unsupportedData),
      );
    });
  }

  test(
    'selected status mismatch is not silently filtered client-side',
    () async {
      await expectLater(
        repository.getCustomerOrders(
          OrderQuery(statuses: [OrderStatus.delivered]),
        ),
        fails(AppFailure.unsupportedData),
      );
    },
  );

  test(
    'missing B2 RPC surfaces dependency failure, never fake receipt',
    () async {
      handle = (request) async => jsonResponse(request, {
        'code': 'PGRST202',
        'message': 'missing',
      }, status: 404);
      final command = StableOrderCommand(
        orderId: fixtureOrderId,
        requestId: fixtureMutationRequestId,
        operation: OrderOperation.customerCancel,
      );
      await expectLater(
        repository.cancelCustomer(command),
        fails(AppFailure.externalDependencyUnavailable),
      );
      expect(requests.single.url.path, '/rest/v1/rpc/cancel_customer_order');
    },
  );

  test(
    'customer mutation accepts only canonical receipt and omits empty reason',
    () async {
      handle = (request) async => jsonResponse(
        request,
        envelope(
          fixtureMutationReceiptJson(
            operation: 'customer_cancel',
            status: 'cancelled',
          ),
        ),
      );
      final command = StableOrderCommand(
        orderId: fixtureOrderId,
        requestId: fixtureMutationRequestId,
        operation: OrderOperation.customerCancel,
        reason: '',
      );
      final receipt = await repository.cancelCustomer(command);
      expect(receipt.order.status, OrderStatus.cancelled);
      expect(jsonDecode(requests.single.body), {
        'p_order_id': fixtureOrderId,
        'p_request_id': fixtureMutationRequestId,
      });
    },
  );

  test('wrong receipt identity leaves mutation outcome unknown', () async {
    final data = fixtureMutationReceiptJson(
      operation: 'customer_cancel',
      status: 'cancelled',
    );
    data['request_id'] = fixtureEventId;
    handle = (request) async => jsonResponse(request, envelope(data));
    await expectLater(
      repository.cancelCustomer(
        StableOrderCommand(
          orderId: fixtureOrderId,
          requestId: fixtureMutationRequestId,
          operation: OrderOperation.customerCancel,
        ),
      ),
      fails(AppFailure.outcomeUnknownCode),
    );
  });

  test(
    'mutation transport timeout is unknown and is never automatically retried',
    () async {
      handle = (_) async => throw TimeoutException('test');
      await expectLater(
        repository.cancelCustomer(
          StableOrderCommand(
            orderId: fixtureOrderId,
            requestId: fixtureMutationRequestId,
            operation: OrderOperation.customerCancel,
          ),
        ),
        fails(AppFailure.outcomeUnknownCode),
      );
      expect(requests, hasLength(1));
    },
  );

  test('late mutation ACK cannot cross a session generation', () async {
    final gate = Completer<http.Response>();
    http.Request? sent;
    handle = (request) {
      sent = request;
      return gate.future;
    };
    final pending = repository.cancelCustomer(
      StableOrderCommand(
        orderId: fixtureOrderId,
        requestId: fixtureMutationRequestId,
        operation: OrderOperation.customerCancel,
      ),
    );
    final assertion = expectLater(pending, fails(AppFailure.unauthenticated));
    await Future<void>.delayed(Duration.zero);
    scope = const SessionScope(
      userId: fixtureCustomerId,
      role: 'customer',
      generation: 2,
    );
    gate.complete(
      jsonResponse(
        sent!,
        envelope(
          fixtureMutationReceiptJson(
            operation: 'customer_cancel',
            status: 'cancelled',
          ),
        ),
      ),
    );
    await assertion;
    expect(requests, hasLength(1));
  });

  test('recovery not_found remains a union, not mutation success', () async {
    handle = (request) async => jsonResponse(
      request,
      envelope({'state': 'not_found', 'receipt': null, 'failure': null}),
    );
    expect(
      (await repository.getOperationResult(
        requestId: fixtureMutationRequestId,
        orderId: fixtureOrderId,
        operation: OrderOperation.customerCancel,
      )).isNotFound,
      isTrue,
    );
    expect(jsonDecode(requests.single.body), {
      'p_request_id': fixtureMutationRequestId,
      'p_order_id': fixtureOrderId,
      'p_operation': 'customer_cancel',
    });
  });

  test('manager command cannot be sent by customer and mismatched command is rejected', () async {
    final command = StableOrderCommand(
      orderId: fixtureOrderId,
      requestId: fixtureMutationRequestId,
      operation: OrderOperation.confirm,
    );
    await expectLater(
      repository.confirm(command),
      fails(AppFailure.forbiddenOrUnavailable),
    );
    await expectLater(
      repository.cancelCustomer(command),
      fails(AppFailure.invalidArgument),
    );
    expect(requests, isEmpty);
  });
}
