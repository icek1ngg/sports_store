import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/orders/data/models/order_dto.dart';
import 'package:sports_store/features/orders/data/repositories/secure_pending_order_command_store.dart';
import 'package:sports_store/features/orders/domain/models/order_command.dart';
import 'package:sports_store/features/orders/domain/models/order_mutation_receipt.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/domain/models/operation_result.dart';
import 'package:sports_store/features/orders/domain/repositories/order_repository.dart';
import 'package:sports_store/features/orders/presentation/view_models/order_command_controller.dart';

import '../../../fixtures/order_notification_fixtures.dart';

class _Repository implements OrderRepository {
  late Future<OrderMutationReceipt> Function(StableOrderCommand) send;
  OperationResult lookup = const OperationResult.notFound();
  int lookups = 0;
  @override
  Future<OrderMutationReceipt> cancelCustomer(StableOrderCommand command) =>
      send(command);
  @override
  Future<OperationResult> getOperationResult({
    required String requestId,
    required String orderId,
    required OrderOperation operation,
  }) async {
    lookups++;
    return lookup;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const original = SessionScope(
    userId: fixtureCustomerId,
    role: 'customer',
    generation: 1,
  );
  late SessionScope scope;
  late SecurePendingOrderCommandStore store;
  late _Repository repository;
  late OrderCommandController controller;
  final command = StableOrderCommand(
    orderId: fixtureOrderId,
    requestId: fixtureMutationRequestId,
    operation: OrderOperation.customerCancel,
  );
  final receipt = OrderMutationReceiptDto.fromJson(
    fixtureMutationReceiptJson(
      operation: 'customer_cancel',
      status: 'cancelled',
    ),
  ).domain;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    scope = original;
    store = SecurePendingOrderCommandStore(
      scope: original,
      readSession: () => scope,
    );
    repository = _Repository();
    controller = OrderCommandController(
      repository: repository,
      store: store,
      scope: original,
      readSession: () => scope,
    );
  });

  test('lookup-only recovery retains unknown key and retires only final failure before new intent', () async {
    await store.save(command);
    var sends = 0;
    repository.send = (next) async {
      sends++;
      final json = fixtureMutationReceiptJson(
        operation: 'customer_cancel',
        status: 'cancelled',
      );
      json['request_id'] = next.requestId;
      return OrderMutationReceiptDto.fromJson(json).domain;
    };
    expect((await controller.resolve(command)).isNotFound, isTrue);
    expect(sends, 0);
    expect((await store.list()).single.requestId, command.requestId);
    repository.lookup = const OperationResult.failed(
      AppFailure(code: AppFailure.stateChanged),
    );
    expect((await controller.resolve(command)).isFailed, isTrue);
    expect(await store.list(), isEmpty);
    expect(sends, 0);
    final next = StableOrderCommand(
      orderId: command.orderId,
      requestId: '90000000-0000-4000-8000-000000000999',
      operation: command.operation,
    );
    expect((await controller.execute(next)).requestId, next.requestId);
    expect(sends, 1);
  });

  test(
    'protected pending saved before send, removed only after canonical ACK',
    () async {
      repository.send = (value) async {
        expect((await store.list()).single.requestId, value.requestId);
        return receipt;
      };
      expect((await controller.execute(command)).requestId, command.requestId);
      expect(await store.list(), isEmpty);
    },
  );

  test(
    'unknown outcome survives restart; lookup commits without another mutation',
    () async {
      var sends = 0;
      repository.send = (_) async {
        sends++;
        throw const AppFailure(
          code: AppFailure.outcomeUnknownCode,
          outcomeUnknown: true,
        );
      };
      await expectLater(
        controller.execute(command),
        throwsA(isA<AppFailure>()),
      );
      expect((await store.list()).single.requestId, command.requestId);
      repository.lookup = OperationResult.committed(receipt);
      final restarted = OrderCommandController(
        repository: repository,
        store: SecurePendingOrderCommandStore(
          scope: original,
          readSession: () => scope,
        ),
        scope: original,
        readSession: () => scope,
      );
      await restarted.execute(command);
      expect(sends, 1);
      expect(repository.lookups, 1);
      expect(await store.list(), isEmpty);
    },
  );

  test(
    'not_found retries original key; never a new key from reopened dialog',
    () async {
      await store.save(command);
      repository.send = (value) async {
        expect(value.requestId, command.requestId);
        return receipt;
      };
      await controller.execute(
        StableOrderCommand(
          orderId: fixtureOrderId,
          requestId: fixtureEventId,
          operation: OrderOperation.customerCancel,
        ),
      );
      expect(repository.lookups, 1);
    },
  );

  test(
    'session change rejects late ACK and preserves old account pending',
    () async {
      final gate = Completer<OrderMutationReceipt>();
      final sent = Completer<void>();
      repository.send = (_) {
        sent.complete();
        return gate.future;
      };
      final pending = controller.execute(command);
      final assertion = expectLater(pending, throwsA(isA<AppFailure>()));
      await sent.future;
      scope = const SessionScope(
        userId: fixtureManagerId,
        role: 'manager',
        generation: 2,
      );
      gate.complete(receipt);
      await assertion;
      await expectLater(store.list(), throwsA(isA<AppFailure>()));
      scope = original;
      expect((await store.list()).single.requestId, command.requestId);
      final foreignStore = SecurePendingOrderCommandStore(
        scope: const SessionScope(
          userId: fixtureManagerId,
          role: 'manager',
          generation: 2,
        ),
        readSession: () => scope,
      );
      await expectLater(foreignStore.list(), throwsA(isA<AppFailure>()));
    },
  );

  test('duplicate send while in flight fails closed', () async {
    final gate = Completer<OrderMutationReceipt>();
    final sent = Completer<void>();
    repository.send = (_) {
      sent.complete();
      return gate.future;
    };
    final first = controller.execute(command);
    await sent.future;
    await expectLater(controller.execute(command), throwsA(isA<AppFailure>()));
    gate.complete(receipt);
    await first;
  });

  test('fingerprint conflict does not replace saved intent', () async {
    await store.save(command);
    await expectLater(
      store.save(
        StableOrderCommand(
          orderId: fixtureOrderId,
          requestId: fixtureMutationRequestId,
          operation: OrderOperation.confirm,
        ),
      ),
      throwsA(isA<AppFailure>()),
    );
    expect(
      (await store.list()).single.operation,
      OrderOperation.customerCancel,
    );
  });

  test('corrupt protected data retained and never submitted', () async {
    final key = 'sports_store.orders.pending.v1.$fixtureCustomerId';
    FlutterSecureStorage.setMockInitialValues({key: 'broken'});
    await expectLater(controller.execute(command), throwsA(isA<AppFailure>()));
    expect(await const FlutterSecureStorage().read(key: key), 'broken');
  });

  test('multiple store instances serialize one protected namespace', () async {
    final other = SecurePendingOrderCommandStore(
      scope: original,
      readSession: () => scope,
    );
    final second = StableOrderCommand(
      orderId: fixtureEventId,
      requestId: fixtureEventId,
      operation: OrderOperation.customerCancel,
    );
    await Future.wait([store.save(command), other.save(second)]);
    expect((await store.list()).map((c) => c.requestId).toSet(), {
      command.requestId,
      second.requestId,
    });
  });

  test(
    'restored terminal failure removes pending without re-execution',
    () async {
      await store.save(command);
      repository.lookup = const OperationResult.failed(
        AppFailure(code: AppFailure.cancellationNotAllowed),
      );
      await expectLater(
        controller.execute(command),
        throwsA(isA<AppFailure>()),
      );
      expect(repository.lookups, 1);
      expect(await store.list(), isEmpty);
    },
  );

  test('startup recovery is lookup only and retains not_found', () async {
    await store.save(command);
    expect((await controller.recoverPending()).single.isNotFound, isTrue);
    expect((await store.list()).single.requestId, command.requestId);
    repository.lookup = OperationResult.committed(receipt);
    expect((await controller.recoverPending()).single.isCommitted, isTrue);
    expect(await store.list(), isEmpty);
  });

  test('changed intent remains unknown while old key not_found', () async {
    await store.save(command);
    await expectLater(
      controller.execute(
        StableOrderCommand(
          orderId: fixtureOrderId,
          requestId: fixtureEventId,
          operation: OrderOperation.confirm,
        ),
      ),
      throwsA(isA<AppFailure>()),
    );
    expect((await store.list()).single.requestId, command.requestId);
    expect(repository.lookups, 1);
  });
}
