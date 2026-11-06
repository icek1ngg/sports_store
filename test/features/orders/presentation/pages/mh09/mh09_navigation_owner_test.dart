import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/domain/models/order_details.dart';
import 'package:sports_store/features/orders/domain/models/order_operation.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_order_details_page.dart';
import 'package:sports_store/features/orders/presentation/pages/mh09/mh09_detail_body.dart';
import 'package:sports_store/features/orders/presentation/pages/mh09/mh09_detail_content.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_action_footer.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_header.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_recipient_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_action_dialog.dart';

import 'mh09_page_test_support.dart';

void main() {
  testWidgets(
    'retained destinations fail closed when parent removes callbacks',
    (tester) async {
      var dispatches = 0;
      final repository = Mh09PageOrders(
        () => mh09Details(
          codSummary: mh09CodSummary(),
          returnSummaries: [mh09ReturnSummary()],
        ),
      );
      await tester.pumpWidget(
        mh09PageHost(
          repository: repository,
          onCallRecipient: (_) => dispatches++,
          onOpenChat: (_) => dispatches++,
          onOpenCod: (_) => dispatches++,
          onOpenReturn: (_) => dispatches++,
        ),
      );
      await tester.pumpAndSettle();
      final owner = tester.element(find.byType(Mh09DetailContent));
      final recipient = tester.widget<Mh09RecipientSection>(
        find.byType(Mh09RecipientSection),
      );
      final body = tester.widget<Mh09DetailBody>(find.byType(Mh09DetailBody));
      await tester.pumpWidget(mh09PageHost(repository: repository));
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(Mh09DetailContent)), same(owner));
      recipient.onCall!();
      recipient.onChat!();
      body.onOpenCod!(fixtureOrderId);
      body.onOpenReturn!(fixtureReturnId);
      await tester.pump();
      expect(dispatches, 0);
      expect(repository.detailCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'async completion and disposed container cannot revive callbacks',
    (tester) async {
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      var dispatches = 0;
      final details = mh09Details(
        capabilities: mh09Capabilities(confirm: true),
        codSummary: mh09CodSummary(),
        returnSummaries: [mh09ReturnSummary()],
      );
      final repository = Mh09PageOrders(() => details);
      await tester.pumpWidget(
        mh09PageHost(
          repository: repository,
          pageOverride: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, show, _) => show
                ? ManagerOrderDetailsPage(
                    orderId: fixtureOrderId,
                    enablePolling: false,
                    onCallRecipient: (_) => dispatches++,
                    onOpenChat: (_) => dispatches++,
                    onOpenCod: (_) => dispatches++,
                    onOpenReturn: (_) => dispatches++,
                  )
                : const Scaffold(body: Text('Source removed')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final recipient = tester.widget<Mh09RecipientSection>(
        find.byType(Mh09RecipientSection),
      );
      final body = tester.widget<Mh09DetailBody>(find.byType(Mh09DetailBody));
      final header = tester.widget<Mh09Header>(find.byType(Mh09Header));
      final footer = tester.widget<Mh09ActionFooter>(
        find.byType(Mh09ActionFooter),
      );
      final pending = Completer<OrderDetails>();
      repository.result = () => pending.future;
      final refreshing = body.onRefresh();
      await tester.pump();
      expect(repository.detailCalls, 2);
      visible.value = false;
      await tester.pumpAndSettle();
      recipient.onCall!();
      recipient.onChat!();
      body.onOpenCod!(fixtureOrderId);
      body.onOpenReturn!(fixtureReturnId);
      header.onRefresh!();
      header.onBack!();
      footer.onAction!(OrderOperation.confirm);
      pending.complete(details);
      await refreshing;
      await tester.pumpAndSettle();
      expect(dispatches, 0);
      expect(repository.detailCalls, 2);
      expect(find.byType(OrderActionDialog), findsNothing);
      expect(find.textContaining(fixtureOrderId), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await body.onRefresh();
      header.onBack!();
      recipient.onCall!();
      footer.onAction!(OrderOperation.reject);
      await tester.pump();
      expect(dispatches, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rapid route removal and push reject old dialog and contact callbacks',
    (tester) async {
      var calls = 0;
      late NavigatorState navigator;
      late MaterialPageRoute<void> sourceRoute;
      Widget detail() => ManagerOrderDetailsPage(
        orderId: fixtureOrderId,
        enablePolling: false,
        onCallRecipient: (_) => calls++,
      );
      final repository = Mh09PageOrders(
        () => mh09Details(capabilities: mh09Capabilities(confirm: true)),
      );
      await tester.pumpWidget(
        mh09PageHost(
          repository: repository,
          pageOverride: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  navigator = Navigator.of(context);
                  sourceRoute = MaterialPageRoute(builder: (_) => detail());
                  navigator.push(sourceRoute);
                },
                child: const Text('Open detail'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open detail'));
      await tester.pumpAndSettle();
      final recipient = tester.widget<Mh09RecipientSection>(
        find.byType(Mh09RecipientSection),
      );
      await tester.tap(find.byKey(const ValueKey('mh09-action-confirm')));
      await tester.pumpAndSettle();
      final dialog = tester.widget<OrderActionDialog>(
        find.byType(OrderActionDialog),
      );
      final modal = ModalRoute.of(
        tester.element(find.byType(OrderActionDialog)),
      )!;
      expect(dialog.isStillAllowed(), isTrue);
      navigator.removeRoute(sourceRoute);
      navigator.push(MaterialPageRoute<void>(builder: (_) => detail()));
      expect(dialog.isStillAllowed(), isFalse);
      recipient.onCall!();
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(tester.takeException(), isNull);
      navigator.pop();
      await tester.pumpAndSettle();
      navigator.removeRoute(modal);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open detail'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mh09-action-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('order-action-submit')));
      await tester.pump();
      expect(
        find.text('Thao tác hiện chưa khả dụng. Vui lòng thử lại sau.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
