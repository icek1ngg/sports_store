import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_order_details_page.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_header.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_order_identity.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_recipient_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_items_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_payment_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_action_footer.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_lifecycle_sections.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_timeline.dart';

import '../../tool/ui_preview/mh09_preview_scenario.dart';
import 'mh09_04a_report.dart';
import 'mh09_04a_test_support.dart';

void main() {
  testWidgets(
    'real integrated MH09 primary 390x844 region captures and geometry',
    (tester) async {
      final harness = Mh09AuditHarness(tester);
      final report = Mh09AuditReport('primary_390');
      try {
        await harness.open();
        final page = find.byType(ManagerOrderDetailsPage);
        report.check('actual integrated page', page.evaluate().length == 1);
        final context = tester.element(page);
        report.check(
          'actual logical viewport',
          MediaQuery.sizeOf(context) == const Size(390, 844),
        );
        report.check(
          'actual text scale',
          MediaQuery.textScalerOf(context).scale(14) == 14,
        );
        report.check(
          'no DEMO overlay',
          find.byTooltip('MH09: chọn kịch bản').evaluate().isEmpty,
        );
        final regions = <String, Finder>{
          'header': find.byType(Mh09Header),
          'identity': find.byType(Mh09OrderIdentity),
          'recipient': find.byType(Mh09RecipientSection),
          'items': find.byType(Mh09ItemsSection),
          'payment': find.byType(Mh09PaymentSection),
          'delivery': find.byType(OrderDeliverySection),
          'cod': find.byType(OrderCodLifecycleSection),
          'returns': find.byType(OrderReturnsSection),
          'timeline': find.byType(OrderTimeline),
          'footer': find.byType(Mh09ActionFooter),
          'bodyViewport': harness.bodyScroll,
          'back': find.byTooltip('Quay lại'),
          'refresh': find.byTooltip('Tải lại'),
          'headerTitle': find.text('CHI TIẾT ĐƠN HÀNG'),
          'call': find.byKey(const ValueKey('mh09-recipient-call')),
          'chat': find.byKey(const ValueKey('mh09-recipient-chat')),
          'reject': find.byKey(const ValueKey('mh09-action-reject')),
          'confirm': find.byKey(const ValueKey('mh09-action-confirm')),
        };
        regions.forEach((name, finder) => report.region(tester, name, finder));
        final styles = <String, Object?>{};
        for (final entry in {
          'header': 'CHI TIẾT ĐƠN HÀNG',
          'identity': harness.id,
          'recipient': 'Người mua và người nhận',
          'items': 'Sản phẩm trong đơn',
          'payment': 'THANH TOÁN',
          'total': '1.960.000 ₫',
        }.entries) {
          final textFinder = find.text(entry.value).first;
          final text = tester.widget<Text>(textFinder);
          final style = DefaultTextStyle.of(tester.element(textFinder)).style
              .merge(text.style);
          styles[entry.key] = {
            'font': style.fontFamily,
            'size': style.fontSize,
            'weight': style.fontWeight?.value,
            'lineHeight': style.height,
            'color': style.color?.toARGB32(),
          };
        }
        report.facts['styles'] = styles;
        final scroll = tester.state<ScrollableState>(
          find
              .descendant(
                of: harness.bodyScroll,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        report.facts['mainContentHeight'] =
            scroll.position.maxScrollExtent + scroll.position.viewportDimension;
        await harness.capture('primary_390_top');
        for (final entry in {
          'recipient': 'Người mua và người nhận',
          'items': 'Sản phẩm trong đơn',
          'payment': 'THANH TOÁN',
          'delivery': 'Giao hàng',
          'cod': 'Đối soát COD',
          'returns': 'Yêu cầu trả hàng',
          'timeline': 'Lịch sử đơn hàng',
        }.entries) {
          await harness.scrollTo(find.text(entry.value).first);
          final viewport = tester.getRect(harness.bodyScroll);
          final heading = tester.getTopLeft(find.text(entry.value).first);
          final delta = (heading.dy - viewport.top - 24).clamp(
            0.0,
            viewport.height * .8,
          );
          if (delta > 1) {
            await tester.dragFrom(
              Offset(viewport.center.dx, viewport.bottom - 24),
              Offset(0, -delta),
            );
            await tester.pumpAndSettle();
          }
          report.collect(tester, 'scroll ${entry.key}');
          await harness.capture('primary_390_${entry.key}_focus');
        }
        await harness.capture('primary_390_bottom');
        report.collect(tester, 'primary complete');
      } catch (error, stack) {
        report.fail('$error\n$stack');
        await harness.capture('primary_390_failure');
      } finally {
        await report.save();
        await harness.close();
      }
      expect(report.failures, isEmpty);
    },
  );

  testWidgets('actual external unavailable section has separate screenshot', (
    tester,
  ) async {
    final harness = Mh09AuditHarness(tester);
    final report = Mh09AuditReport('primary_operations');
    try {
      await harness.open(record: 2);
      await harness.scene(Mh09PreviewScenario.operations);
      await harness.scrollTo(find.text('THAO TÁC VẬN HÀNH'));
      await harness.capture('primary_390_operations');
      report.check(
        'operations visible',
        find.text('THAO TÁC VẬN HÀNH').hitTestable().evaluate().isNotEmpty,
      );
      report.collect(tester, 'operations');
    } catch (error, stack) {
      report.fail('$error\n$stack');
    } finally {
      await report.save();
      await harness.close();
    }
    expect(report.failures, isEmpty);
  });
}
