import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'mh09_04a_test_support.dart';

const mh09B2Phase = String.fromEnvironment(
  'MH09_CAPTURE_PHASE',
  defaultValue: 'final',
);
const mh09B2Directory = 'docs/features/mh09/artifacts/visual_04b2';

Map<String, double> mh09B2Rect(Rect rect) => {
  'x': rect.left,
  'y': rect.top,
  'width': rect.width,
  'height': rect.height,
};

Future<void> captureMh09B2(Mh09AuditHarness harness, String name) async {
  await harness.tester.pump();
  await harness.tester.runAsync(() async {
    final render =
        harness.boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final directory = Directory('$mh09B2Directory/$mh09B2Phase')
      ..createSync(recursive: true);
    await File('${directory.path}/$name.png')
        .writeAsBytes(bytes.buffer.asUint8List());
    await File('${directory.path}/$name.capture.json').writeAsString(
      jsonEncode({
        'phase': mh09B2Phase,
        'orderId': harness.id,
        'scenario': harness.environment.mh09.scenario.name,
        'viewport': [harness.size.width, harness.size.height],
        'dpr': 1,
        'textScale': harness.scale,
        'fontsLoaded': true,
        'fontFamilies': ['Inter', 'BarlowCondensed', 'MaterialIcons'],
        'kind': 'Flutter widget-test raster, NOT Android runtime',
        'method':
            'Actual stable Preview, real MH08 push, RepaintBoundary.toImage',
      }),
    );
    image.dispose();
  });
}

void saveMh09B2Geometry(String name, Map<String, Object?> data) {
  final file = File('$mh09B2Directory/$mh09B2Phase/$name.json');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
}
