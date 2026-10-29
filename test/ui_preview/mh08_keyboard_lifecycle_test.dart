import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_kpi_strip.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh08/mh08_status_chips.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_feed.dart';

import '../../tool/ui_preview/mh08_preview_app.dart';
import '../../tool/ui_preview/mh08_preview_environment.dart';
import 'mh08_preview_test_support.dart';

const _searchKey = ValueKey<String>('mh08-search-field');
const _chipsKey = ValueKey<String>('mh08-status-chips-scroll');
const _pendingKpiKey = ValueKey<String>('mh08-kpi-value-Chờ xác nhận');
const _shippingKpiKey = ValueKey<String>('mh08-kpi-value-Đang giao');

const _viewports = <Size>[
  Size(320, 844),
  Size(360, 844),
  Size(390, 844),
  Size(412, 844),
  Size(844, 390),
];

void _configureView(WidgetTester tester, Size viewport, double scale) {
  tester.view
    ..physicalSize = viewport
    ..devicePixelRatio = 1
    ..padding = const FakeViewPadding()
    ..viewInsets = const FakeViewPadding();
  tester.platformDispatcher.textScaleFactorTestValue = scale;
}

void _resetView(WidgetTester tester) {
  tester.view
    ..resetPhysicalSize()
    ..resetDevicePixelRatio()
    ..resetPadding()
    ..resetViewInsets();
  tester.platformDispatcher.clearTextScaleFactorTestValue();
}

Future<void> _unmount(
  WidgetTester tester,
  Mh08PreviewEnvironment environment,
) async {
  try {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  } finally {
    environment.dispose();
  }
}

List<String> _orderIds(WidgetTester tester) => tester
    .widget<OrderFeed>(find.byType(OrderFeed))
    .orders
    .map((summary) => summary.order.id)
    .toList(growable: false);

void _expectHealthy(WidgetTester tester, String stage) {
  expect(tester.takeException(), isNull, reason: stage);
}

void _expectKpi(
  WidgetTester tester, {
  required int total,
  required int pending,
  required int shipping,
}) {
  expect(find.byType(Mh08KpiStrip), findsOneWidget);
  expect(find.text('$total đơn hàng'), findsOneWidget);
  expect(
    tester.getSemantics(find.byKey(_pendingKpiKey)),
    matchesSemantics(label: 'Chờ xác nhận: $pending'),
  );
  expect(
    tester.getSemantics(find.byKey(_shippingKpiKey)),
    matchesSemantics(label: 'Đang giao: $shipping'),
  );
}

Future<void> _expectKeyboardLayout(
  WidgetTester tester, {
  required double height,
  required double inset,
}) async {
  expect(find.byType(Mh08KpiStrip), findsNothing);
  final search = find.byKey(_searchKey);
  final chips = find.byKey(_chipsKey);
  expect(search, findsOneWidget);
  expect(chips, findsOneWidget);
  await tester.ensureVisible(search);
  await tester.ensureVisible(chips);

  final keyboardTop = height - inset;
  for (final finder in [search, chips]) {
    final rect = tester.getRect(finder);
    expect(rect.top, lessThan(keyboardTop));
    expect(rect.bottom, lessThanOrEqualTo(keyboardTop + 1));
  }
  final list = find.byType(ListView).last;
  expect(list, findsOneWidget);
  expect(tester.getRect(list).bottom, closeTo(keyboardTop, 1));
  _expectHealthy(tester, 'keyboard layout');
}

Future<void> _openKeyboard(WidgetTester tester, double inset) async {
  final search = find.byKey(_searchKey);
  await tester.ensureVisible(search);
  await tester.tap(search);
  tester.view.viewInsets = FakeViewPadding(bottom: inset);
  await tester.pumpAndSettle();
}

Future<void> _closeKeyboard(WidgetTester tester) async {
  tester.view.viewInsets = const FakeViewPadding();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> _selectActiveQuery(
  WidgetTester tester,
  Mh08PreviewEnvironment environment,
) async {
  final search = find.byKey(_searchKey);
  await tester.ensureVisible(search);
  await tester.tap(search);
  await tester.enterText(search, 'Nguyễn Minh Anh');
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();

  final chip = find.descendant(
    of: find.byType(Mh08StatusChips),
    matching: find.text('Chờ xác nhận'),
  );
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pumpAndSettle();
  expect(environment.manager.managerReads.last.search, 'Nguyễn Minh Anh');
  expect(environment.manager.managerReads.last.statuses, [
    OrderStatus.pendingConfirmation,
  ]);
}

Future<void> _runLifecycleCase(
  WidgetTester tester,
  Size viewport,
  double scale,
) async {
  _configureView(tester, viewport, scale);
  final environment = Mh08PreviewEnvironment()..selectScreen('MH08');
  final openInset = viewport.width < viewport.height ? 200.0 : 160.0;
  final reopenInset = viewport.width < viewport.height ? 216.0 : 176.0;
  try {
    await tester.pumpWidget(
      Mh08PreviewApp(showControls: false, environment: environment),
    );
    await tester.pumpAndSettle();
    await _selectActiveQuery(tester, environment);
    _expectKpi(tester, total: 1, pending: 1, shipping: 0);

    final readCount = environment.manager.managerReads.length;
    final query = environment.manager.managerReads.last;
    expect(
      tester
          .widget<Mh08StatusChips>(find.byType(Mh08StatusChips))
          .selectedStatus,
      OrderStatus.pendingConfirmation,
    );

    await _openKeyboard(tester, openInset);
    await _expectKeyboardLayout(
      tester,
      height: viewport.height,
      inset: openInset,
    );
    expect(find.text('1 đơn hàng'), findsNothing);
    expect(environment.manager.managerReads.length, readCount);

    await _closeKeyboard(tester);
    _expectKpi(tester, total: 1, pending: 1, shipping: 0);
    expect(
      tester.widget<TextField>(find.byKey(_searchKey)).controller!.text,
      'Nguyễn Minh Anh',
    );
    expect(
      tester
          .widget<Mh08StatusChips>(find.byType(Mh08StatusChips))
          .selectedStatus,
      OrderStatus.pendingConfirmation,
    );
    expect(environment.manager.managerReads.length, readCount);
    expect(environment.manager.managerReads.last, query);

    await _openKeyboard(tester, reopenInset);
    await _expectKeyboardLayout(
      tester,
      height: viewport.height,
      inset: reopenInset,
    );
    expect(find.text('1 đơn hàng'), findsNothing);
    expect(environment.manager.managerReads.length, readCount);

    await _closeKeyboard(tester);
    _expectKpi(tester, total: 1, pending: 1, shipping: 0);
    expect(environment.manager.managerReads.length, readCount);
    expect(environment.manager.managerReads.last, query);
    _expectHealthy(
      tester,
      'lifecycle ${viewport.width}x${viewport.height} s$scale',
    );
  } finally {
    await _unmount(tester, environment);
    _resetView(tester);
  }
}

void main() {
  testWidgets(
    'MH08-04B1 restores controls through keyboard open-close-reopen',
    (tester) async {
      for (final viewport in _viewports) {
        for (final scale in [1.0, 1.5, 2.0]) {
          await _runLifecycleCase(tester, viewport, scale);
        }
      }
    },
  );

  testWidgets('MH08-04B1 keyboard does not reset a paginated feed', (
    tester,
  ) async {
    const viewport = Size(390, 844);
    _configureView(tester, viewport, 1);
    final environment = Mh08PreviewEnvironment()..selectScreen('MH08');
    try {
      await tester.pumpWidget(
        Mh08PreviewApp(showControls: false, environment: environment),
      );
      await tester.pumpAndSettle();
      _expectKpi(tester, total: 10, pending: 2, shipping: 2);
      await loadManagerNextPage(tester, environment);

      final beforeIds = _orderIds(tester);
      final beforeReads = environment.manager.managerReads.length;
      final beforeCanLoadMore = tester
          .widget<OrderFeed>(find.byType(OrderFeed))
          .canLoadMore;
      expect(beforeIds.length, greaterThanOrEqualTo(6));

      await _openKeyboard(tester, 200);
      await _expectKeyboardLayout(tester, height: viewport.height, inset: 200);
      await _closeKeyboard(tester);
      _expectKpi(tester, total: 10, pending: 2, shipping: 2);

      await _openKeyboard(tester, 216);
      await _expectKeyboardLayout(tester, height: viewport.height, inset: 216);
      await _closeKeyboard(tester);

      expect(_orderIds(tester), beforeIds);
      expect(environment.manager.managerReads.length, beforeReads);
      expect(
        tester.widget<OrderFeed>(find.byType(OrderFeed)).canLoadMore,
        beforeCanLoadMore,
      );
      _expectKpi(tester, total: 10, pending: 2, shipping: 2);
      _expectHealthy(tester, 'pagination keyboard lifecycle');
    } finally {
      await _unmount(tester, environment);
      _resetView(tester);
    }
  });
}
