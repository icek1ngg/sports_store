import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_buyer_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_card_actions.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_header.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_kpi_strip.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_order_card.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_payment_section.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_status_chips.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_feed.dart';

import '../../tool/ui_preview/mh08_preview_app.dart';
import '../../tool/ui_preview/mh08_preview_environment.dart';
import 'mh08_04a_capture_helper.dart' show loadMh08AuditFonts;
import 'mh08_04b2_capture_helper.dart';

const _searchKey = ValueKey<String>('mh08-search-field');
const _statusLabels = <String>[
  'Tất cả',
  'Chờ xác nhận',
  'Đang chuẩn bị',
  'Chờ shipper nhận hàng',
  'Đang giao',
  'Chờ xử lý giao lại',
  'Chờ hàng về cửa hàng',
  'Đã giao hàng',
  'Đã hủy',
  'Đã từ chối',
  'Không giao được — đã nhận hàng về',
];

Future<void> _settle(
  WidgetTester tester,
  Mh08DensityReport report,
  String stage,
) async {
  try {
    await tester.pumpAndSettle();
  } catch (error) {
    report.fail('$stage pumpAndSettle: $error');
  }
  report.collectExceptions(tester, stage);
}

Future<void> _show(
  WidgetTester tester,
  Mh08DensityReport report,
  Finder finder,
  String label,
) async {
  try {
    final scrollable = find.byType(Scrollable).last;
    if (finder.evaluate().isEmpty && scrollable.evaluate().isNotEmpty) {
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pump();
    }
    for (
      var attempt = 0;
      attempt < 28 && finder.evaluate().isEmpty;
      attempt++
    ) {
      if (scrollable.evaluate().isEmpty) break;
      final state = tester.state<ScrollableState>(scrollable);
      state.position.jumpTo(
        (state.position.pixels + 420)
            .clamp(0, state.position.maxScrollExtent)
            .toDouble(),
      );
      await tester.pump();
    }
    if (finder.evaluate().isEmpty) {
      report.fail('$label is missing');
      return;
    }
    final card = find.ancestor(
      of: finder,
      matching: find.byType(Mh08OrderCard),
    );
    final target = label == 'first card actions' || card.evaluate().isEmpty
        ? finder
        : card;
    await tester.ensureVisible(target.first);
    await tester.pump();
  } catch (error) {
    report.fail('$label cannot be shown: $error');
  }
  report.collectExceptions(tester, label);
}

Future<void> _loadAllRows(WidgetTester tester, Mh08DensityReport report) async {
  for (var attempt = 0; attempt < 24; attempt++) {
    final feedFinder = find.byType(OrderFeed);
    if (feedFinder.evaluate().isEmpty) {
      report.fail('OrderFeed is missing while loading rows');
      return;
    }
    final feed = tester.widget<OrderFeed>(feedFinder.first);
    if (feed.orders.length == 10 && !feed.canLoadMore) {
      report.check('all ten manager rows are present', true);
      return;
    }
    final scrollable = find.byType(Scrollable).last;
    if (scrollable.evaluate().isEmpty) break;
    final state = tester.state<ScrollableState>(scrollable);
    state.position.jumpTo(state.position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 100));
    await _settle(tester, report, 'load page ${attempt + 1}');
  }
  final feed = tester.widget<OrderFeed>(find.byType(OrderFeed).first);
  report.check('all ten manager rows are present', feed.orders.length == 10);
}

void _recordGeometry(
  WidgetTester tester,
  Mh08DensityReport report,
  Size expectedSize, [
  double expectedDpr = 1,
  double expectedTextScale = 1,
]) {
  final scaffold = find.byType(Scaffold).last;
  if (scaffold.evaluate().isEmpty) {
    report.fail('viewport MediaQuery is missing');
  } else {
    final media = MediaQuery.of(tester.element(scaffold));
    final actualScale = media.textScaler.scale(1);
    final sizeOk =
        (media.size.width - expectedSize.width).abs() < .01 &&
        (media.size.height - expectedSize.height).abs() < .01;
    final dprOk = (media.devicePixelRatio - expectedDpr).abs() < .01;
    final scaleOk = (actualScale - expectedTextScale).abs() < .01;
    report.check(
      'actual viewport ${expectedSize.width}x${expectedSize.height}',
      sizeOk && dprOk && scaleOk,
      '${media.size.width}x${media.size.height} @${media.devicePixelRatio} '
          'scale=$actualScale',
    );
  }
  report.region(tester, 'feed_top', find.byType(OrderFeed));
  report.region(tester, 'header', find.byType(Mh08Header));
  report.region(tester, 'search', find.byKey(_searchKey));
  report.region(tester, 'kpi', find.byType(Mh08KpiStrip));
  report.region(
    tester,
    'chips',
    find.byKey(const ValueKey('mh08-status-chips-scroll')),
  );
  report.region(tester, 'first_card', find.byType(Mh08OrderCard));
  report.region(tester, 'buyer', find.byType(Mh08BuyerSection));
  report.region(
    tester,
    'item_preview',
    find.byKey(const ValueKey('mh08-item-preview')),
  );
  report.region(tester, 'payment', find.byType(Mh08PaymentSection));
  report.region(tester, 'actions', find.byType(Mh08CardActions));
  report.region(
    tester,
    'details',
    find.byKey(const ValueKey('mh08-open-order')),
  );

  report.textStyle(tester, 'header_title', find.text('ĐƠN HÀNG'));
  report.textStyle(tester, 'brand', find.text('VN ATHLETICS'));
  final cardFinder = find.byType(Mh08OrderCard);
  if (cardFinder.evaluate().isNotEmpty) {
    final card = tester.widget<Mh08OrderCard>(cardFinder.first);
    report.textStyle(
      tester,
      'first_card_title',
      find.text(card.summary.order.id),
    );
  }
}

void _checkControls(WidgetTester tester, Mh08DensityReport report) {
  report.check(
    'search field is rendered',
    find.byKey(_searchKey).evaluate().isNotEmpty,
  );
  report.check(
    'search hint is intact',
    find.text('Mã đơn hoặc tên khách hàng...').evaluate().isNotEmpty,
  );
  report.check(
    'status chips are rendered',
    find.byType(Mh08StatusChips).evaluate().isNotEmpty,
  );
  for (final label in _statusLabels) {
    report.check(
      'status label $label is intact',
      find.text(label).evaluate().isNotEmpty,
    );
  }
  report.check(
    'total count is intact',
    find.text('10 đơn hàng').evaluate().isNotEmpty,
  );
  for (final item in const <MapEntry<String, String>>[
    MapEntry('Chờ xác nhận', 'Chờ xác nhận: 2'),
    MapEntry('Đang giao', 'Đang giao: 2'),
  ]) {
    final finder = find.byKey(ValueKey('mh08-kpi-value-${item.key}'));
    if (finder.evaluate().isEmpty) {
      report.check('${item.key} KPI count is intact', false);
      continue;
    }
    final label = tester.getSemantics(finder.first).label;
    report.check('${item.key} KPI count is intact', label == item.value, label);
  }
}

Future<Mh08PreviewEnvironment> _mount(
  WidgetTester tester, {
  required Size physicalSize,
  required double devicePixelRatio,
  required double textScale,
  required GlobalKey boundaryKey,
}) async {
  tester.view
    ..physicalSize = physicalSize
    ..devicePixelRatio = devicePixelRatio
    ..padding = const FakeViewPadding()
    ..viewInsets = const FakeViewPadding();
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  final environment = Mh08PreviewEnvironment()..selectScreen('MH08');
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: Mh08PreviewApp(showControls: false, environment: environment),
    ),
  );
  return environment;
}

Future<void> _unmount(
  WidgetTester tester,
  Mh08PreviewEnvironment environment,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  environment.dispose();
}

void main() {
  setUpAll(loadMh08AuditFonts);
  testWidgets('MH08-04B2 real preview density renderer', (tester) async {
    final report = Mh08DensityReport();
    Mh08PreviewEnvironment? environment;
    try {
      var boundaryKey = GlobalKey();
      environment = await _mount(
        tester,
        physicalSize: const Size(390, 844),
        devicePixelRatio: 1,
        textScale: 1,
        boundaryKey: boundaryKey,
      );
      report.beginCase(
        name: 'mh08_04b2_390x844_s1_data',
        width: 390,
        height: 844,
        devicePixelRatio: 1,
        textScale: 1,
      );
      await _settle(tester, report, '390 data');
      _recordGeometry(tester, report, const Size(390, 844));
      report.check(
        'first fixture card is shorter than baseline580',
        tester.getSize(find.byType(Mh08OrderCard).first).height < 580,
      );
      _checkControls(tester, report);
      await report.capture(tester, boundaryKey, '390x844_s1_top');
      await _show(tester, report, find.byType(Mh08OrderCard), 'first card');
      await report.capture(tester, boundaryKey, '390x844_s1_firstcard');
      await _show(
        tester,
        report,
        find.byKey(const ValueKey('mh08-confirm')),
        'first card actions',
      );
      await report.capture(
        tester,
        boundaryKey,
        '390x844_s1_actions_bottomcard',
      );
      await _loadAllRows(tester, report);
      await _show(
        tester,
        report,
        find.text('Áo jersey bóng đá'),
        'multiproduct row',
      );
      report.check(
        'multiproduct detail remains intact',
        find.text('Và 1 dòng sản phẩm khác').evaluate().isNotEmpty,
      );
      await report.capture(tester, boundaryKey, '390x844_s1_multiproduct');
      await _show(
        tester,
        report,
        find.text(
          'Cửa hàng thể thao Thành phố Hà Nội – Bộ phận mua sắm doanh nghiệp',
        ),
        'long buyer',
      );
      report.check(
        'long address remains intact',
        find
            .text(
              'Tầng 7, tòa nhà thể thao Thành phố Hà Nội, 18 phố Huế, quận Hai Bà Trưng, Hà Nội',
            )
            .evaluate()
            .isNotEmpty,
      );
      await report.capture(tester, boundaryKey, '390x844_s1_longbuyer_address');
      await _show(
        tester,
        report,
        find.text('Giao hàng thất bại, cần xử lý giao lại.'),
        'warning row',
      );
      await report.capture(tester, boundaryKey, '390x844_s1_warning');
      final list = find.byType(Scrollable).last;
      final listState = tester.state<ScrollableState>(list);
      listState.position.jumpTo(listState.position.maxScrollExtent);
      await _settle(tester, report, 'bottom list');
      await report.capture(tester, boundaryKey, '390x844_s1_bottomlist');
      await _show(tester, report, find.byKey(_searchKey), 'search field');
      await tester.tap(find.byKey(_searchKey));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      await tester.enterText(find.byKey(_searchKey), 'Nguyễn Minh Anh');
      await tester.pump(const Duration(milliseconds: 400));
      await _settle(tester, report, 'keyboard');
      final queryText = tester
          .widget<TextField>(find.byKey(_searchKey))
          .controller
          ?.text;
      report.check(
        'query text remains intact',
        queryText == 'Nguyễn Minh Anh',
        queryText,
      );
      report.check(
        'keyboard hides KPI strip',
        find.byType(Mh08KpiStrip).evaluate().isEmpty,
      );
      await report.capture(tester, boundaryKey, '390x844_s1_keyboard');
      await _unmount(tester, environment);
      environment = await _mount(
        tester,
        physicalSize: const Size(640, 1688),
        devicePixelRatio: 2,
        textScale: 2,
        boundaryKey: boundaryKey = GlobalKey(),
      );
      report.beginCase(
        name: 'mh08_04b2_320x844_s2_data',
        width: 320,
        height: 844,
        devicePixelRatio: 2,
        textScale: 2,
      );
      await _settle(tester, report, '320 scale2 data');
      _recordGeometry(tester, report, const Size(320, 844), 2, 2);
      await report.capture(tester, boundaryKey, '320x844_s2_top');
      await _unmount(tester, environment);
      environment = await _mount(
        tester,
        physicalSize: const Size(844, 390),
        devicePixelRatio: 1,
        textScale: 1,
        boundaryKey: boundaryKey = GlobalKey(),
      );
      report.beginCase(
        name: 'mh08_04b2_844x390_landscape',
        width: 844,
        height: 390,
        devicePixelRatio: 1,
        textScale: 1,
      );
      await _settle(tester, report, 'landscape data');
      _recordGeometry(tester, report, const Size(844, 390));
      await report.capture(tester, boundaryKey, '844x390_s1_top');
    } catch (error) {
      report.fail('renderer execution: $error');
    } finally {
      if (environment != null) {
        await _unmount(tester, environment);
      }
    }
    await tester.runAsync(report.finish);
    expect(
      report.globalFailures,
      isEmpty,
      reason: 'MH08-04B2 report was written before this assertion.',
    );
  });
}
