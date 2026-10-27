import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/utils/display_formatters.dart';
import 'package:sports_store/features/orders/data/models/order_dto.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_order_details_page.dart';
import 'package:sports_store/features/orders/presentation/pages/mh09/mh09_legacy_action_footer.dart';
import 'package:sports_store/features/orders/presentation/pages/mh09/mh09_legacy_contact_actions.dart';
import 'package:sports_store/features/orders/presentation/pages/mh09/mh09_legacy_detail_body.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_action_footer.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_header.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_items_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_operational_actions.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_order_identity.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_payment_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_recipient_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_lifecycle_sections.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_timeline.dart';

import 'mh09_page_test_support.dart';

void main() {
  testWidgets('wires all seven sections to one accepted aggregate', (
    tester,
  ) async {
    final details = mh09Details(
      buyer: {'id': fixtureCustomerId, 'full_name': 'Người mua minh họa'},
      codSummary: mh09CodSummary(),
      capabilities: mh09Capabilities(assign: true, confirm: true, reject: true),
    );
    final repository = Mh09PageOrders(() => details);
    await tester.pumpWidget(mh09PageHost(repository: repository));
    await tester.pumpAndSettle();

    expect(find.byType(ManagerOrderDetailsPage), findsOneWidget);
    expect(find.byType(Mh09Header), findsOneWidget);
    expect(find.byType(Mh09ActionFooter), findsOneWidget);
    expect(find.byType(Mh09OrderIdentity), findsOneWidget);
    expect(find.byType(Mh09RecipientSection), findsOneWidget);
    expect(find.byType(Mh09ItemsSection), findsOneWidget);
    expect(find.byType(Mh09PaymentSection), findsOneWidget);
    expect(find.byType(OrderLifecycleSections), findsOneWidget);
    expect(find.byType(OrderTimeline), findsOneWidget);
    expect(find.byType(Mh09OperationalActions), findsOneWidget);
    expect(find.byType(Mh09LegacyDetailBody), findsNothing);
    expect(find.byType(Mh09LegacyContactActions), findsNothing);
    expect(find.byType(Mh09LegacyActionFooter), findsNothing);

    final identity = tester.widget<Mh09OrderIdentity>(
      find.byType(Mh09OrderIdentity),
    );
    final recipient = tester.widget<Mh09RecipientSection>(
      find.byType(Mh09RecipientSection),
    );
    final items = tester.widget<Mh09ItemsSection>(
      find.byType(Mh09ItemsSection),
    );
    final payment = tester.widget<Mh09PaymentSection>(
      find.byType(Mh09PaymentSection),
    );
    final lifecycle = tester.widget<OrderLifecycleSections>(
      find.byType(OrderLifecycleSections),
    );
    final timeline = tester.widget<OrderTimeline>(find.byType(OrderTimeline));
    final operations = tester.widget<Mh09OperationalActions>(
      find.byType(Mh09OperationalActions),
    );
    final footer = tester.widget<Mh09ActionFooter>(
      find.byType(Mh09ActionFooter),
    );

    expect(identical(identity.order, details.order), isTrue);
    expect(identical(recipient.order, details.order), isTrue);
    expect(identical(recipient.buyer, details.buyer), isTrue);
    expect(recipient.contactEnabled, isTrue);
    expect(recipient.onCall, isNull);
    expect(recipient.onChat, isNull);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('mh09-recipient-call')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('mh09-recipient-chat')),
          )
          .onPressed,
      isNull,
    );
    expect(items.items, hasLength(details.items.length));
    for (var index = 0; index < details.items.length; index++) {
      expect(identical(items.items[index], details.items[index]), isTrue);
    }
    expect(identical(payment.order, details.order), isTrue);
    expect(identical(payment.codSummary, details.codSummary), isTrue);
    expect(
      identical(lifecycle.deliverySummary, details.deliverySummary),
      isTrue,
    );
    expect(identical(lifecycle.codSummary, details.codSummary), isTrue);
    expect(
      identical(lifecycle.returnSummaries, details.returnSummaries),
      isTrue,
    );
    expect(identical(timeline.entries, details.timeline), isTrue);
    expect(timeline.historyComplete, details.historyComplete);
    expect(identical(operations.capabilities, details.capabilities), isTrue);
    expect(identical(footer.capabilities, details.capabilities), isTrue);
  });

  testWidgets('keeps missing projections honest and formats integer totals', (
    tester,
  ) async {
    final details = mh09Details();
    await tester.pumpWidget(
      mh09PageHost(repository: Mh09PageOrders(() => details)),
    );
    await tester.pumpAndSettle();

    expect(find.text(formatVnd(details.order.subtotalVnd)), findsOneWidget);
    expect(find.text(formatVnd(details.order.deliveryFeeVnd)), findsOneWidget);
    expect(find.text(formatVnd(details.order.totalCodVnd)), findsOneWidget);
    expect(find.text('Chưa có dữ liệu giao hàng'), findsOneWidget);
    expect(find.text('Chưa có dữ liệu COD'), findsNWidgets(2));
    expect(find.text('Chưa có dữ liệu yêu cầu trả hàng'), findsOneWidget);
    expect(find.text('Đã giao hàng'), findsNothing);
    expect(find.text('Shipper đã thu'), findsNothing);
    expect(find.text('Chờ duyệt'), findsNothing);
  });

  testWidgets(
    'keeps order, delivery, COD, return and timeline states independent',
    (tester) async {
      final details = mh09Details(
        status: 'delivered',
        deliverySummary: mh09DeliverySummary(),
        codSummary: mh09CodSummary(),
        returnSummaries: [mh09ReturnSummary()],
        timeline: [
          fixtureTimelineEntryJson(),
          fixtureTimelineEntryJson(
            eventId: '40000000-0000-4000-8000-000000000003',
            sourceEntityType: 'delivery_task',
            sourceEntityId: fixtureTaskId,
            eventKind: 'outbound_failed',
            toState: 'failed',
            occurredAt: '2026-10-08T06:00:00Z',
          ),
          fixtureTimelineEntryJson(
            eventId: '40000000-0000-4000-8000-000000000004',
            sourceEntityType: 'cod',
            eventKind: 'cod_received',
            fromState: 'collected',
            toState: 'received',
            occurredAt: '2026-10-08T06:30:00Z',
          ),
          fixtureTimelineEntryJson(
            eventId: '40000000-0000-4000-8000-000000000005',
            sourceEntityType: 'return_request',
            sourceEntityId: fixtureReturnId,
            eventKind: 'return_submitted',
            toState: 'pending_review',
            occurredAt: '2026-10-08T07:00:00Z',
          ),
        ],
      );
      await tester.pumpWidget(
        mh09PageHost(repository: Mh09PageOrders(() => details)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Đã giao hàng'), findsOneWidget);
      expect(find.text('Giao thất bại'), findsOneWidget);
      expect(find.text('Shipper đã thu'), findsOneWidget);
      expect(find.text('Chờ duyệt'), findsOneWidget);
      expect(find.text('Đơn hàng được tạo'), findsOneWidget);
      expect(find.text('Giao hàng thất bại'), findsOneWidget);
      expect(find.text('Cửa hàng đã nhận COD'), findsOneWidget);
      expect(find.text('Đã gửi yêu cầu trả hàng'), findsOneWidget);
      expect(find.text('Đã hủy'), findsNothing);
    },
  );

  testWidgets(
    'preserves forty valid snapshot rows and clears the footer boundary',
    (tester) async {
      final raw = fixtureOrderDetailsJson();
      raw['items'] = [
        for (var index = 1; index <= 40; index++)
          {
            ...fixtureOrderItemJson(),
            'id':
                '60000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
            'product_name': 'Sản phẩm snapshot $index',
            'variant_label': 'Màu $index / EU 4$index',
            'unit_price_vnd': 86250,
            'line_total_vnd': 86250,
          },
      ];
      raw['capabilities'] = mh09Capabilities(confirm: true);
      final details = OrderDetailsDto.fromJson(raw).domain;
      await tester.pumpWidget(
        mh09PageHost(repository: Mh09PageOrders(() => details)),
      );
      await tester.pumpAndSettle();

      expect(find.text('40 dòng sản phẩm'), findsOneWidget);
      expect(find.text('Sản phẩm snapshot 1'), findsOneWidget);
      final scrollable = find.ancestor(
        of: find.byType(Mh09ItemsSection),
        matching: find.byType(SingleChildScrollView),
      );
      expect(scrollable, findsOneWidget);
      await tester.drag(scrollable, const Offset(0, -50000));
      await tester.pumpAndSettle();

      final last = find.text('Sản phẩm snapshot 40');
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      final reachableLast = last.hitTestable();
      expect(reachableLast, findsOneWidget);
      expect(last, findsOneWidget);
      expect(find.byType(Mh09ActionFooter), findsOneWidget);
      final lastRect = tester.getRect(reachableLast);
      final headerBottom = tester.getBottomLeft(find.byType(Mh09Header)).dy;
      final footerTop = tester.getTopLeft(find.byType(Mh09ActionFooter)).dy;
      expect(lastRect.top, greaterThanOrEqualTo(headerBottom));
      expect(lastRect.bottom, lessThanOrEqualTo(footerTop));
      expect(tester.takeException(), isNull);
    },
  );
}
