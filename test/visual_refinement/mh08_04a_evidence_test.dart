import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_buyer_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_card_actions.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_header.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_kpi_strip.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_order_card.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_payment_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_feed.dart';
import 'package:sports_store/shared/widgets/async_content.dart';

import '../../tool/ui_preview/mh08_preview_app.dart';
import '../../tool/ui_preview/mh08_manager_repository.dart';
import '../../tool/ui_preview/mh08_preview_environment.dart';
import 'mh08_04a_capture_helper.dart';

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

Future<void> _loadAllRows(WidgetTester tester, Mh08AuditReport report) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    final feedFinder = find.byType(OrderFeed);
    if (feedFinder.evaluate().isEmpty) {
      report.fail('OrderFeed is missing in 390 reference');
      return;
    }
    final feed = tester.widget<OrderFeed>(feedFinder.first);
    if (feed.orders.length == 10 && !feed.canLoadMore) {
      report.check('390 reference loads ten rows', true);
      return;
    }
    try {
      final scrollable = find.byType(Scrollable).last;
      final state = tester.state<ScrollableState>(scrollable);
      state.position.jumpTo(state.position.maxScrollExtent);
      await tester.pump(const Duration(milliseconds: 80));
      await _settle(tester, report, '390 page ${attempt + 1}');
    } catch (error) {
      report.fail('390 page ${attempt + 1}: $error');
      return;
    }
  }
  final feed = tester.widget<OrderFeed>(find.byType(OrderFeed).first);
  report.check('390 reference loads ten rows', feed.orders.length == 10);
}

Future<void> _visible(
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
    report.fail('$label cannot be shown: $error');
  }
  report.collectExceptions(tester, label);
}

Future<void> _scrollToBottom(
  WidgetTester tester,
  Mh08AuditReport report,
) async {
  try {
    final scrollable = find.byType(Scrollable).last;
    final state = tester.state<ScrollableState>(scrollable);
    state.position.jumpTo(state.position.maxScrollExtent);
    await tester.pump();
    await _settle(tester, report, '390 bottom scroll');
  } catch (error) {
    report.fail('390 bottom scroll: $error');
  }
}

Future<void> _settleKeyboard(
  WidgetTester tester,
  Mh08AuditReport report,
) async {
  for (var tick = 0; tick < 12; tick++) {
    await tester.pump(const Duration(milliseconds: 50));
    report.collectExceptions(tester, '390 keyboard settle ${tick + 1}');
    if (find.byType(ListView).evaluate().isNotEmpty) return;
  }
  report.fail('390 keyboard bounded settle did not restore ListView');
}

void _record390Geometry(WidgetTester tester, Mh08AuditReport report) {
  report.region(tester, 'header', find.byType(Mh08Header));
  report.region(
    tester,
    'search',
    find.byKey(const ValueKey('mh08-search-field')),
  );
  report.region(tester, 'kpi', find.byType(Mh08KpiStrip));
  report.region(
    tester,
    'chips',
    find.byKey(const ValueKey('mh08-status-chips-scroll')),
  );
  report.region(tester, 'card', find.byType(Mh08OrderCard));
  report.region(
    tester,
    'item_preview',
    find.byKey(const ValueKey('mh08-item-preview')),
  );
  report.region(tester, 'actions', find.byType(Mh08CardActions));
  report.region(
    tester,
    'details',
    find.byKey(const ValueKey('mh08-open-order')),
  );
  report.region(tester, 'buyer', find.byType(Mh08BuyerSection));
  report.region(tester, 'payment', find.byType(Mh08PaymentSection));
  report.textStyle(tester, 'header_title', find.text('ĐƠN HÀNG'));
  report.textStyle(tester, 'brand', find.text('VN ATHLETICS'));
}

Future<void> _captureScenario(
  WidgetTester tester,
  Mh08PreviewEnvironment environment,
  Mh08AuditReport report,
  GlobalKey boundaryKey,
  Mh08PreviewScenario scenario,
  String label,
) async {
  report.beginCase(
    name: 'mh08_04a_390_reference_$label',
    width: 390,
    height: 844,
    textScale: 1,
  );
  environment.selectScenario(scenario);
  await tester.pump();
  if (scenario == Mh08PreviewScenario.loading) {
    await tester.pump(const Duration(milliseconds: 100));
  } else if (scenario == Mh08PreviewScenario.stale) {
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester, report, label);
  } else {
    await _settle(tester, report, label);
  }
  report.check('$label state is visible', switch (scenario) {
    Mh08PreviewScenario.loading =>
      find.byType(LoadingState).evaluate().isNotEmpty,
    Mh08PreviewScenario.empty =>
      find.text('Chưa có đơn hàng cần xử lý').evaluate().isNotEmpty,
    Mh08PreviewScenario.error => find.byType(ErrorState).evaluate().isNotEmpty,
    Mh08PreviewScenario.stale =>
      find.text('Dữ liệu có thể chưa cập nhật').evaluate().isNotEmpty,
    _ => false,
  });
  await report.capture(tester, boundaryKey, 'mh08_04a_390_$label');
}

void main() {
  setUpAll(loadMh08AuditFonts);

  testWidgets('MH08-04A 390 reference states and geometry', (tester) async {
    final report = Mh08AuditReport('mh08_04a_reference_report.json');
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding()
      ..viewInsets = const FakeViewPadding();
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    final environment = Mh08PreviewEnvironment()..selectScreen('MH08');
    final boundaryKey = GlobalKey();
    report.beginCase(
      name: 'mh08_04a_390_reference_data',
      width: 390,
      height: 844,
      textScale: 1,
    );
    try {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: Mh08PreviewApp(showControls: false, environment: environment),
        ),
      );
      await _settle(tester, report, '390 data');
      _record390Geometry(tester, report);
      await report.capture(tester, boundaryKey, 'mh08_04a_390_top');

      await _visible(
        tester,
        report,
        find.byKey(const ValueKey('mh08-confirm')),
        '390 first pending card',
      );
      await report.capture(tester, boundaryKey, 'mh08_04a_390_firstcard');
      await _loadAllRows(tester, report);
      final warning = environment.manager.summaries[5].warnings.single.message;
      final longName = environment.manager.summaries[8].customerDisplayName!;
      await _visible(tester, report, find.text(warning), '390 warning');
      await report.capture(tester, boundaryKey, 'mh08_04a_390_middle');
      await _visible(tester, report, find.text(longName), '390 long text');
      report.check(
        '390 long text is rendered',
        find.text(longName).evaluate().isNotEmpty,
      );
      await report.capture(tester, boundaryKey, 'mh08_04a_390_longtext');
      await _scrollToBottom(tester, report);
      await report.capture(tester, boundaryKey, 'mh08_04a_390_bottom');

      await _visible(
        tester,
        report,
        find.byKey(const ValueKey('mh08-confirm')),
        '390 confirm action',
      );
      await tester.tap(find.byKey(const ValueKey('mh08-confirm')).first);
      await _settle(tester, report, 'confirm dialog');
      report.check(
        'confirm dialog title',
        find.text('Xác nhận đơn hàng').evaluate().isNotEmpty,
      );
      await report.capture(tester, boundaryKey, 'mh08_04a_390_confirm');
      await tester.tap(find.text('Đóng'));
      await _settle(tester, report, 'close confirm dialog');

      await _visible(
        tester,
        report,
        find.byKey(const ValueKey('mh08-reject')),
        '390 reject action',
      );
      await tester.tap(find.byKey(const ValueKey('mh08-reject')).first);
      await _settle(tester, report, 'reject dialog');
      report.check(
        'reject reason field',
        find.byKey(const ValueKey('order-action-reason')).evaluate().isNotEmpty,
      );
      await report.capture(tester, boundaryKey, 'mh08_04a_390_reject');
      await tester.tap(find.text('Đóng'));
      await _settle(tester, report, 'close reject dialog');

      final search = find.byKey(const ValueKey('mh08-search-field'));
      await _visible(tester, report, search, '390 search');
      await tester.tap(search);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      await tester.enterText(search, 'Nguyễn Minh Anh');
      await tester.pump(const Duration(milliseconds: 400));
      await _settleKeyboard(tester, report);
      report.check(
        '390 keyboard hides KPI',
        find.byType(Mh08KpiStrip).evaluate().isEmpty,
      );
      await report.capture(tester, boundaryKey, 'mh08_04a_390_keyboard');
      tester.view.viewInsets = const FakeViewPadding();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      await _captureScenario(
        tester,
        environment,
        report,
        boundaryKey,
        Mh08PreviewScenario.loading,
        'loading',
      );
      await _captureScenario(
        tester,
        environment,
        report,
        boundaryKey,
        Mh08PreviewScenario.empty,
        'empty',
      );
      await _captureScenario(
        tester,
        environment,
        report,
        boundaryKey,
        Mh08PreviewScenario.error,
        'error',
      );
      await _captureScenario(
        tester,
        environment,
        report,
        boundaryKey,
        Mh08PreviewScenario.stale,
        'stale',
      );
      report.collectExceptions(tester, '390 reference final');
    } catch (error) {
      report.fail('390 reference execution: $error');
    } finally {
      if (report.currentHasFailures && mh08AuditWritesArtifacts) {
        try {
          await report.capture(tester, boundaryKey, 'mh08_04a_390_failure');
        } catch (error) {
          report.fail('390 failure screenshot: $error');
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      environment.dispose();
    }
    await tester.runAsync(report.finish);
    expect(
      report.globalFailures,
      isEmpty,
      reason: 'MH08-04A 390 report was written before this assertion.',
    );
  });
}
