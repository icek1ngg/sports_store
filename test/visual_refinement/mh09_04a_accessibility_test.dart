import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mh09_04a_report.dart';
import 'mh09_04a_test_support.dart';

double _contrast(Color a, Color b) {
  final left = a.computeLuminance();
  final right = b.computeLuminance();
  return ((left > right ? left : right) + .05) /
      ((left < right ? left : right) + .05);
}

void main() {
  testWidgets('enabled financial action labels meet small-text AA contrast', (
    tester,
  ) async {
    final harness = Mh09AuditHarness(tester);
    final report = Mh09AuditReport('accessibility_contrast');
    try {
      await harness.open();
      final reject = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('mh09-action-reject')),
      );
      final confirm = tester.widget<FilledButton>(
        find.byKey(const ValueKey('mh09-action-confirm')),
      );
      report.check(
        'both canonical actions enabled',
        reject.onPressed != null && confirm.onPressed != null,
      );
      final colors = <String, ButtonStyle>{
        'reject': reject.style!,
        'confirm': confirm.style!,
      };
      for (final entry in colors.entries) {
        final foreground = entry.value.foregroundColor!.resolve({})!;
        final background = entry.value.backgroundColor!.resolve({})!;
        final ratio = _contrast(foreground, background);
        report.facts[entry.key] = {
          'foreground': foreground.toARGB32().toRadixString(16),
          'background': background.toARGB32().toRadixString(16),
          'ratio': ratio,
          'fontSize': entry.value.textStyle?.resolve({})?.fontSize,
        };
        report.check(
          '${entry.key} small text contrast >=4.5',
          ratio >= 4.5,
          ratio,
        );
      }
      await harness.capture('accessibility_enabled_actions');
      report.collect(tester, 'contrast');
    } finally {
      await report.save();
      await harness.close();
    }
    expect(
      report.failures,
      isEmpty,
      reason: 'Keep this assertion failing for demonstrated contrast defects.',
    );
  });

  testWidgets('major MH09 section titles expose heading semantics', (
    tester,
  ) async {
    final harness = Mh09AuditHarness(tester);
    final report = Mh09AuditReport('accessibility_headings');
    final semantics = tester.ensureSemantics();
    try {
      await harness.open();
      for (final title in [
        'Người mua và người nhận',
        'Sản phẩm trong đơn',
        'THANH TOÁN',
      ]) {
        await harness.scrollTo(find.text(title));
        final node = tester.getSemantics(find.text(title));
        final data = node.getSemanticsData();
        report.check(
          '$title is an accessibility heading',
          data.flagsCollection.isHeader,
          data.label,
        );
      }
      await harness.capture('accessibility_heading_payment');
      report.collect(tester, 'headings');
    } finally {
      await report.save();
      await harness.close();
      semantics.dispose();
    }
    expect(
      report.failures,
      isEmpty,
      reason:
          'Heading navigation requirements remain explicit until refinement.',
    );
  });
}
