import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/presentation/pages/mh09/mh09_detail_body.dart';

import '../../tool/ui_preview/mh08_preview_app.dart';
import '../../tool/ui_preview/mh08_preview_environment.dart';
import '../../tool/ui_preview/mh09_preview_scenario.dart';

import 'mh09_04a_capture.dart';
export 'mh09_04a_capture.dart' show mh09AuditDirectory;

class Mh09AuditHarness {
  Mh09AuditHarness(this.tester);
  final WidgetTester tester;
  final boundaryKey = GlobalKey();
  late Mh08PreviewEnvironment environment;
  Size size = const Size(390, 844);
  double scale = 1;
  int record = 0;
  EdgeInsets padding = EdgeInsets.zero;
  String get id => environment.manager.summaries[record].order.id;
  Finder get bodyScroll => find
      .descendant(
        of: find.byType(Mh09DetailBody),
        matching: find.byType(SingleChildScrollView),
      )
      .first;

  Future<void> rebuild() async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    final media = MediaQueryData.fromView(tester.view).copyWith(
      textScaler: TextScaler.linear(scale),
      padding: padding,
      viewPadding: padding,
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MediaQuery(
          data: media,
          child: Mh08PreviewApp(environment: environment, showControls: false),
        ),
      ),
    );
  }

  Future<void> open({
    Size size = const Size(390, 844),
    double scale = 1,
    int record = 0,
    EdgeInsets padding = EdgeInsets.zero,
  }) async {
    await tester.runAsync(loadMh09AuditFonts);
    environment = Mh08PreviewEnvironment()..selectScreen('MH08');
    this.record = record;
    await rebuild();
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('mh08-search-field')), id);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    final open = find.byKey(const ValueKey('mh08-open-order')).first;
    for (var n = 0; n < 12 && open.hitTestable().evaluate().isEmpty; n++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    await tester.tap(open);
    await tester.pumpAndSettle();
    this.size = size;
    this.scale = scale;
    this.padding = padding;
    await rebuild();
    await tester.pumpAndSettle();
  }

  Future<void> scene(Mh09PreviewScenario scene, {bool settle = true}) async {
    environment.selectMh09Scenario(scene);
    await tester.pump();
    if (settle && scene != Mh09PreviewScenario.unresolved) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> scrollTo(Finder target) async {
    final owners = find.ancestor(
      of: target.first,
      matching: find.byType(Scrollable),
    );
    if (owners.evaluate().isEmpty) {
      if (target.hitTestable().evaluate().isNotEmpty) return;
      throw TestFailure('Unreachable target without a scroll owner: $target');
    }
    final scroll = owners.first;
    for (var n = 0; n < 180; n++) {
      final viewport = tester.getRect(scroll).deflate(3);
      final rect = tester.getRect(target.first);
      final point = Offset(
        rect.center.dx,
        rect.height > viewport.height ? rect.top + 16 : rect.center.dy,
      );
      if (viewport.contains(point)) return;
      await tester.drag(
        scroll,
        Offset(
          0,
          (point.dy > viewport.center.dy ? -1 : 1) * viewport.height * .75,
        ),
      );
      await tester.pumpAndSettle();
    }
    throw TestFailure('Target unreachable after real scrolling: $target');
  }

  Future<void> capture(String name) async {
    await captureMh09Audit(tester, boundaryKey, name, {
      'orderId': id,
      'scenario': environment.mh09.scenario.name,
      'viewport': [size.width, size.height],
      'dpr': 1,
      'textScale': scale,
      'padding': [padding.left, padding.top, padding.right, padding.bottom],
      'viewInsetsBottom': tester.view.viewInsets.bottom,
    });
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    environment.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewInsets();
  }
}
