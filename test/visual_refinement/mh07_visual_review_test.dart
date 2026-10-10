import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_action_dialog.dart';

import '../../tool/ui_preview/mh07_preview_app.dart';

void main() {
  testWidgets(
    'MH07 320/360/390/412 scale 1/1.5/2 screenshot and keyboard matrix',
    (tester) async {
      final boundaryKey = GlobalKey();
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      Future<void> capture(String name) async {
        await tester.pump();
        expect(tester.takeException(), isNull, reason: name);
        if (Platform.environment['UI_VISUAL_OUTPUT'] == '1') {
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final bitmap = await boundary.toImage(pixelRatio: 1);
            final bytes = await bitmap.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('docs/ui_review_artifacts/$name.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            bitmap.dispose();
          });
        }
      }

      for (final width in [320.0, 360.0, 390.0, 412.0]) {
        for (final scale in [1.0, 1.5, 2.0]) {
          tester.view.physicalSize = Size(width, 844);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundaryKey,
              child: const UiPreviewApp(showControls: false),
            ),
          );
          await tester.pumpAndSettle();
          final prefix =
              'mh07_flutter_${width.toInt()}_s${scale.toString().replaceAll('.', '_')}';
          await capture('${prefix}_top');
          await tester.ensureVisible(find.text('Xem chi tiết').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Xem chi tiết').first);
          await tester.pumpAndSettle();
          await capture('${prefix}_detail');
          final detailScroll = tester.state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ListView).last,
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          detailScroll.position.jumpTo(detailScroll.position.maxScrollExtent);
          await tester.pumpAndSettle();
          await capture('${prefix}_detail_bottom');
          Navigator.of(tester.element(find.byType(ListView).last)).pop();
          await tester.pumpAndSettle();
          await tester.drag(find.byType(ListView).first, const Offset(0, -700));
          await tester.pumpAndSettle();
          await capture('${prefix}_scroll');
          final listScroll = tester.state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ListView).first,
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          for (var page = 0; page < 6; page++) {
            listScroll.position.jumpTo(listScroll.position.maxScrollExtent);
            await tester.pumpAndSettle();
          }
          expect(find.text('Cần hỗ trợ về đơn hàng?'), findsOneWidget);
          await capture('${prefix}_bottom');
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      }
      tester.view.physicalSize = const Size(320, 844);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: const UiPreviewApp(showControls: false),
        ),
      );
      await tester.pumpAndSettle();
      await capture('mh07_flutter_safe_area');
      await tester.tap(find.byType(TextField));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.enterText(find.byType(TextField), 'AirFlex');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await capture('mh07_flutter_keyboard');
      expect(find.text('AirFlex'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'))).load();
    await (FontLoader('BarlowCondensed')
          ..addFont(rootBundle.load('assets/fonts/BarlowCondensed-Bold.ttf')))
        .load();
  });
  testWidgets(
    'MH07 nested dialog observes detail invalidation and session expiry',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const UiPreviewApp());
      await tester.pumpAndSettle();
      final changeScenario = tester
          .widget<PopupMenuButton<PreviewScenario>>(
            find.byWidgetPredicate(
              (widget) => widget is PopupMenuButton<PreviewScenario>,
            ),
          )
          .onSelected!;
      await tester.ensureVisible(find.text('Xem chi tiết').first);
      await tester.tap(find.text('Xem chi tiết').first);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Hủy đơn hàng'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Hủy đơn hàng'));
      await tester.pumpAndSettle();
      final dialog = tester.widget<OrderActionDialog>(
        find.byType(OrderActionDialog),
      );
      expect(dialog.sourceCache, isNotNull);
      dialog.sourceCache!.invalidate('orders/detail/${dialog.orderId}');
      await tester.pumpAndSettle();
      expect(
        find.text('Dữ liệu đã thay đổi. Làm mới trước khi tiếp tục.'),
        findsOneWidget,
      );
      changeScenario(PreviewScenario.expired);
      await tester.pumpAndSettle();
      expect(find.text('Không thể tiếp tục thao tác'), findsOneWidget);
      expect(find.text(dialog.orderId), findsNothing);
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
      expect(
        find.text('Chi tiết đơn hàng hiện không khả dụng.'),
        findsOneWidget,
      );
      final root = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
        listen: false,
      );
      expect(
        root.read(featureSessionScopeProvider).canReadPrivateData,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('MH07 real preview repeatedly mounts and closes detail routes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (var cycle = 0; cycle < 3; cycle++) {
      await tester.pumpWidget(const UiPreviewApp());
      await tester.pumpAndSettle();
      for (var modal = 0; modal < 3; modal++) {
        await tester.ensureVisible(find.text('Xem chi tiết').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Xem chi tiết').first);
        await tester.pumpAndSettle();
        expect(find.text('Chi tiết đơn hàng'), findsOneWidget);
        expect(tester.takeException(), isNull);
        Navigator.of(tester.element(find.text('Chi tiết đơn hàng'))).pop();
        await tester.pumpAndSettle();
        expect(find.text('Chi tiết đơn hàng'), findsNothing);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
