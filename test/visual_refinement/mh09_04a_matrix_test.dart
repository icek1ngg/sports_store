import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/utils/display_formatters.dart';
import 'package:sports_store/features/orders/presentation/pages/mh09/mh09_detail_body.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_header.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_items_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_operational_actions.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_order_identity.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_payment_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_recipient_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_lifecycle_sections.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_timeline.dart';

import '../../tool/ui_preview/mh09_preview_scenario.dart';
import 'mh09_04a_report.dart';
import 'mh09_04a_test_support.dart';

String _scaleTag(double value) => value.toString().replaceAll('.', '_');

bool _overlaps(Rect left, Rect right) {
  final intersection = left.intersect(right);
  return intersection.width > .5 && intersection.height > .5;
}

Future<void> _collect(
  WidgetTester tester,
  Mh09AuditReport report,
  String stage,
) async {
  try {
    report.collect(tester, stage);
  } catch (error) {
    report.fail('$stage exception collection: $error');
  }
}

void _checkButton(
  WidgetTester tester,
  Mh09AuditReport report,
  Finder finder,
  String label,
) {
  if (finder.evaluate().isEmpty) {
    report.fail('$label action is missing');
    return;
  }
  try {
    final size = tester.getSize(finder.first);
    report.check(
      '$label target is at least 48x48',
      size.width >= 48 && size.height >= 48,
      '${size.width}x${size.height}',
    );
  } catch (error) {
    report.fail('$label target geometry: $error');
  }
}

void _recordRegions(
  WidgetTester tester,
  Mh09AuditReport report,
  Size viewport,
  EdgeInsets padding,
) {
  final regions = <String, Finder>{
    'header': find.byType(Mh09Header),
    'identity': find.byType(Mh09OrderIdentity),
    'recipient': find.byType(Mh09RecipientSection),
    'items': find.byType(Mh09ItemsSection),
    'payment': find.byType(Mh09PaymentSection),
    'lifecycle': find.byType(OrderLifecycleSections),
    'timeline': find.byType(OrderTimeline),
    'operations': find.byType(Mh09OperationalActions),
    'body': find.byType(Mh09DetailBody),
  };
  final rects = <String, Rect>{};
  for (final entry in regions.entries) {
    try {
      report.region(tester, entry.key, entry.value);
      if (entry.value.evaluate().isEmpty) continue;
      final rect = tester.getRect(entry.value.first);
      rects[entry.key] = rect;
      report.check(
        '${entry.key} stays within horizontal viewport',
        rect.left >= -1 && rect.right <= viewport.width + 1,
        '$rect',
      );
    } catch (error) {
      report.fail('${entry.key} geometry: $error');
    }
  }

  final header = rects['header'];
  if (header != null) {
    report.check(
      'header respects top safe area',
      header.top >= padding.top - 1,
      '$header / top inset ${padding.top}',
    );
    report.check(
      'header respects horizontal safe areas',
      header.left >= padding.left - 1 &&
          header.right <= viewport.width - padding.right + 1,
      '$header / $padding',
    );
  }
  final body = rects['body'];
  if (body != null && header != null) {
    report.check(
      'scroll body starts below header',
      body.top >= header.bottom - 1,
      '$body / $header',
    );
  }

  final componentNames = [
    'identity',
    'recipient',
    'items',
    'payment',
    'lifecycle',
    'timeline',
    'operations',
  ];
  for (var left = 0; left < componentNames.length; left++) {
    final leftRect = rects[componentNames[left]];
    if (leftRect == null) continue;
    for (var right = left + 1; right < componentNames.length; right++) {
      final rightRect = rects[componentNames[right]];
      if (rightRect == null) continue;
      report.check(
        '${componentNames[left]} does not overlap ${componentNames[right]}',
        !_overlaps(leftRect, rightRect),
        '$leftRect / $rightRect',
      );
    }
  }
}

void _checkCanonicalContract(
  WidgetTester tester,
  Mh09AuditReport report,
  Mh09AuditHarness harness,
) {
  final details = harness.environment.manager.canonicalDetails(harness.id);
  final expectedStatus = orderStatusLabel(details.order.status);
  final total = formatVnd(details.order.totalCodVnd);
  report.check(
    'canonical UUID is visible',
    find.text(harness.id).evaluate().isNotEmpty,
    harness.id,
  );
  report.check(
    'canonical UUID has semantic label',
    find.bySemanticsLabel('Mã đơn hàng: ${harness.id}').evaluate().isNotEmpty,
  );
  report.check(
    'actual order status has semantic label',
    find
        .bySemanticsLabel('Trạng thái đơn: $expectedStatus')
        .evaluate()
        .isNotEmpty,
    expectedStatus,
  );
  report.check(
    'full COD amount is accessible',
    find.bySemanticsLabel('Tổng COD: $total').evaluate().isNotEmpty,
    total,
  );

  final components = <String, Finder>{
    'header': find.byType(Mh09Header),
    'identity': find.byType(Mh09OrderIdentity),
    'recipient': find.byType(Mh09RecipientSection),
    'items': find.byType(Mh09ItemsSection),
    'payment': find.byType(Mh09PaymentSection),
    'lifecycle': find.byType(OrderLifecycleSections),
    'timeline': find.byType(OrderTimeline),
    'operations': find.byType(Mh09OperationalActions),
  };
  for (final entry in components.entries) {
    report.check(
      '${entry.key} component is present',
      entry.value.evaluate().isNotEmpty,
    );
  }

  _checkButton(tester, report, find.byTooltip('Quay lại'), 'back');
  _checkButton(tester, report, find.byTooltip('Tải lại'), 'refresh');
  _checkButton(
    tester,
    report,
    find.byKey(const ValueKey('mh09-recipient-call')),
    'call',
  );
  _checkButton(
    tester,
    report,
    find.byKey(const ValueKey('mh09-recipient-chat')),
    'chat',
  );
  _checkButton(
    tester,
    report,
    find.byKey(const ValueKey('mh09-action-reject')),
    'reject',
  );
  _checkButton(
    tester,
    report,
    find.byKey(const ValueKey('mh09-action-confirm')),
    'confirm',
  );

  final reject = find.byKey(const ValueKey('mh09-action-reject'));
  final confirm = find.byKey(const ValueKey('mh09-action-confirm'));
  if (reject.evaluate().isNotEmpty && confirm.evaluate().isNotEmpty) {
    final rejectRect = tester.getRect(reject.first);
    final confirmRect = tester.getRect(confirm.first);
    for (final entry in {
      'reject': rejectRect,
      'confirm': confirmRect,
    }.entries) {
      report.check(
        'footer ${entry.key} stays within viewport',
        entry.value.left >= -1 && entry.value.right <= harness.size.width + 1,
        '${entry.value}',
      );
    }
    final verticalOverlap =
        rejectRect.bottom > confirmRect.top &&
        confirmRect.bottom > rejectRect.top;
    final ordered = verticalOverlap
        ? rejectRect.left < confirmRect.left
        : rejectRect.top < confirmRect.top ||
              (rejectRect.top == confirmRect.top &&
                  rejectRect.left < confirmRect.left);
    report.check(
      'footer button order is reject then confirm',
      ordered,
      '$rejectRect / $confirmRect',
    );
    report.check(
      'footer actions do not overlap',
      !_overlaps(rejectRect, confirmRect),
      '$rejectRect / $confirmRect',
    );
  }
}

Future<List<String>> _auditCase(
  WidgetTester tester,
  Size viewport,
  double scale,
) async {
  final tag =
      'mh09_04a_${viewport.width.toInt()}x${viewport.height.toInt()}_s${_scaleTag(scale)}';
  final report = Mh09AuditReport(tag);
  final harness = Mh09AuditHarness(tester);
  final padding = viewport.width > viewport.height
      ? const EdgeInsets.fromLTRB(24, 0, 24, 24)
      : const EdgeInsets.only(top: 24, bottom: 34);
  var opened = false;
  try {
    await harness.open(size: viewport, scale: scale, padding: padding);
    opened = true;
    await _collect(tester, report, 'open');
    await harness.scene(Mh09PreviewScenario.canonical);
    await _collect(tester, report, 'canonical scene');
    _checkCanonicalContract(tester, report, harness);
    _recordRegions(tester, report, viewport, padding);
    await harness.capture('${tag}_top');
    await _collect(tester, report, 'top capture');

    final payment = find.byType(Mh09PaymentSection);
    try {
      await harness.scrollTo(payment);
      report.check(
        'payment section is reachable by gesture',
        payment.evaluate().isNotEmpty &&
            tester.getRect(payment.first).bottom > 0 &&
            tester.getRect(payment.first).top < viewport.height,
      );
    } catch (error) {
      report.fail('payment gesture: $error');
    }
    await _collect(tester, report, 'payment gesture');

    final timelineHeader = find.text('Lịch sử đơn hàng');
    try {
      await harness.scrollTo(timelineHeader);
      final timelineRect = tester.getRect(timelineHeader.first);
      report.check(
        'last timeline header is reachable by gesture',
        timelineRect.top >= padding.top - 1 &&
            timelineRect.bottom <= viewport.height - padding.bottom + 1,
        '$timelineRect',
      );
    } catch (error) {
      report.fail('timeline gesture: $error');
    }
    await _collect(tester, report, 'timeline gesture');

    final body = find.byType(Mh09DetailBody);
    final reject = find.byKey(const ValueKey('mh09-action-reject'));
    final confirm = find.byKey(const ValueKey('mh09-action-confirm'));
    if (body.evaluate().isNotEmpty &&
        reject.evaluate().isNotEmpty &&
        confirm.evaluate().isNotEmpty) {
      final bodyRect = tester.getRect(body.first);
      final actionTop = [
        tester.getRect(reject.first).top,
        tester.getRect(confirm.first).top,
      ].reduce((left, right) => left < right ? left : right);
      report.check(
        'footer is reserved below scroll body',
        bodyRect.bottom <= actionTop + 1,
        '$bodyRect / action top $actionTop',
      );
      final actionBottom = [
        tester.getRect(reject.first).bottom,
        tester.getRect(confirm.first).bottom,
      ].reduce((left, right) => left > right ? left : right);
      report.check(
        'footer respects bottom safe area',
        actionBottom <= viewport.height - padding.bottom + 1,
        'bottom $actionBottom / inset ${padding.bottom}',
      );
    }
    await harness.capture('${tag}_bottom');
    await _collect(tester, report, 'bottom capture');
  } catch (error) {
    report.fail('case execution: $error');
    await _collect(tester, report, 'case failure');
  } finally {
    if (opened && report.failures.isNotEmpty) {
      try {
        await harness.capture('${tag}_failure');
      } catch (error) {
        report.fail('failure capture: $error');
      }
    }
    try {
      await harness.close();
      await _collect(tester, report, 'close');
    } catch (error) {
      report.fail('harness close: $error');
    }
    try {
      await report.save();
    } catch (error) {
      report.fail('report save: $error');
    }
  }
  return List<String>.from(report.failures);
}

void main() {
  testWidgets('MH09-04A responsive matrix uses the real preview page', (
    tester,
  ) async {
    final failures = <String>[];
    for (final viewport in [
      const Size(320, 844),
      const Size(360, 844),
      const Size(390, 844),
      const Size(412, 844),
      const Size(844, 390),
    ]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        failures.addAll(await _auditCase(tester, viewport, scale));
      }
    }
    expect(
      failures,
      isEmpty,
      reason: 'MH09-04A reports are saved after all matrix cases.',
    );
  });
}
