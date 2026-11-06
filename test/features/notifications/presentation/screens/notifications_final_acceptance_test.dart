import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../pages/mh17/mh17_page_test_support.dart';

const _capture = bool.fromEnvironment('MH17_FINAL_CAPTURE');

Future<void> _save(WidgetTester tester, String name) async {
  if (!_capture) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('acceptance-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(
      'docs/features/mh17/artifacts/final_acceptance/flutter_review/$name.png',
    );
    if (await file.exists()) throw StateError('Preserve existing screenshot');
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
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  testWidgets(
    'tile announces title and type once, keeps body/time/read action',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var opens = 0;
      var reads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotificationTile(
              key: const ValueKey('semantic-tile'),
              notification: row1,
              onTap: () => opens++,
              onMarkRead: () => reads++,
            ),
          ),
        ),
      );
      final label = tester
          .getSemantics(find.byKey(const ValueKey('semantic-tile')))
          .label;
      expect(RegExp(RegExp.escape(row1.title)).allMatches(label).length, 1);
      expect(RegExp('Đơn hàng').allMatches(label).length, 1);
      expect(label, startsWith('Chưa đọc.'));
      expect(label, contains(row1.body));
      expect(label, contains('08/10/2026 10:40'));
      expect(
        tester.getSemantics(find.byType(TextButton)).label,
        'Đánh dấu đã đọc',
      );
      await tester.tap(find.text('Đánh dấu đã đọc'));
      expect(reads, 1);
      expect(opens, 0);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('controlled loading, error and explicit retry to empty render', (
    tester,
  ) async {
    final repository = PageNotifications();
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('acceptance-capture'),
        child: host(repository),
      ),
    );
    await settle(tester);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    await _save(tester, 'controlled_loading');
    repository.requests.single.result.completeError(
      const AppFailure(code: AppFailure.network),
    );
    repository.countRequests.single.complete(0);
    await tester.pumpAndSettle();
    expect(find.text('Thử lại'), findsOneWidget);
    await _save(tester, 'controlled_error');
    final before = repository.requests.length;
    await tester.tap(find.text('Thử lại'));
    await settle(tester);
    expect(repository.requests.length, greaterThan(before));
    for (final request in repository.requests) {
      if (!request.result.isCompleted) request.result.complete(page([]));
    }
    for (final count in repository.countRequests) {
      if (!count.isCompleted) count.complete(0);
    }
    await tester.pumpAndSettle();
    expect(find.text('Chưa có thông báo'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _save(tester, 'controlled_empty');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final width in [320.0, 360.0, 390.0, 412.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('acceptance ${width.toInt()}dp text$scale full long row', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = PageNotifications();
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('acceptance-capture'),
            child: host(repository, textScale: scale),
          ),
        );
        await settle(tester);
        repository.requests.single.result.complete(page([longRow, row2]));
        repository.countRequests.single.complete(124);
        await tester.pumpAndSettle();
        expect(find.text('99+'), findsOneWidget);
        expect(find.text(longRow.title), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _save(tester, '${width.toInt()}_text${scale}_top');
        await tester.scrollUntilVisible(
          find.text(row2.title),
          250,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.ensureVisible(find.text(row2.title));
        await tester.pumpAndSettle();
        expect(find.text(row2.title).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _save(tester, '${width.toInt()}_text${scale}_bottom');
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets(
    'keyboard Tab activates focused unread filter; targets labelled',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = PageNotifications();
      await tester.pumpWidget(host(repository));
      await settle(tester);
      repository.requests.single.result.complete(page([row1]));
      repository.countRequests.single.complete(3);
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      var unreadFocused = false;
      for (var i = 0; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final node = FocusManager.instance.primaryFocus;
        final chip = find.ancestor(
          of: find.text('Chưa đọc'),
          matching: find.byType(ChoiceChip),
        );
        if (node?.context != null &&
            tester.element(chip).findRenderObject() ==
                node!.context!.findAncestorRenderObjectOfType<RenderBox>()) {
          unreadFocused = true;
          break;
        }
        if (node?.context != null) {
          var inside = false;
          node!.context!.visitAncestorElements((element) {
            if (element == tester.element(chip)) inside = true;
            return true;
          });
          if (inside) {
            unreadFocused = true;
            break;
          }
        }
      }
      expect(unreadFocused, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await settle(tester);
      expect(repository.requests.last.query.filter, NotificationFilter.unread);
      repository.requests.last.result.complete(page([row1]));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
