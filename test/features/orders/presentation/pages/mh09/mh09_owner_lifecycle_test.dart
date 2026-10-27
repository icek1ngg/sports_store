import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
  testWidgets('same-frame inactive source revokes a retained dialog decision', (
    tester,
  ) async {
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    final repository = Mh09PageOrders(
      () => mh09Details(capabilities: mh09Capabilities(confirm: true)),
    );
    late Element source;
    late OrderActionDialog dialog;
    bool? mountedDuringProbe;
    bool? activeDuringProbe;
    bool? decisionDuringProbe;
    await tester.pumpWidget(
      mh09PageHost(
        repository: repository,
        pageOverride: ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (_, show, _) => Column(
            children: [
              Expanded(
                child: show
                    ? const ManagerOrderDetailsPage(
                        orderId: fixtureOrderId,
                        enablePolling: false,
                      )
                    : const SizedBox.shrink(),
              ),
              Builder(
                builder: (_) {
                  if (!show) {
                    mountedDuringProbe = source.mounted;
                    activeDuringProbe = source.debugIsActive;
                    decisionDuringProbe = dialog.isStillAllowed();
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester.element(find.byType(Scaffold)).visitAncestorElements((element) {
      if (element.widget is ConsumerWidget ||
          element.widget is ConsumerStatefulWidget) {
        source = element;
        return false;
      }
      return true;
    });
    await tester.tap(find.byKey(const ValueKey('mh09-action-confirm')));
    await tester.pumpAndSettle();
    dialog = tester.widget<OrderActionDialog>(find.byType(OrderActionDialog));
    expect(dialog.isStillAllowed(), isTrue);
    visible.value = false;
    await tester.pumpAndSettle();
    expect(mountedDuringProbe, isTrue);
    expect(activeDuringProbe, isFalse);
    expect(decisionDuringProbe, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reparenting revokes old callbacks without reviving dialog tickets',
    (tester) async {
      final moved = ValueNotifier(false);
      addTearDown(moved.dispose);
      final key = GlobalKey();
      var dispatched = 0;
      final page = ManagerOrderDetailsPage(
        key: key,
        orderId: fixtureOrderId,
        enablePolling: false,
        onCallRecipient: (_) => dispatched++,
        onOpenChat: (_) => dispatched++,
        onOpenCod: (_) => dispatched++,
        onOpenReturn: (_) => dispatched++,
      );
      final repository = Mh09PageOrders(
        () => mh09Details(
          capabilities: mh09Capabilities(confirm: true),
          codSummary: mh09CodSummary(),
          returnSummaries: [mh09ReturnSummary()],
        ),
      );
      late OrderActionDialog dialog;
      late Mh09RecipientSection recipient;
      late Mh09DetailBody body;
      late Mh09Header header;
      late Mh09ActionFooter footer;
      late Element source;
      var probed = false;
      await tester.pumpWidget(
        mh09PageHost(
          repository: repository,
          pageOverride: ValueListenableBuilder<bool>(
            valueListenable: moved,
            builder: (_, swap, _) => Row(
              children: [
                Expanded(child: swap ? const SizedBox.shrink() : page),
                Builder(
                  builder: (_) {
                    if (swap && !probed) {
                      probed = true;
                      expect(source.mounted, isTrue);
                      expect(source.debugIsActive, isFalse);
                      expect(dialog.isStillAllowed(), isFalse);
                      recipient.onCall!();
                      recipient.onChat!();
                      body.onOpenCod!(fixtureOrderId);
                      body.onOpenReturn!(fixtureReturnId);
                      header.onRefresh!();
                      header.onBack!();
                      footer.onAction!(OrderOperation.confirm);
                    }
                    return const SizedBox.shrink();
                  },
                ),
                Expanded(child: swap ? page : const SizedBox.shrink()),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      source = tester.element(find.byType(Mh09DetailContent));
      recipient = tester.widget(find.byType(Mh09RecipientSection));
      body = tester.widget(find.byType(Mh09DetailBody));
      header = tester.widget(find.byType(Mh09Header));
      footer = tester.widget(find.byType(Mh09ActionFooter));
      await tester.tap(find.byKey(const ValueKey('mh09-action-confirm')));
      await tester.pumpAndSettle();
      dialog = tester.widget(find.byType(OrderActionDialog));
      moved.value = true;
      await tester.pumpAndSettle();
      expect(probed, isTrue);
      expect(source.debugIsActive, isTrue);
      expect(tester.element(find.byType(Mh09DetailContent)), same(source));
      expect(dialog.isStillAllowed(), isFalse);
      recipient.onCall!();
      expect(dispatched, 0);
      expect(repository.detailCalls, 1);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mh09-action-confirm')));
      await tester.pumpAndSettle();
      final currentDialog = tester.widget<OrderActionDialog>(
        find.byType(OrderActionDialog),
      );
      expect(currentDialog.isStillAllowed(), isTrue);
      expect(currentDialog.operation, OrderOperation.confirm);
    },
  );
}
