import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/domain/models/order_operation.dart';
import 'package:sports_store/features/orders/presentation/widgets/mh09/mh09_action_footer.dart';

import '../../tool/ui_preview/mh09_preview_scenario.dart';
import '../features/orders/presentation/widgets/mh09/mh09_02b_test_support.dart';
import 'mh09_04a_test_support.dart';

const _artifactDirectory = 'docs/features/mh09/artifacts/visual_04b1';
const _rejectKey = ValueKey<String>('mh09-action-reject');
const _confirmKey = ValueKey<String>('mh09-action-confirm');
const _cancelKey = ValueKey<String>('mh09-action-manager-cancel');
const _pink = Color(0xffffdad6);
const _ink = Color(0xff111111);

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  final high = a > b ? a : b;
  final low = a < b ? a : b;
  return (high + .05) / (low + .05);
}

Mh09ActionFooter _footer({
  bool confirm = false,
  bool reject = false,
  bool cancel = false,
  bool fresh = true,
  bool inScope = true,
  bool busy = false,
  ValueChanged<OrderOperation>? onAction,
}) => Mh09ActionFooter(
  capabilities: mh09Capabilities(
    confirm: confirm,
    reject: reject,
    cancel: cancel,
  ),
  isActionStateFresh: fresh,
  canActInCurrentScope: inScope,
  isBusy: busy,
  onAction: onAction,
);

bool _hasSemanticTap(WidgetTester tester, Finder finder) {
  final data = tester.getSemantics(finder).getSemanticsData();
  return data.actions & SemanticsAction.tap.index != 0;
}

Future<void> _capture04b1(Mh09AuditHarness harness, String name) async {
  await harness.tester.pump();
  await harness.tester.runAsync(() async {
    final context = harness.boundaryKey.currentContext;
    if (context == null) throw StateError('MH09 boundary is not mounted');
    final boundary = context.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final directory = Directory(_artifactDirectory)
      ..createSync(recursive: true);
    await File('${directory.path}/$name.png')
        .writeAsBytes(data.buffer.asUint8List());
    await File('${directory.path}/$name.capture.json').writeAsString(
      jsonEncode({
        'orderId': harness.id,
        'scenario': harness.environment.mh09.scenario.name,
        'viewport': [harness.size.width, harness.size.height],
        'dpr': 1,
        'textScale': harness.scale,
        'sameViewport': true,
        'kind': 'Flutter widget-test raster, NOT Android runtime',
        'fontsLoaded': true,
        'fontFamilies': ['Inter', 'BarlowCondensed', 'MaterialIcons'],
        'method': 'Actual Mh08PreviewApp(showControls:false), real MH08 push, local RepaintBoundary.toImage',
      }),
    );
    image.dispose();
  });
}

void main() {
  testWidgets('MH09-04B1 footer geometry and visual contrast', (tester) async {
    final harness = Mh09AuditHarness(tester);
    try {
      await harness.open();
      final rejectFinder = find.byKey(_rejectKey);
      final confirmFinder = find.byKey(_confirmKey);
      await harness.scrollTo(rejectFinder);
      final reject = tester.widget<OutlinedButton>(rejectFinder);
      final confirm = tester.widget<FilledButton>(confirmFinder);
      final rejectRect = tester.getRect(rejectFinder);
      final confirmRect = tester.getRect(confirmFinder);
      expect(rejectRect.height, closeTo(48, .01));
      expect(confirmRect.height, closeTo(48, .01));
      expect(rejectRect.top, closeTo(confirmRect.top, .5));
      expect(confirmRect.width, greaterThan(rejectRect.width));
      for (final entry in {
        rejectFinder: 'Từ chối đơn',
        confirmFinder: 'Xác nhận đơn hàng',
      }.entries) {
        final label = find.descendant(
          of: entry.key,
          matching: find.text(entry.value),
        );
        expect(label, findsOneWidget);
        expect(tester.widget<Text>(label).overflow, isNull);
      }
      final rejectForeground = reject.style!.foregroundColor!.resolve({})!;
      final rejectBackground = reject.style!.backgroundColor!.resolve({})!;
      expect(rejectBackground, _pink);
      expect(
        _contrast(rejectForeground, rejectBackground),
        greaterThanOrEqualTo(4.5),
      );
      expect(confirm.style!.foregroundColor!.resolve({}), Colors.white);
      expect(confirm.style!.backgroundColor!.resolve({}), _ink);
      await _capture04b1(harness, 'footer390');
    } finally {
      await harness.close();
    }
  });

  testWidgets('MH09-04B1 keeps three content headings and semantic data', (
    tester,
  ) async {
    final harness = Mh09AuditHarness(tester);
    final semantics = tester.ensureSemantics();
    const headings = [
      'Người mua và người nhận',
      'Sản phẩm trong đơn',
      'THANH TOÁN',
    ];
    try {
      await harness.open();
      var intendedHeaders = 0;
      for (final title in headings) {
        final heading = find.text(title);
        expect(heading, findsOneWidget);
        await harness.scrollTo(heading);
        final semanticHeading = find.bySemanticsLabel(title);
        expect(semanticHeading, findsOneWidget);
        final data = tester.getSemantics(semanticHeading).getSemanticsData();
        expect(data.label, title);
        expect(data.flagsCollection.isHeader, isTrue);
        intendedHeaders++;
        await _capture04b1(harness, switch (title) {
          'Người mua và người nhận' => 'recipientheading',
          'Sản phẩm trong đơn' => 'itemsheading',
          _ => 'paymentheading',
        });
        switch (title) {
          case 'Người mua và người nhận':
            final recipientChild = find.text('Người nhận đơn thể thao');
            await harness.scrollTo(recipientChild);
            expect(
              tester.getSemantics(recipientChild).getSemanticsData().label,
              contains('Người nhận đơn thể thao'),
            );
          case 'Sản phẩm trong đơn':
            final itemChild = find.text('Giày chạy bộ AirFlex');
            await harness.scrollTo(itemChild);
            expect(
              tester.getSemantics(itemChild).getSemanticsData().label,
              contains('Giày chạy bộ AirFlex'),
            );
          case 'THANH TOÁN':
            final totalText = find.text('1.960.000 ₫').first;
            await harness.scrollTo(totalText);
            final total = find.bySemanticsLabel('Tổng COD: 1.960.000 ₫');
            expect(total, findsOneWidget);
            expect(
              tester.getSemantics(total).getSemanticsData().label,
              'Tổng COD: 1.960.000 ₫',
            );
        }
      }
      expect(intendedHeaders, 3);
    } finally {
      semantics.dispose();
      await harness.close();
    }
  });

  testWidgets('MH09-04B1 footer capability and owner gates', (tester) async {
    final semantics = tester.ensureSemantics();
    final blockedCalls = <OrderOperation>[];
    Future<void> assertDisabled({
      required bool fresh,
      required bool scope,
      required bool busy,
      ValueChanged<OrderOperation>? callback,
    }) async {
      await pumpMh09(
        tester,
        _footer(
          reject: true,
          confirm: true,
          cancel: true,
          fresh: fresh,
          inScope: scope,
          busy: busy,
          onAction: callback,
        ),
      );
      for (final key in [_rejectKey, _confirmKey, _cancelKey]) {
        final data = tester.getSemantics(find.byKey(key)).getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.flagsCollection.isEnabled, Tristate.isFalse);
        expect(_hasSemanticTap(tester, find.byKey(key)), isFalse);
        await tester.tap(find.byKey(key));
        await tester.pump();
      }
    }

    try {
      await pumpMh09(tester, const Mh09ActionFooter());
      expect(find.byKey(_rejectKey), findsNothing);
      expect(find.byKey(_confirmKey), findsNothing);
      expect(find.byKey(_cancelKey), findsNothing);
      await assertDisabled(
        fresh: false,
        scope: true,
        busy: false,
        callback: blockedCalls.add,
      );
      await assertDisabled(
        fresh: true,
        scope: false,
        busy: false,
        callback: blockedCalls.add,
      );
      await assertDisabled(
        fresh: true,
        scope: true,
        busy: true,
        callback: blockedCalls.add,
      );
      await assertDisabled(fresh: true, scope: true, busy: false);
      expect(blockedCalls, isEmpty);

      final operations = <OrderOperation>[];
      await pumpMh09(
        tester,
        _footer(
          reject: true,
          confirm: true,
          cancel: true,
          onAction: operations.add,
        ),
      );
      expect(find.text('Hủy ngoại lệ'), findsOneWidget);
      await tester.tap(find.byKey(_rejectKey));
      await tester.tap(find.byKey(_confirmKey));
      await tester.tap(find.byKey(_cancelKey));
      expect(operations, [
        OrderOperation.reject,
        OrderOperation.confirm,
        OrderOperation.managerCancel,
      ]);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('MH09-04B1 integrated single capabilities stay distinct', (
    tester,
  ) async {
    final harness = Mh09AuditHarness(tester);
    try {
      await harness.open();
      await harness.scene(Mh09PreviewScenario.confirmOnly);
      expect(find.byKey(_confirmKey), findsOneWidget);
      expect(find.byKey(_rejectKey), findsNothing);
      expect(find.byKey(_cancelKey), findsNothing);
      await harness.scene(Mh09PreviewScenario.rejectOnly);
      expect(find.byKey(_rejectKey), findsOneWidget);
      expect(find.byKey(_confirmKey), findsNothing);
      expect(find.byKey(_cancelKey), findsNothing);
    } finally {
      await harness.close();
    }

    final exceptional = Mh09AuditHarness(tester);
    try {
      await exceptional.open(record: 2);
      await exceptional.scene(Mh09PreviewScenario.exceptionalCancel);
      expect(find.byKey(_cancelKey), findsOneWidget);
      expect(find.byKey(_rejectKey), findsNothing);
      expect(find.byKey(_confirmKey), findsNothing);
    } finally {
      await exceptional.close();
    }
  });

  testWidgets('MH09-04B1 integrated responsive footer and timeline', (
    tester,
  ) async {
    final cases = [
      (const Size(320, 844), 2.0, 'footer320scale2'),
      (const Size(844, 390), 1.5, 'landscape15'),
      (const Size(844, 390), 2.0, 'landscape2'),
    ];
    for (final entry in cases) {
      final harness = Mh09AuditHarness(tester);
      try {
        await harness.open(size: entry.$1, scale: entry.$2);
        await harness.scene(Mh09PreviewScenario.large);
        final lastTimeline = find.text('Đơn hàng được tạo');
        await harness.scrollTo(lastTimeline);
        expect(lastTimeline.hitTestable(), findsOneWidget);
        for (final key in [_rejectKey, _confirmKey]) {
          expect(find.byKey(key), findsOneWidget);
          expect(
            tester.getSize(find.byKey(key)).height,
            greaterThanOrEqualTo(48),
          );
        }
        expect(tester.takeException(), isNull);
        if (entry.$3 == 'footer320scale2') {
          await harness.scrollTo(find.byKey(_rejectKey));
          await _capture04b1(harness, entry.$3);
        }
      } finally {
        await harness.close();
      }
    }
  });
}
