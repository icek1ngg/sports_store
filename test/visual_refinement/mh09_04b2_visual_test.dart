import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/utils/display_formatters.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_items_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_recipient_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_timeline.dart';

import '../../tool/ui_preview/mh09_preview_scenario.dart';
import 'mh09_04a_test_support.dart';
import 'mh09_04b2_capture.dart';

void main() {
  testWidgets('MH09-04B2 real Preview geometry and normal section captures', (
    tester,
  ) async {
    final harness = Mh09AuditHarness(tester);
    try {
      await harness.open();
      final recipient = find.byType(Mh09RecipientSection);
      final items = find.byType(Mh09ItemsSection);
      final snapshots = tester.widget<Mh09ItemsSection>(items).items;
      final regions = <String, Object?>{};
      for (final entry in {
        'recipient': recipient,
        'items': items,
        'call': find.byKey(const ValueKey('mh09-recipient-call')),
        'chat': find.byKey(const ValueKey('mh09-recipient-chat')),
        'reject': find.byKey(const ValueKey('mh09-action-reject')),
        'confirm': find.byKey(const ValueKey('mh09-action-confirm')),
      }.entries) {
        regions[entry.key] = mh09B2Rect(tester.getRect(entry.value));
      }
      for (final key in ['mh09-recipient-call', 'mh09-recipient-chat']) {
        expect(
          tester.getSize(find.byKey(ValueKey(key))).height,
          greaterThanOrEqualTo(48),
        );
      }
      final itemRegions = <Object?>[];
      for (final item in snapshots) {
        final row = find.byKey(ValueKey(item.id));
        expect(row, findsOneWidget);
        final surfaces = find.ancestor(
          of: row,
          matching: find.byType(DecoratedBox),
        );
        final surface = surfaces.evaluate().isEmpty ? row : surfaces.first;
        final tile = tester.getRect(surface);
        final decoration = surfaces.evaluate().isEmpty
            ? null
            : tester.widget<DecoratedBox>(surface).decoration;
        itemRegions.add({
          'id': item.id,
          'bounds': mh09B2Rect(tile),
          'contentBounds': mh09B2Rect(tester.getRect(row)),
          'radius': decoration is BoxDecoration
              ? decoration.borderRadius?.resolve(TextDirection.ltr).topLeft.x
              : null,
          'background': decoration is BoxDecoration
              ? decoration.color?.toARGB32()
              : null,
          'sectionLocalY': tile.top - tester.getRect(items).top,
          'productName': item.productName,
          'variant': item.variantLabel,
          'attributes': item.attributes,
          'quantity': item.quantity,
          'unitPriceVnd': item.unitPriceVnd,
          'lineTotalVnd': item.lineTotalVnd,
        });
      }
      saveMh09B2Geometry('geometry_390', {
        'orderId': harness.id,
        'viewport': [390, 844],
        'dpr': 1,
        'scale': 1,
        'regions': regions,
        'itemRegions': itemRegions,
      });
      await harness.scrollTo(find.text('Người mua và người nhận'));
      await captureMh09B2(harness, 'contact_390');
      await harness.scrollTo(find.text('Sản phẩm trong đơn'));
      await tester.drag(
        harness.bodyScroll,
        Offset(0, 100 - tester.getTopLeft(items).dy),
      );
      await tester.pumpAndSettle();
      await captureMh09B2(harness, 'items_390');
      expect(tester.takeException(), isNull);
    } finally {
      await harness.close();
    }
  });

  testWidgets('MH09-04B2 long snapshots and all forty items stay reachable', (
    tester,
  ) async {
    final harness = Mh09AuditHarness(tester);
    try {
      await harness.open(size: const Size(320, 844), scale: 2, record: 8);
      final recipient = tester.widget<Mh09RecipientSection>(
        find.byType(Mh09RecipientSection),
      );
      expect(recipient.order.recipientName.length, greaterThan(25));
      expect(recipient.order.addressDetail.length, greaterThan(60));
      await harness.scrollTo(find.text(recipient.order.recipientName));
      await captureMh09B2(harness, 'contact_320_scale2');
      await harness.scrollTo(find.byKey(const ValueKey('mh09-recipient-call')));
      final reason = find.textContaining('Gọi:');
      await harness.scrollTo(reason);
      expect(reason.hitTestable(), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mh09-recipient-chat')).hitTestable(),
        findsOneWidget,
      );
      await captureMh09B2(harness, 'contact_320_controls');
      await harness.scene(Mh09PreviewScenario.large);
      final section = tester.widget<Mh09ItemsSection>(
        find.byType(Mh09ItemsSection),
      );
      expect(section.items.length, 40);
      final first = section.items.first;
      final firstName = find.descendant(
        of: find.byKey(ValueKey(first.id)),
        matching: find.text(first.productName),
      );
      await harness.scrollTo(firstName);
      await captureMh09B2(harness, 'items_320_scale2');
      expect(tester.takeException(), isNull);
    } finally {
      await harness.close();
    }

    final large = Mh09AuditHarness(tester);
    try {
      await large.open();
      await large.scene(Mh09PreviewScenario.large);
      final items = tester
          .widget<Mh09ItemsSection>(find.byType(Mh09ItemsSection))
          .items;
      expect(items.length, 40);
      var previousY = double.negativeInfinity;
      for (final item in items) {
        final row = find.byKey(ValueKey(item.id));
        expect(row, findsOneWidget);
        final top = tester.getTopLeft(row).dy;
        expect(top, greaterThan(previousY));
        previousY = top;
      }
      final lastName = find.descendant(
        of: find.byKey(ValueKey(items.last.id)),
        matching: find.text(items.last.productName),
      );
      await large.scrollTo(lastName);
      expect(lastName.hitTestable(), findsOneWidget);
      final lastRow = find.byKey(ValueKey(items.last.id));
      final lastTotal = find.descendant(
        of: lastRow,
        matching: find.text(
          'Thành tiền: ${formatVnd(items.last.lineTotalVnd)}',
        ),
      );
      await large.scrollTo(lastTotal);
      expect(lastTotal.hitTestable(), findsOneWidget);
      expect(
        tester.getBottomRight(lastRow).dy,
        lessThanOrEqualTo(tester.getRect(large.bodyScroll).bottom),
      );
      await captureMh09B2(large, 'items_40_last');
      for (final title in [
        'Giao hàng',
        'Đối soát COD',
        'Yêu cầu trả hàng',
        'Lịch sử đơn hàng',
      ]) {
        final heading = find.text(title);
        await large.scrollTo(heading);
        expect(heading.hitTestable(), findsOneWidget);
      }
      await tester.drag(large.bodyScroll, const Offset(0, -500));
      await tester.pumpAndSettle();
      final timeline = find.byType(OrderTimeline);
      expect(
        tester.getBottomRight(timeline).dy,
        lessThanOrEqualTo(tester.getRect(large.bodyScroll).bottom),
      );
      await captureMh09B2(large, 'items_40_later_sections');
      expect(tester.takeException(), isNull);
    } finally {
      await large.close();
    }
  });
}
