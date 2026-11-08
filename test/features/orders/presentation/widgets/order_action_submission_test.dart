import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/orders/data/models/order_dto.dart';
import 'package:sports_store/features/orders/domain/models/order_command.dart';
import 'package:sports_store/features/orders/domain/models/order_mutation_receipt.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/domain/models/operation_result.dart';
import 'package:sports_store/features/orders/domain/repositories/order_repository.dart';
import 'package:sports_store/features/orders/presentation/view_models/order_providers.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_action_dialog.dart';

import '../../../../fixtures/order_notification_fixtures.dart';

class _Commands implements OrderRepository {
  int sends = 0, lookups = 0;
  bool loseAck = false;
  OrderMutationReceipt? receipt;
  @override
  Future<OrderMutationReceipt> cancelCustomer(
    StableOrderCommand command,
  ) async {
    sends++;
    final json = fixtureMutationReceiptJson(
      operation: 'customer_cancel',
      status: 'cancelled',
    );
    json['request_id'] = command.requestId;
    receipt = OrderMutationReceiptDto.fromJson(json).domain;
    if (loseAck) {
      throw const AppFailure(
        code: AppFailure.outcomeUnknownCode,
        outcomeUnknown: true,
      );
    }
    return receipt!;
  }

  @override
  Future<OperationResult> getOperationResult({
    required String requestId,
    required String orderId,
    required OrderOperation operation,
  }) async {
    lookups++;
    return OperationResult.committed(receipt!);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final lost in [false, true]) {
    testWidgets('dialog production command composition; lost ACK=$lost', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({});
      const scope = SessionScope(
        userId: fixtureCustomerId,
        role: 'customer',
        generation: 1,
      );
      final repo = _Commands()..loseAck = lost;
      final container = ProviderContainer(
        overrides: [
          featureSessionScopeProvider.overrideWithValue(scope),
          orderRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => OrderActionDialog(
                      orderId: fixtureOrderId,
                      operation: OrderOperation.customerCancel,
                      isStillAllowed: () => true,
                      submittedScope: scope,
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('order-action-submit')));
      await tester.pumpAndSettle();
      expect(repo.sends, 1);
      if (lost) {
        expect(find.byType(OrderActionDialog), findsOneWidget);
        expect(
          await container.read(pendingOrderCommandStoreProvider).list(),
          hasLength(1),
        );
        await tester.tap(find.byKey(const ValueKey('order-action-submit')));
        await tester.pumpAndSettle();
        expect(repo.lookups, 1);
        expect(repo.sends, 1);
      }
      expect(find.byType(OrderActionDialog), findsNothing);
      expect(
        await container.read(pendingOrderCommandStoreProvider).list(),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
