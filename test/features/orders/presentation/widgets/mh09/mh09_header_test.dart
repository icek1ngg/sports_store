import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_header.dart';

import 'mh09_test_support.dart';

void main() {
  testWidgets('dispatches only parent callbacks without navigating itself', (
    tester,
  ) async {
    var backs = 0;
    var refreshes = 0;
    await pumpMh09(
      tester,
      Mh09Header(
        canPop: true,
        onBack: () => backs++,
        onRefresh: () => refreshes++,
      ),
      gutters: 0,
    );
    await tester.tap(find.byTooltip('Quay lại'));
    expect(backs, 1);
    expect(refreshes, 0);
    await tester.tap(find.byTooltip('Tải lại'));
    expect(refreshes, 1);
    expect(find.byType(Mh09Header), findsOneWidget);
  });

  for (final canPop in [false, true]) {
    testWidgets('back requires both canPop=$canPop and a callback', (
      tester,
    ) async {
      var calls = 0;
      await pumpMh09(
        tester,
        Mh09Header(canPop: canPop, onBack: canPop ? null : () => calls++),
        gutters: 0,
      );
      final back = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Quay lại',
      );
      expect(tester.widget<IconButton>(back).onPressed, isNull);
      await tester.tap(back);
      expect(calls, 0);
    });
  }

  testWidgets('busy refresh is disabled and exposes its progress label', (
    tester,
  ) async {
    var refreshes = 0;
    await pumpMh09(
      tester,
      Mh09Header(
        canPop: false,
        isRefreshing: true,
        onRefresh: () => refreshes++,
      ),
      gutters: 0,
    );
    final refresh = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Đang tải lại',
    );
    expect(tester.widget<IconButton>(refresh).onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(refresh);
    expect(refreshes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing refresh callback cannot dispatch an action', (
    tester,
  ) async {
    await pumpMh09(tester, const Mh09Header(canPop: false), gutters: 0);
    final refresh = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Tải lại',
    );
    expect(tester.widget<IconButton>(refresh).onPressed, isNull);
  });

  testWidgets('complete title has header semantics and Barlow typography', (
    tester,
  ) async {
    await pumpMh09(tester, const Mh09Header(canPop: false), gutters: 0);
    const title = 'CHI TIẾT ĐƠN HÀNG';
    expect(
      tester.getSemantics(find.bySemanticsLabel(title)),
      matchesSemantics(label: title, isHeader: true),
    );
    expect(
      tester.widget<Text>(find.text(title)).style?.fontFamily,
      'BarlowCondensed',
    );
    expect(find.byType(Tooltip), findsNWidgets(2));
    for (final button in find.byType(IconButton).evaluate()) {
      final size = tester.getSize(find.byWidget(button.widget));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
  });

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('header reflows at width$width scale$scale', (tester) async {
        await pumpMh09(
          tester,
          const Mh09Header(canPop: true),
          width: width,
          scale: scale,
          gutters: 0,
        );
        expect(tester.takeException(), isNull);
        final title = find.text('CHI TIẾT ĐƠN HÀNG');
        expect(tester.widget<Text>(title).maxLines, isNull);
        expect(tester.getCenter(title).dx, closeTo(width / 2, .01));
        expect(
          tester.getSize(find.byType(Mh09Header)).height,
          greaterThanOrEqualTo(64),
        );
      });
    }
  }
}
