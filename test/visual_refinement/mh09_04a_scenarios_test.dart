import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_order_details_page.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_header.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_items_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_payment_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_recipient_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_lifecycle_sections.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_timeline.dart';

import '../../tool/ui_preview/mh09_preview_scenario.dart';
import 'mh09_04a_report.dart';
import 'mh09_04a_test_support.dart';

const _buyer =
    'Cửa hàng thể thao Thành phố Hà Nội – Bộ phận mua sắm doanh nghiệp';
const _recipient =
    'Người nhận hàng tại Trung tâm thể thao Thành phố Hà Nội, quầy số 12';
const _address =
    'Tầng 7, tòa nhà thể thao Thành phố Hà Nội, 18 phố Huế, quận Hai Bà Trưng, Hà Nội';
const _lastItem =
    'Bộ dụng cụ thể thao chuyên nghiệp phiên bản minh họa MH09 40';

bool _text(String value) => find.text(value).evaluate().isNotEmpty;
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

void _target(
  WidgetTester tester,
  Mh09AuditReport report,
  Finder finder,
  String label,
) {
  if (finder.evaluate().isEmpty) {
    report.check('$label is present', false);
    return;
  }
  final size = tester.getSize(finder.first);
  report.check(
    '$label has a 48 logical pixel target',
    size.width >= 48 && size.height >= 48,
    '${size.width}x${size.height}',
  );
  report.check(
    '$label is hit testable',
    finder.hitTestable().evaluate().isNotEmpty,
  );
}

void _readingOrder(WidgetTester tester, Mh09AuditReport report) {
  final sections = [
    find.byType(Mh09Header),
    find.byType(Mh09RecipientSection),
    find.byType(Mh09ItemsSection),
    find.byType(Mh09PaymentSection),
    find.byType(OrderLifecycleSections),
    find.byType(OrderTimeline),
  ];
  final tops = <double>[];
  for (final section in sections) {
    if (section.evaluate().isNotEmpty) {
      tops.add(tester.getRect(section.first).top);
    }
  }
  report.check(
    'sections preserve logical reading order',
    tops.length == sections.length &&
        List.generate(
          tops.length - 1,
          (i) => tops[i] <= tops[i + 1],
        ).every((value) => value),
  );
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
  testWidgets('MH09-04A targeted scenario states and responsive content', (
    tester,
  ) async {
    final report = Mh09AuditReport('mh09_04a_scenarios');
    final harness = Mh09AuditHarness(tester);
    final semantics = tester.ensureSemantics();
    report.facts['scenarioCoverage'] = Mh09PreviewScenario.values.length;
    try {
      await harness.open(record: 4);
      report.check(
        'real MH08 to MH09 route is mounted',
        find.byType(ManagerOrderDetailsPage).evaluate().length == 1,
      );
      report.check(
        'full UUID is visible and semantic',
        _text(harness.id) &&
            harness.id.length == 36 &&
            _semantic('Mã đơn hàng: ${harness.id}'),
      );
      report.check(
        'header and delivered status are semantic',
        _semantic('CHI TIẾT ĐƠN HÀNG') &&
            _semantic('Trạng thái đơn: Đã giao hàng'),
      );
      report.check(
        'COD amount keeps integer VND meaning',
        _semantic('Tổng COD: 375.000 ₫'),
      );
      report.check(
        'disabled contact reason is discoverable',
        _semantic('Gọi. Tính năng gọi chưa khả dụng.'),
      );
      _readingOrder(tester, report);
      _target(tester, report, find.byTooltip('Quay lại'), 'back control');
      _target(tester, report, find.byTooltip('Tải lại'), 'refresh control');
      _target(
        tester,
        report,
        find.byKey(const ValueKey('mh09-recipient-call')),
        'call control',
      );
      _target(
        tester,
        report,
        find.byKey(const ValueKey('mh09-recipient-chat')),
        'chat control',
      );
      await _scene(
        harness,
        report,
        Mh09PreviewScenario.canonical,
        'mh09_04a_390_canonical',
      );
      await _scene(
        harness,
        report,
        Mh09PreviewScenario.normal,
        'mh09_04a_390_normal',
        checks: () => {
          'delivered status': _text('Đã giao hàng'),
          'delivery lifecycle': _text('Giao hàng'),
          'COD lifecycle': _text('Đối soát COD'),
          'return lifecycle is independent': _text('Chờ duyệt'),
          'return timeline is retained': _text('Đã gửi yêu cầu trả hàng'),
        },
      );
      await _scene(
        harness,
        report,
        Mh09PreviewScenario.missingDelivery,
        'mh09_04a_390_missing_delivery',
        checks: () => {
          'missing delivery is explicit': _text('Chưa có dữ liệu giao hàng'),
          'missing delivery keeps COD': !_text('Chưa có dữ liệu COD'),
          'buyer remains in scope': _text('Vũ Gia Hân'),
        },
      );
      await _scene(
        harness,
        report,
        Mh09PreviewScenario.missingCod,
        'mh09_04a_390_missing_cod',
        checks: () => {
          'missing COD is explicit': _text('Chưa có dữ liệu COD'),
          'missing COD keeps delivery': !_text('Chưa có dữ liệu giao hàng'),
        },
      );
      await _scene(
        harness,
        report,
        Mh09PreviewScenario.missingBuyer,
        'mh09_04a_390_missing_buyer',
        checks: () => {
          'missing buyer is explicit': _text('Chưa có thông tin tài khoản'),
          'missing buyer keeps delivery': !_text('Chưa có dữ liệu giao hàng'),
          'missing buyer keeps COD': !_text('Chưa có dữ liệu COD'),
        },
      );
      await _scene(
        harness,
        report,
        Mh09PreviewScenario.emptyReturns,
        'mh09_04a_390_empty_returns',
        checks: () => {
          'empty returns are explicit': _text(
            'Chưa có dữ liệu yêu cầu trả hàng',
          ),
          'empty returns do not imply cancellation': !_text('Đã hủy'),
        },
      );
    } finally {
      semantics.dispose();
      await harness.close();
    }

    final large = Mh09AuditHarness(tester);
    try {
      await large.open(record: 8);
      await _scene(
        large,
        report,
        Mh09PreviewScenario.large,
        'mh09_04a_390_large',
        checks: () => {
          'large fixture exposes forty rows': _text('40 dòng sản phẩm'),
        },
      );
      await _scrollCheck(
        large,
        report,
        find.text(_lastItem),
        'last large item',
      );
      await _scrollCheck(
        large,
        report,
        find.text('Lịch sử đơn hàng'),
        'large timeline',
      );
      await _capture(large, report, 'mh09_04a_390_large_bottom');
    } finally {
      await large.close();
    }

    final long = Mh09AuditHarness(tester);
    try {
      await long.open(size: const Size(320, 844), scale: 2, record: 8);
      report.check('long buyer renders at 320 scale 2', _text(_buyer));
      await _scrollCheck(
        long,
        report,
        find.text(_recipient),
        'long recipient at 320 scale 2',
      );
      await _scrollCheck(
        long,
        report,
        find.text(_address),
        'long address at 320 scale 2',
      );
      await _capture(long, report, 'mh09_04a_320_s2_long');
    } catch (error) {
      report.fail('mh09_04a_320_s2_long execution: $error');
      await _capture(long, report, 'mh09_04a_320_s2_long_failure');
    } finally {
      await long.close();
    }

    for (final scale in [1.5, 2.0]) {
      final landscape = Mh09AuditHarness(tester);
      final tag = scale == 1.5 ? '1_5' : '2';
      try {
        await landscape.open(
          size: const Size(844, 390),
          scale: scale,
          record: 0,
        );
        for (final key in ['mh09-action-reject', 'mh09-action-confirm']) {
          await _scrollCheck(
            landscape,
            report,
            find.byKey(ValueKey(key)),
            '$key landscape scale $scale',
          );
        }
        await _capture(landscape, report, 'mh09_04a_844x390_s${tag}_footer');
      } catch (error) {
        report.fail('mh09_04a_844x390_s$tag execution: $error');
      } finally {
        await landscape.close();
      }
    }

    await report.save();
    expect(
      report.failures,
      isEmpty,
      reason: 'Scenario report was saved before assertion.',
    );
  });
}
