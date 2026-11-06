import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/shared/widgets/async_content.dart';

import '../../tool/ui_preview/mh09_preview_scenario.dart';
import 'mh09_04a_report.dart';
import 'mh09_04a_test_support.dart';

const _lastItem =
    'Bộ dụng cụ thể thao chuyên nghiệp phiên bản minh họa MH09 40';

bool _text(String value) => find.text(value).evaluate().isNotEmpty;
bool _key(String value) =>
    find.byKey(ValueKey<String>(value)).evaluate().isNotEmpty;
bool _semantic(String value) =>
    find.bySemanticsLabel(value).evaluate().isNotEmpty;

Future<void> _capture(
  Mh09AuditHarness harness,
  Mh09AuditReport report,
  String name,
) async {
  try {
    await harness.capture(name);
  } catch (error) {
    report.fail('$name capture: $error');
  }
}

Future<void> _scene(
  Mh09AuditHarness harness,
  Mh09AuditReport report,
  Mh09PreviewScenario scenario,
  String name, {
  Map<String, bool> Function()? checks,
  bool settle = true,
}) async {
  try {
    await harness.scene(scenario, settle: settle);
    (checks?.call() ?? const <String, bool>{}).forEach(
      (label, pass) => report.check(label, pass),
    );
    report.collect(harness.tester, name);
  } catch (error) {
    report.fail('$name execution: $error');
  }
  await _capture(harness, report, name);
}

Future<void> _scrollCheck(
  Mh09AuditHarness harness,
  Mh09AuditReport report,
  Finder target,
  String label,
) async {
  if (target.evaluate().isEmpty) {
    report.check('$label is present', false);
    return;
  }
  try {
    await harness.scrollTo(target);
    report.check(
      '$label is reachable by a real gesture',
      target.hitTestable().evaluate().isNotEmpty,
    );
  } catch (error) {
    report.fail('$label scroll: $error');
  }
}

void main() {
  testWidgets('MH09-04A privacy, transport states, and capabilities', (
    tester,
  ) async {
    final report = Mh09AuditReport('mh09_04a_privacy');
    final transport = Mh09AuditHarness(tester);
    try {
      await transport.open(record: 0);
      transport.environment.mh09.holdLoading = true;
      await _scene(
        transport,
        report,
        Mh09PreviewScenario.loading,
        'mh09_04a_390_loading',
        settle: false,
        checks: () => {
          'loading retains order id': _text(transport.id),
          'loading exposes progress': find
              .byType(LinearProgressIndicator)
              .evaluate()
              .isNotEmpty,
        },
      );
      transport.environment.mh09.releaseLoading();
      await tester.pumpAndSettle();
      await _scene(
        transport,
        report,
        Mh09PreviewScenario.error,
        'mh09_04a_390_error',
        checks: () => {
          'error retains read id': _text(transport.id),
          'error explains staleness': _text('Dữ liệu có thể chưa cập nhật'),
        },
      );
      await _scene(
        transport,
        report,
        Mh09PreviewScenario.stale,
        'mh09_04a_390_stale',
        checks: () => {
          'stale retains read id': _text(transport.id),
          'stale explains staleness': _text('Dữ liệu có thể chưa cập nhật'),
        },
      );
    } finally {
      await transport.close();
    }

    for (final scenario in [
      Mh09PreviewScenario.expired,
      Mh09PreviewScenario.unauthorized,
      Mh09PreviewScenario.unresolved,
    ]) {
      final harness = Mh09AuditHarness(tester);
      try {
        await harness.open(record: 0);
        await _scene(
          harness,
          report,
          scenario,
          'mh09_04a_390_${scenario.name}',
          settle: scenario != Mh09PreviewScenario.unresolved,
          checks: () => {
            '${scenario.name} hides UUID': !_text(harness.id),
            '${scenario.name} hides buyer': !_text('Nguyễn Minh Anh'),
            '${scenario.name} hides private items': !_key('mh09-items-card'),
            if (scenario == Mh09PreviewScenario.expired)
              'expired state is explicit': find
                  .byType(SessionExpiredState)
                  .evaluate()
                  .isNotEmpty,
            if (scenario == Mh09PreviewScenario.unauthorized)
              'unauthorized state is explicit': find
                  .byType(SessionUnavailableState)
                  .evaluate()
                  .isNotEmpty,
            if (scenario == Mh09PreviewScenario.unresolved)
              'unresolved state remains loading': find
                  .byType(LoadingState)
                  .evaluate()
                  .isNotEmpty,
          },
        );
      } finally {
        await harness.close();
      }
    }

    final switched = Mh09AuditHarness(tester);
    try {
      await switched.open(record: 8);
      await switched.scene(Mh09PreviewScenario.large);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
        listen: false,
      );
      final oldCache = container.read(epochCacheProvider);
      final oldScope = switched.environment.scope;
      await switched.scene(Mh09PreviewScenario.accountSwitch, settle: false);
      report.check(
        'account switch removes old forty-row world',
        !_text('40 dòng sản phẩm'),
      );
      report.check('account switch removes old last item', !_text(_lastItem));
      report.check(
        'account switch changes manager owner',
        switched.environment.scope.userId != oldScope.userId,
      );
      report.check(
        'account switch replaces account cache',
        !identical(container.read(epochCacheProvider), oldCache),
      );
      report.check(
        'authorized B uses current canonical item count',
        _text('1 dòng sản phẩm'),
      );
      report.facts['accountScopePolicy'] = 'Manager B may see the same store-wide canonical buyer; old forty-row A fixture must never return.';
      report.collect(tester, 'account switch');
      await _capture(switched, report, 'mh09_04a_390_account_switch');
    } catch (error) {
      report.fail('account switch execution: $error');
      await _capture(switched, report, 'mh09_04a_390_account_switch_failure');
    } finally {
      await switched.close();
    }

    final capability = Mh09AuditHarness(tester);
    try {
      await capability.open(record: 0);
      await _scene(
        capability,
        report,
        Mh09PreviewScenario.confirmOnly,
        'mh09_04a_390_confirm_only',
        checks: () => {
          'confirm is present': _key('mh09-action-confirm'),
          'reject is absent': !_key('mh09-action-reject'),
        },
      );
      await _scene(
        capability,
        report,
        Mh09PreviewScenario.rejectOnly,
        'mh09_04a_390_reject_only',
        checks: () => {
          'reject is present': _key('mh09-action-reject'),
          'confirm is absent': !_key('mh09-action-confirm'),
        },
      );
      await _scene(
        capability,
        report,
        Mh09PreviewScenario.commandsDenied,
        'mh09_04a_390_commands_denied',
        checks: () => {
          'denied confirm is absent': !_key('mh09-action-confirm'),
          'denied reject is absent': !_key('mh09-action-reject'),
        },
      );
    } finally {
      await capability.close();
    }

    final exceptional = Mh09AuditHarness(tester);
    try {
      await exceptional.open(record: 2);
      await _scene(
        exceptional,
        report,
        Mh09PreviewScenario.exceptionalCancel,
        'mh09_04a_390_exceptional_cancel',
        checks: () => {
          'manager cancel is present': _key('mh09-action-manager-cancel'),
          'manager cancel has eligibility':
              tester
                  .widget<OutlinedButton>(
                    find.byKey(const ValueKey('mh09-action-manager-cancel')),
                  )
                  .onPressed !=
              null,
        },
      );
      await _scrollCheck(
        exceptional,
        report,
        find.byKey(const ValueKey('mh09-action-manager-cancel')),
        'manager cancel action',
      );
      await _scene(
        exceptional,
        report,
        Mh09PreviewScenario.operations,
        'mh09_04a_390_operations_preparing',
        checks: () => {
          'assignment is present': _text('Phân công'),
          'external operation reason is semantic': _semantic(
            'Phân công. Chưa khả dụng. Dịch vụ giao hàng chưa sẵn sàng.',
          ),
        },
      );
      await _scrollCheck(
        exceptional,
        report,
        find.text('Phân công'),
        'assignment operation',
      );
    } finally {
      await exceptional.close();
    }

    final failed = Mh09AuditHarness(tester);
    try {
      await failed.open(record: 5);
      await _scene(
        failed,
        report,
        Mh09PreviewScenario.operations,
        'mh09_04a_390_operations_failed_delivery',
        checks: () => {
          'second delivery attempt is present': _text('Giao lần hai'),
          'early return is present': _text('Hoàn hàng sớm'),
          'failed delivery reason is semantic': _semantic(
            'Giao lần hai. Chưa khả dụng. Dịch vụ giao hàng chưa sẵn sàng.',
          ),
        },
      );
      await _scrollCheck(
        failed,
        report,
        find.text('Giao lần hai'),
        'second delivery operation',
      );
      await _scrollCheck(
        failed,
        report,
        find.text('Hoàn hàng sớm'),
        'early return operation',
      );
      await _capture(failed, report, 'mh09_04a_390_operations_failed_bottom');
    } finally {
      await failed.close();
    }

    await report.save();
    expect(
      report.failures,
      isEmpty,
      reason: 'Privacy report was saved before assertion.',
    );
  });
}
