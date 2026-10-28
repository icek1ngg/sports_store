import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/orders/data/models/order_dto.dart';
import 'package:sports_store/features/orders/domain/models/order_details.dart';
import 'package:sports_store/features/orders/domain/models/order_operation.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_order_details_page.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_action_footer.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_recipient_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_action_dialog.dart';

import 'mh09_page_test_support.dart';

const _foreignOrderId = '10000000-0000-4000-8000-000000000002';
const _secondManagerId = '20000000-0000-4000-8000-000000000005';

OrderDetails _foreignDetails() {
  final raw = fixtureOrderDetailsJson(
    timeline: [fixtureTimelineEntryJson(sourceEntityId: _foreignOrderId)],
  );
  raw['order'] = {
    ...Map<String, Object?>.from(raw['order']! as Map),
    'id': _foreignOrderId,
  };
  raw['items'] = (raw['items']! as List<Object?>)
      .map(
        (item) => {
          ...Map<String, Object?>.from(item! as Map),
          'order_id': _foreignOrderId,
        },
      )
      .toList();
  return OrderDetailsDto.fromJson(raw).domain;
}

void main() {
  testWidgets('shipper access is denied before any private read', (
    tester,
  ) async {
    final repository = Mh09PageOrders(
      () => mh09Details(
        buyer: {
          'id': fixtureCustomerId,
          'full_name': 'Thông tin riêng của người mua',
        },
      ),
    );
    await tester.pumpWidget(
      mh09PageHost(
        repository: repository,
        scope: const SessionScope(
          userId: fixtureShipperId,
          role: 'shipper',
          generation: 3,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Không thể truy cập dữ liệu'), findsOneWidget);
    expect(find.text('Thông tin riêng của người mua'), findsNothing);
    expect(repository.detailCalls, 0);
  });

  testWidgets('unresolved role remains loading without a private read', (
    tester,
  ) async {
    final repository = Mh09PageOrders(() => mh09Details());
    await tester.pumpWidget(
      mh09PageHost(
        repository: repository,
        scope: const SessionScope.unresolved(),
      ),
    );
    await tester.pump();

    expect(
      find.bySemanticsLabel('Đang xác nhận phiên đăng nhập'),
      findsOneWidget,
    );
    expect(find.text('Sản phẩm minh họa'), findsNothing);
    expect(repository.detailCalls, 0);
  });

  testWidgets('expired session makes zero detail reads', (tester) async {
    final repository = Mh09PageOrders(() => mh09Details());
    await tester.pumpWidget(
      mh09PageHost(
        repository: repository,
        scope: const SessionScope(userId: null, role: null, generation: 4),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Phiên đăng nhập đã hết hạn'), findsOneWidget);
    expect(find.textContaining(fixtureOrderId), findsNothing);
    expect(repository.detailCalls, 0);
  });

  testWidgets(
    'a valid foreign order aggregate fails closed without private projection',
    (tester) async {
      final repository = Mh09PageOrders(() => _foreignDetails());
      await tester.pumpWidget(mh09PageHost(repository: repository));
      await tester.pumpAndSettle();

      expect(
        find.text('Dữ liệu chưa thể hiển thị. Vui lòng làm mới.'),
        findsOneWidget,
      );
      expect(find.text(_foreignOrderId), findsNothing);
      expect(find.text('Sản phẩm minh họa'), findsNothing);
      expect(repository.detailCalls, 1);
    },
  );

  testWidgets('network failure retry reloads and renders the accepted detail', (
    tester,
  ) async {
    var attempts = 0;
    final details = mh09Details(
      buyer: {
        'id': fixtureCustomerId,
        'full_name': 'Người mua sau lần thử lại',
      },
    );
    final repository = Mh09PageOrders(() {
      attempts++;
      if (attempts == 1) {
        throw const AppFailure(code: AppFailure.network);
      }
      return details;
    });
    await tester.pumpWidget(mh09PageHost(repository: repository));
    await tester.pumpAndSettle();

    expect(
      find.text('Không thể kết nối. Kiểm tra mạng và thử lại.'),
      findsOneWidget,
    );
    expect(find.text('Thử lại'), findsOneWidget);
    expect(repository.detailCalls, 1);

    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();

    expect(repository.detailCalls, 2);
    expect(find.text('Người mua sau lần thử lại'), findsOneWidget);
    expect(find.text('Sản phẩm minh họa'), findsOneWidget);
    expect(find.text(fixtureOrderId), findsOneWidget);
  });

  testWidgets(
    'manager A to manager B cannot let a late read restore manager A private data',
    (tester) async {
      final oldPending = Completer<OrderDetails>();
      final oldDetails = mh09Details(
        buyer: {
          'id': fixtureCustomerId,
          'full_name': 'Người mua của manager A',
        },
      );
      final freshB = mh09Details(
        buyer: {
          'id': fixtureCustomerId,
          'full_name': 'Người mua của manager B',
        },
      );
      var calls = 0;
      final repository = Mh09PageOrders(() {
        calls++;
        return calls == 1 ? oldPending.future : freshB;
      });

      await tester.pumpWidget(
        mh09PageHost(repository: repository, scope: mh09ManagerScope),
      );
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ManagerOrderDetailsPage)),
      );
      expect(repository.detailCalls, 1);

      await tester.pumpWidget(
        mh09PageHost(
          repository: repository,
          scope: const SessionScope(
            userId: _secondManagerId,
            role: 'manager',
            generation: 5,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        ProviderScope.containerOf(tester.element(find.byType(MaterialApp))),
        same(container),
      );
      expect(repository.detailCalls, 2);
      expect(find.text('Người mua của manager B'), findsOneWidget);
      expect(find.text('Người mua của manager A'), findsNothing);

      oldPending.complete(oldDetails);
      await tester.pumpAndSettle();

      expect(find.text('Người mua của manager B'), findsOneWidget);
      expect(find.text('Người mua của manager A'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'role and account switch revokes a reject dialog and clears its private fields',
    (tester) async {
      final reason = 'Lý do riêng của manager A';
      var callbackCount = 0;
      final repository = Mh09PageOrders(
        () => mh09Details(capabilities: mh09Capabilities(reject: true)),
      );
      await tester.pumpWidget(
        mh09PageHost(
          repository: repository,
          onCallRecipient: (_) => callbackCount++,
        ),
      );
      await tester.pumpAndSettle();
      final oldRecipient = tester.widget<Mh09RecipientSection>(
        find.byType(Mh09RecipientSection),
      );
      final oldFooter = tester.widget<Mh09ActionFooter>(
        find.byType(Mh09ActionFooter),
      );
      final oldCall = oldRecipient.onCall;
      final oldAction = oldFooter.onAction;
      await tester.tap(find.byKey(const ValueKey('mh09-action-reject')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('order-action-reason')),
        reason,
      );
      expect(find.text(reason), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ManagerOrderDetailsPage)),
      );
      await tester.pumpWidget(
        mh09PageHost(
          repository: repository,
          scope: const SessionScope(
            userId: fixtureCustomerId,
            role: 'customer',
            generation: 6,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        ProviderScope.containerOf(tester.element(find.byType(MaterialApp))),
        same(container),
      );
      expect(find.text('Không thể tiếp tục thao tác'), findsOneWidget);
      expect(find.byKey(const ValueKey('order-action-submit')), findsNothing);
      expect(find.byKey(const ValueKey('order-action-reason')), findsNothing);
      expect(find.text(reason), findsNothing);
      expect(find.text(fixtureOrderId), findsNothing);

      oldCall?.call();
      oldAction?.call(OrderOperation.reject);
      await tester.pump();
      expect(callbackCount, 0);
      expect(find.byType(OrderActionDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
