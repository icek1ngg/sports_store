import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../pages/mh17/mh17_page_test_support.dart';
import '../../../../../tool/ui_preview/preview_app.dart';

const captureSet = String.fromEnvironment('MH17_CAPTURE_SET');

Future<void> capture(WidgetTester tester, String name) async {
  if (captureSet.isEmpty) return;
  expect(['baseline', 'after', 'review'], contains(captureSet));
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('refactor-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(
      'docs/features/mh17/artifacts/structure_refactor/$captureSet/$name.png',
    );
    if (await file.exists()) throw StateError('Preserve previous capture');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    for (final font in {
      'Inter': 'assets/fonts/Inter-Variable.ttf',
      'BarlowCondensed': 'assets/fonts/BarlowCondensed-Bold.ttf',
      if (captureSet == 'review')
        'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  for (final scenario in [(390.0, 1.0), (320.0, 1.0), (320.0, 2.0)]) {
    testWidgets('real notification UI ${scenario.$1} text ${scenario.$2}', (
      tester,
    ) async {
      tester.view.physicalSize = Size(scenario.$1, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = PageNotifications();
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('refactor-capture'),
          child: host(repository, textScale: scenario.$2),
        ),
      );
      await settle(tester);
      repository.requests.single.result.complete(page([longRow]));
      repository.countRequests.single.complete(124);
      await tester.pumpAndSettle();
      expect(find.text(longRow.title), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'mh17_${scenario.$1.toInt()}_text${scenario.$2}');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final screen in ['MH07', 'MH08', 'MH09', 'MH17']) {
    testWidgets('existing Preview $screen preserves shared ThemeData', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const RepaintBoundary(
          key: ValueKey('refactor-capture'),
          child: UiPreviewApp(),
        ),
      );
      await tester.pumpAndSettle();
      if (screen != 'MH07') {
        await tester.tap(find.byTooltip('Chọn màn hình'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(screen));
        await tester.pumpAndSettle();
      }
      expect(find.text('DEMO UI · dữ liệu kiểm thử'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, '${screen.toLowerCase()}_preview');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
