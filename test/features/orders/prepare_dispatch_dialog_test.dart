import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/orders/domain/repositories/manager_dispatch_repository.dart';
import 'package:sports_store/features/orders/presentation/view_models/manager_dispatch_providers.dart';
import 'package:sports_store/features/orders/presentation/widgets/prepare_dispatch_dialog.dart';

const scope = SessionScope(userId: 'manager', role: 'manager', generation: 1);

class FakeDispatch implements ManagerDispatchRepository {
  final calls = <({String order, String shipper, String request})>[];
  bool fail = false;
  bool shipperRemoved = false;
  @override
  Future<List<DispatchShipper>> loadShippers() async => shipperRemoved
      ? const []
      : const [DispatchShipper(id: 'shipper-1', name: 'Nguyễn Shipper')];
  @override
  Future<void> prepareAndAssign({
    required String orderId,
    required String shipperId,
    required String requestId,
  }) async {
    calls.add((order: orderId, shipper: shipperId, request: requestId));
    if (fail) throw const DispatchFailure('Mất kết nối', ambiguous: true);
  }
}

Future<void> pumpDialog(
  WidgetTester tester,
  FakeDispatch repository, {
  bool allowed = true,
  SessionScope currentScope = scope,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        featureSessionScopeProvider.overrideWithValue(currentScope),
        managerDispatchRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<DispatchDialogOutcome>(
                context: context,
                builder: (_) => PrepareDispatchDialog(
                  orderId: 'order-1',
                  scope: scope,
                  isStillAllowed: () => allowed,
                ),
              ),
              child: const Text('Mở'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Mở'));
  await tester.pumpAndSettle();
}

Future<void> chooseShipper(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Nguyễn Shipper').last);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'unresolved session retains pending intent only for the original account',
    () {
      final container = ProviderContainer(
        overrides: [featureSessionScopeProvider.overrideWithValue(scope)],
      );
      addTearDown(container.dispose);
      container
          .read(pendingDispatchStoreProvider)
          .remember('order', const PendingDispatch('request', 'shipper'));
      container.updateOverrides([
        featureSessionScopeProvider.overrideWithValue(
          const SessionScope.unresolved(),
        ),
      ]);
      expect(
        container.read(pendingDispatchStoreProvider).forOrder('order'),
        isNull,
      );
      container.updateOverrides([
        featureSessionScopeProvider.overrideWithValue(scope),
      ]);
      expect(
        container
            .read(pendingDispatchStoreProvider)
            .forOrder('order')
            ?.requestId,
        'request',
      );
      container.updateOverrides([
        featureSessionScopeProvider.overrideWithValue(
          const SessionScope(
            userId: 'other-manager',
            role: 'manager',
            generation: 2,
          ),
        ),
      ]);
      expect(
        container.read(pendingDispatchStoreProvider).forOrder('order'),
        isNull,
      );
    },
  );
  testWidgets('requires both shipper and explicit packing confirmation', (
    tester,
  ) async {
    final repository = FakeDispatch();
    await pumpDialog(tester, repository);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await chooseShipper(tester);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xác nhận bàn giao'));
    await tester.pumpAndSettle();
    expect(repository.calls.single.order, 'order-1');
    expect(repository.calls.single.shipper, 'shipper-1');
    expect(find.byType(PrepareDispatchDialog), findsNothing);
  });
  testWidgets('ambiguous retry retains request id and shipper', (tester) async {
    final repository = FakeDispatch()..fail = true;
    await pumpDialog(tester, repository);
    await chooseShipper(tester);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xác nhận bàn giao'));
    await tester.pumpAndSettle();
    expect(find.text('Mất kết nối'), findsOneWidget);
    await tester.tap(find.text('Thử lại cùng yêu cầu'));
    await tester.pumpAndSettle();
    expect(repository.calls, hasLength(2));
    expect(repository.calls[0], repository.calls[1]);
    repository.shipperRemoved = true;
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thử lại cùng yêu cầu'));
    await tester.pumpAndSettle();
    expect(repository.calls, hasLength(3));
    expect(repository.calls[0], repository.calls[2]);
  });
  testWidgets('revoked permission cannot submit', (tester) async {
    final repository = FakeDispatch();
    await pumpDialog(tester, repository, allowed: false);
    await chooseShipper(tester);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(repository.calls, isEmpty);
  });
  testWidgets('changed account cannot see shippers or submit', (tester) async {
    final repository = FakeDispatch();
    await pumpDialog(
      tester,
      repository,
      currentScope: const SessionScope(
        userId: 'other',
        role: 'customer',
        generation: 2,
      ),
    );
    expect(find.text('Nguyễn Shipper'), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(repository.calls, isEmpty);
  });
}
