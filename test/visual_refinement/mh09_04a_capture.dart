import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const mh09AuditDirectory = 'docs/features/mh09/artifacts/visual_04a';
bool _fontsLoaded = false;
Future<void> loadMh09AuditFonts() async {
  if (_fontsLoaded) return;
  for (final entry in {
    'Inter': 'assets/fonts/Inter-Variable.ttf',
    'BarlowCondensed': 'assets/fonts/BarlowCondensed-Bold.ttf',
    'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
  }.entries) {
    await (FontLoader(entry.key)..addFont(rootBundle.load(entry.value))).load();
  }
  _fontsLoaded = true;
}

Future<void> captureMh09Audit(
  WidgetTester tester,
  GlobalKey key,
  String name,
  Map<String, Object?> metadata,
) async {
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final directory = Directory(mh09AuditDirectory)
      ..createSync(recursive: true);
    await File('${directory.path}/$name.png')
        .writeAsBytes(bytes.buffer.asUint8List());
    await File('${directory.path}/$name.capture.json').writeAsString(
      jsonEncode({
        ...metadata,
        'kind': 'Flutter widget-test raster, NOT Android runtime',
        'fontsLoaded': _fontsLoaded,
        'fontFamilies': ['Inter', 'BarlowCondensed', 'MaterialIcons'],
        'method': 'Actual Mh08PreviewApp(showControls:false), real MH08 push, RepaintBoundary.toImage',
      }),
    );
    image.dispose();
  });
}
