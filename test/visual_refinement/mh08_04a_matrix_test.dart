import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_kpi_strip.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_feed.dart';

import '../../tool/ui_preview/mh08_preview_app.dart';
import '../../tool/ui_preview/mh08_preview_environment.dart';
import 'mh08_04a_capture_helper.dart';

String _scaleTag(double value) => value.toString().replaceAll('.', '_');

Future<void> _settle(
  WidgetTester tester,
  Mh08AuditReport report,
  String stage,
) async {
  try {
    await tester.pumpAndSettle();
  } catch (error) {
    report.fail('$stage pumpAndSettle: $error');
  }
  report.collectExceptions(tester, stage);
}

Future<void> _settleKeyboard(
  WidgetTester tester,
  Mh08AuditReport report,
) async {
  for (var tick = 0; tick < 12; tick++) {
    await tester.pump(const Duration(milliseconds: 50));
    report.collectExceptions(tester, 'keyboard settle ${tick + 1}');
    if (find.byType(ListView).evaluate().isNotEmpty) return;
  }
  report.fail('keyboard bounded settle did not restore ListView');
}

Future<void> _resetChipScroll(WidgetTester tester) async {
  final chips = find.byKey(const ValueKey('mh08-status-chips-scroll'));
  final scrollables = find.descendant(
    of: chips,
    matching: find.byType(Scrollable),
  );
  if (scrollables.evaluate().isEmpty) return;
  final state = tester.state<ScrollableState>(scrollables.first);
  if (state.position.pixels != 0) {
    state.position.jumpTo(0);
    await tester.pump();
  }
}

Future<void> _capture(
  WidgetTester tester,
  Mh08AuditReport report,
  GlobalKey boundaryKey,
  String label,
) async {
  await _resetChipScroll(tester);
  await report.capture(tester, boundaryKey, label);
}

Future<void> _auditHorizontalChips(
  WidgetTester tester,
  Mh08AuditReport report,
) async {
  final chips = find.byKey(const ValueKey('mh08-status-chips-scroll'));
  final scrollables = find.descendant(
    of: chips,
    matching: find.byType(Scrollable),
  );
  if (scrollables.evaluate().isEmpty) {
    report.fail('horizontal chip Scrollable is missing');
    return;
  }
  final state = tester.state<ScrollableState>(scrollables.first);
  final before = state.position.pixels;
  final extent = state.position.maxScrollExtent;
  report.check('chips expose horizontal extent', extent > 0, '$extent');
  if (extent > 0) {
    await tester.ensureVisible(chips);
    await tester.pumpAndSettle();
    await tester.drag(chips, const Offset(-320, 0));
    await tester.pump();
    final after = state.position.pixels;
    report.check(
      'chips respond to horizontal gesture',
      after > before,
      '$before → $after',
    );
  }
  await _resetChipScroll(tester);
}

Future<void> _loadAllRows(WidgetTester tester, Mh08AuditReport report) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    final feeds = find.byType(OrderFeed);
    if (feeds.evaluate().isEmpty) {
      report.fail('OrderFeed is missing while loading rows');
      return;
    }
    final feed = tester.widget<OrderFeed>(feeds.first);
    if (feed.orders.length >= 10 && !feed.canLoadMore) {
      report.check('all ten rows loaded', true, 'loaded ${feed.orders.length}');
      return;
    }
    final lists = find.byType(ListView);
    if (lists.evaluate().isEmpty) {
      report.fail('MH08 list is missing while loading rows');
      return;
    }
    try {
      final scrollable = find.byType(Scrollable).last;
      tester
          .state<ScrollableState>(scrollable)
          .position
          .jumpTo(
            tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
          );
      await tester.pump(const Duration(milliseconds: 80));
      await _settle(tester, report, 'load page ${attempt + 1}');
    } catch (error) {
      report.fail('load page ${attempt + 1}: $error');
      return;
    }
  }
  final feed = tester.widget<OrderFeed>(find.byType(OrderFeed).first);
  report.check(
    'all ten rows loaded',
    feed.orders.length == 10 && !feed.canLoadMore,
    'loaded ${feed.orders.length}, canLoadMore=${feed.canLoadMore}',
  );
}

Future<void> _ensureVisible(
  WidgetTester tester,
  Mh08AuditReport report,
  Finder finder,
  String label,
) async {
  try {
    if (finder.evaluate().isEmpty) {
      final scrollable = find.byType(Scrollable).last;
      final state = tester.state<ScrollableState>(scrollable);
      state.position.jumpTo(0);
      await tester.pump();
      for (
        var attempt = 0;
        attempt < 24 && finder.evaluate().isEmpty;
        attempt++
      ) {
        state.position.jumpTo(
          (state.position.pixels + 420)
              .clamp(0, state.position.maxScrollExtent)
              .toDouble(),
        );
        await tester.pump();
      }
    }
    if (finder.evaluate().isEmpty) {
      report.fail('$label is missing');
      return;
    }
    await tester.ensureVisible(finder.first);
    await tester.pump();
  } catch (error) {
    report.fail('$label cannot be scrolled into view: $error');
  }
  report.collectExceptions(tester, label);
}

Future<void> _scrollToBottom(
  WidgetTester tester,
  Mh08AuditReport report,
) async {
  final scrollable = find.byType(Scrollable).last;
  final state = tester.state<ScrollableState>(scrollable);
  state.position.jumpTo(state.position.maxScrollExtent);
  await tester.pump();
  await _settle(tester, report, 'bottom scroll');
}

void _checkButton(
  WidgetTester tester,
  Mh08AuditReport report,
  String key,
  String label,
) {
  final finder = find.byKey(ValueKey<String>(key));
  if (finder.evaluate().isEmpty) {
    report.fail('$label action is missing');
    return;
  }
  final size = tester.getSize(finder.first);
  report.check(
    '$label hit target >=48',
    size.width >= 48 && size.height >= 48,
    '${size.width}x${size.height}',
  );
}

Future<void> _auditCase(
  WidgetTester tester,
  Mh08AuditReport report, {
  required double width,
  required double height,
  required double scale,
}) async {
  final prefix =
      'mh08_04a_${width.toInt()}x${height.toInt()}_s${_scaleTag(scale)}';
  report.beginCase(
    name: prefix,
    width: width,
    height: height,
    textScale: scale,
  );
  tester.view
    ..physicalSize = Size(width, height)
    ..devicePixelRatio = 1
    ..padding = const FakeViewPadding()
    ..viewInsets = const FakeViewPadding();
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  final environment = Mh08PreviewEnvironment()..selectScreen('MH08');
  final boundaryKey = GlobalKey();
  try {
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: Mh08PreviewApp(showControls: false, environment: environment),
      ),
    );
    await _settle(tester, report, 'initial data');
    await _capture(tester, report, boundaryKey, '${prefix}_top');

    final chips = find.byKey(const ValueKey('mh08-status-chips-scroll'));
    report.check(
      'horizontal status chips',
      chips.evaluate().isNotEmpty &&
          tester.widget<SingleChildScrollView>(chips).scrollDirection ==
              Axis.horizontal,
    );
    await _auditHorizontalChips(tester, report);
    final kpi = find.byType(Mh08KpiStrip);
    if (kpi.evaluate().isEmpty) {
      report.fail('KPI strip is missing');
    } else {
      final kpiSize = tester.getSize(kpi.first);
      report.check(
        'KPI fits viewport',
        kpiSize.width <= width - 40.0 && kpiSize.height >= 1,
        '${kpiSize.width}x${kpiSize.height}',
      );
      report.check(
        'KPI reflows at large text scale',
        scale < 1.5 || kpiSize.height > 81,
        '${kpiSize.height}',
      );
    }

    await _ensureVisible(
      tester,
      report,
      find.byKey(const ValueKey('mh08-confirm')),
      'pending confirm action',
    );
    _checkButton(tester, report, 'mh08-confirm', 'confirm');
    _checkButton(tester, report, 'mh08-reject', 'reject');
    _checkButton(tester, report, 'mh08-open-order', 'details');
    await _capture(tester, report, boundaryKey, '${prefix}_pending_actions');

    await _loadAllRows(tester, report);
    final warning = environment.manager.summaries[5].warnings.single.message;
    final longName = environment.manager.summaries[8].customerDisplayName!;
    final longAddress = environment.manager.summaries[8].order.addressDetail;
    await _ensureVisible(tester, report, find.text(warning), 'warning card');
    report.check(
      'warning text is rendered',
      find.text(warning).evaluate().isNotEmpty,
    );
    if (width == 390) {
      await _capture(tester, report, boundaryKey, '${prefix}_warning');
    }
    await _ensureVisible(
      tester,
      report,
      find.text(longName),
      'long Vietnamese buyer',
    );
    report.check(
      'long Vietnamese buyer is rendered',
      find.text(longName).evaluate().isNotEmpty,
    );
    report.check(
      'long Vietnamese address is rendered',
      find.text(longAddress).evaluate().isNotEmpty,
    );
    if (width == 390) {
      await _capture(tester, report, boundaryKey, '${prefix}_longtext');
    }
    await _scrollToBottom(tester, report);
    await _capture(tester, report, boundaryKey, '${prefix}_bottom');

    tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
    await tester.pump();
    final listRect = tester.getRect(find.byType(ListView).last);
    report.check(
      'SafeArea bottom is respected',
      listRect.bottom <= height - 34 + 1,
      'list bottom ${listRect.bottom}',
    );
    if (width == 390) {
      await _capture(tester, report, boundaryKey, '${prefix}_safe_area');
    }
    tester.view.padding = const FakeViewPadding();
    await tester.pump();

    final search = find.byKey(const ValueKey('mh08-search-field'));
    await _ensureVisible(tester, report, search, 'search field');
    await tester.tap(search);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    await tester.enterText(search, 'Nguyễn Minh Anh');
    await tester.pump(const Duration(milliseconds: 400));
    await _settleKeyboard(tester, report);
    report.collectExceptions(tester, 'keyboard');
    report.check(
      'search remains available with keyboard',
      search.evaluate().isNotEmpty,
    );
    report.check(
      'KPI hides behind keyboard',
      find.byType(Mh08KpiStrip).evaluate().isEmpty,
    );
    final lists = find.byType(ListView);
    if (lists.evaluate().isEmpty) {
      report.fail('keyboard ListView is missing after bounded settle');
    } else {
      try {
        final keyboardList = tester.getRect(lists.last);
        report.check(
          'list respects keyboard inset',
          keyboardList.bottom <= height - 300 + 1,
          'list bottom ${keyboardList.bottom}',
        );
      } catch (error) {
        report.fail('keyboard list geometry: $error');
      }
    }
    await _capture(tester, report, boundaryKey, '${prefix}_keyboard');
  } catch (error) {
    report.fail('case execution: $error');
  } finally {
    if (report.currentHasFailures && mh08AuditWritesArtifacts) {
      try {
        await _capture(tester, report, boundaryKey, '${prefix}_failure');
      } catch (error) {
        report.fail('failure screenshot: $error');
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    environment.dispose();
  }
}

void main() {
  setUpAll(loadMh08AuditFonts);

  testWidgets('MH08-04A responsive matrix uses the real preview page', (
    tester,
  ) async {
    final report = Mh08AuditReport('mh08_04a_matrix_report.json');
    for (final viewport in [
      const Size(320, 844),
      const Size(360, 844),
      const Size(390, 844),
      const Size(412, 844),
      const Size(844, 390),
    ]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        await _auditCase(
          tester,
          report,
          width: viewport.width,
          height: viewport.height,
          scale: scale,
        );
      }
    }
    await tester.runAsync(report.finish);
    expect(
      report.globalFailures,
      isEmpty,
      reason: 'MH08-04A report was written before this assertion.',
    );
  });
}
