import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_action_dialog.dart';

import '../../tool/ui_preview/mh09_preview_scenario.dart';
import 'mh09_04a_report.dart';
import 'mh09_04a_test_support.dart';

void _checkReachable(
  WidgetTester tester,
  Mh09AuditReport report,
  Finder finder,
  String label,
) {
  if (finder.evaluate().isEmpty) {
    report.check('$label is present', false);
    return;
  }
  final rect = tester.getRect(finder.first);
  report.check(
    '$label is hit testable',
    finder.hitTestable().evaluate().isNotEmpty,
  );
  report.check(
    '$label clears the synthetic keyboard inset',
    rect.bottom <= 545,
    '${rect.top}..${rect.bottom}',
  );
  report.check(
    '$label has a 48 logical pixel target',
    tester.getSize(finder.first).height >= 48,
  );
}

Future<bool> _dialogScrollTo(
  WidgetTester tester,
  Mh09AuditReport report,
  Finder target,
  String label,
) async {
  if (target.evaluate().isEmpty) {
    report.check('$label is present', false);
    return false;
  }
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
  if (target.hitTestable().evaluate().isNotEmpty) return true;
  final ancestors = find.ancestor(
    of: target.first,
    matching: find.byType(Scrollable),
  );
  final scroll = ancestors.evaluate().isNotEmpty
      ? ancestors.first
      : find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(Scrollable),
            )
            .first;
  if (scroll.evaluate().isEmpty) {
    report.fail('$label has no dialog scrollable');
    return false;
  }
  for (var n = 0; n < 12; n++) {
    final viewport = tester.getRect(scroll);
    final rect = tester.getRect(target.first);
    if (viewport.contains(rect.center) &&
        target.hitTestable().evaluate().isNotEmpty) {
      return true;
    }
    await tester.drag(
      scroll,
      Offset(
        0,
        rect.center.dy > viewport.center.dy
            ? -viewport.height * .65
            : viewport.height * .65,
      ),
    );
    await tester.pumpAndSettle();
  }
  report.fail('$label is unreachable after dialog gestures');
  return false;
}

Future<void> _capture(
  Mh09AuditHarness harness,
  Mh09AuditReport report,
  String label,
) async {
  try {
    await harness.capture(label);
  } catch (error) {
    report.fail('$label capture: $error');
  }
}

void main() {
  testWidgets('MH09-04A reject dialog handles long text and keyboard insets', (
    tester,
  ) async {
    final report = Mh09AuditReport('mh09_04a_dialog');
    final harness = Mh09AuditHarness(tester);
    const validReason = 'Lý do kiểm thử thao tác từ chối đơn hàng.';
    final longReason = List<String>.filled(1001, 'x').join();
    try {
      await harness.open(size: const Size(320, 844), scale: 2, record: 0);
      await harness.scene(Mh09PreviewScenario.rejectOnly);
      final reject = find.byKey(const ValueKey('mh09-action-reject'));
      await harness.scrollTo(reject);
      report.check(
        'reject action is reachable before opening dialog',
        reject.hitTestable().evaluate().isNotEmpty,
      );
      await tester.tap(reject);
      await tester.pumpAndSettle();
      report.check(
        'real OrderActionDialog is mounted',
        find.byType(OrderActionDialog).evaluate().isNotEmpty,
      );
      await _capture(harness, report, 'mh09_04a_320_s2_dialog_initial');

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await harness.rebuild();
      final reason = find.byKey(const ValueKey('order-action-reason'));
      final submit = find.byKey(const ValueKey('order-action-submit'));
      final reasonReady = await _dialogScrollTo(
        tester,
        report,
        reason,
        'reason field',
      );
      _checkReachable(tester, report, reason, 'reason field');
      final submitReady = await _dialogScrollTo(
        tester,
        report,
        submit,
        'submit control',
      );
      _checkReachable(tester, report, submit, 'submit control');
      final close = find.ancestor(
        of: find.text('Đóng'),
        matching: find.byType(TextButton),
      );
      await _dialogScrollTo(tester, report, close, 'close control');
      _checkReachable(tester, report, close, 'close control');
      report.collect(tester, 'dialog inset layout');
      await _capture(harness, report, 'mh09_04a_320_s2_dialog_keyboard');

      if (submitReady) {
        await tester.tap(submit);
        await tester.pump();
        report.check(
          'blank reason is rejected',
          find.text('Vui lòng nhập lý do trước khi gửi.').evaluate().isNotEmpty,
        );
        report.collect(tester, 'blank reason validation');
        await _capture(harness, report, 'mh09_04a_320_s2_dialog_blank');
      }

      if (reasonReady) {
        await _dialogScrollTo(
          tester,
          report,
          reason,
          'reason field for long text',
        );
        await tester.enterText(reason, longReason);
        await tester.pump();
        final longSubmitReady = await _dialogScrollTo(
          tester,
          report,
          submit,
          'submit control for long text',
        );
        if (longSubmitReady) {
          await tester.tap(submit);
          await tester.pump();
          report.check(
            'overlong reason is rejected',
            find
                .text('Lý do không vượt quá 1.000 ký tự.')
                .evaluate()
                .isNotEmpty,
          );
          report.collect(tester, 'long reason validation');
          await _capture(harness, report, 'mh09_04a_320_s2_dialog_long_reason');
        }
      }

      if (reasonReady) {
        await _dialogScrollTo(
          tester,
          report,
          reason,
          'reason field for valid text',
        );
        await tester.enterText(reason, validReason);
        await tester.pump();
        final validSubmitReady = await _dialogScrollTo(
          tester,
          report,
          submit,
          'submit control for valid text',
        );
        if (validSubmitReady) {
          await tester.tap(submit);
          await tester.pump();
          report.check(
            'valid reason reaches the unavailable boundary',
            find
                .text('Thao tác hiện chưa khả dụng. Vui lòng thử lại sau.')
                .evaluate()
                .isNotEmpty,
          );
          report.collect(tester, 'valid reason unavailable');
          await _capture(harness, report, 'mh09_04a_320_s2_dialog_unavailable');
        }
      }

      await harness.scene(Mh09PreviewScenario.expired);
      report.check(
        'expiry clears the private reason',
        find.text(validReason).evaluate().isEmpty,
      );
      report.check(
        'expiry removes the reason field',
        reason.evaluate().isEmpty,
      );
      report.check(
        'expiry explains the unavailable dialog',
        find.text('Không thể tiếp tục thao tác').evaluate().isNotEmpty,
      );
      report.collect(tester, 'expired dialog');
      await _capture(harness, report, 'mh09_04a_320_s2_dialog_expired');
      await _dialogScrollTo(tester, report, close, 'expired close control');
      await tester.tap(close);
      await tester.pumpAndSettle();
      report.check(
        'expired dialog closes safely',
        find.byType(OrderActionDialog).evaluate().isEmpty,
      );
    } catch (error) {
      report.fail('MH09-04A dialog execution: $error');
      await _capture(harness, report, 'mh09_04a_320_s2_dialog_failure');
    } finally {
      await harness.close();
    }
    await report.save();
    expect(
      report.failures,
      isEmpty,
      reason: 'MH09-04A dialog report was saved before this assertion.',
    );
  });
}
