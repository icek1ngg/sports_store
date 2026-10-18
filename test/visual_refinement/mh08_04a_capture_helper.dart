import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const mh08AuditArtifactDirectory = 'docs/features/mh08/artifacts/visual_04a';

bool get mh08AuditWritesArtifacts =>
    Platform.environment['MH08_04A_OUTPUT'] == '1';

Future<void> loadMh08AuditFonts() async {
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  await (FontLoader(
    'Inter',
  )..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'))).load();
  await (FontLoader(
    'BarlowCondensed',
  )..addFont(rootBundle.load('assets/fonts/BarlowCondensed-Bold.ttf'))).load();
}

class Mh08AuditReport {
  Mh08AuditReport(this.fileName);

  final String fileName;
  final cases = <Map<String, dynamic>>[];
  final globalFailures = <String>[];
  Map<String, dynamic>? _current;

  void beginCase({
    required String name,
    required double width,
    required double height,
    required double textScale,
  }) {
    _current = {
      'name': name,
      'viewport': {'width': width, 'height': height},
      'textScale': textScale,
      'checks': <Map<String, dynamic>>[],
      'failures': <String>[],
      'screenshots': <String>[],
      'regions': <String, dynamic>{},
      'styles': <String, dynamic>{},
    };
    cases.add(_current!);
  }

  bool get currentHasFailures =>
      ((_current?['failures'] as List<dynamic>?) ?? const []).isNotEmpty;

  void check(String name, bool passed, [String? detail]) {
    final entry = <String, dynamic>{'name': name, 'pass': passed};
    if (detail != null) entry['detail'] = detail;
    (_current!['checks'] as List<dynamic>).add(entry);
    if (!passed) fail('$name${detail == null ? '' : ': $detail'}');
  }

  void fail(String message) {
    final name = _current?['name'] ?? 'global';
    (_current?['failures'] as List<dynamic>?)?.add(message);
    globalFailures.add('$name: $message');
  }

  void collectExceptions(WidgetTester tester, String stage) {
    while (true) {
      final exception = tester.takeException();
      if (exception == null) return;
      fail('$stage: $exception');
    }
  }

  Future<void> capture(
    WidgetTester tester,
    GlobalKey boundaryKey,
    String label,
  ) async {
    collectExceptions(tester, 'before $label');
    (_current!['screenshots'] as List<dynamic>).add(label);
    await tester.pump();
    collectExceptions(tester, 'after $label');
    if (!mh08AuditWritesArtifacts) return;
    await tester.runAsync(() async {
      final object = boundaryKey.currentContext?.findRenderObject();
      if (object is! RenderRepaintBoundary || !object.hasSize) {
        fail('$label: RepaintBoundary is unavailable');
        return;
      }
      final image = await object.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(mh08AuditArtifactDirectory).create(recursive: true);
      await File('$mh08AuditArtifactDirectory/$label.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  void region(WidgetTester tester, String name, Finder finder) {
    if (finder.evaluate().isEmpty) {
      fail('$name region is missing');
      return;
    }
    final rect = tester.getRect(finder.first);
    (_current!['regions'] as Map<String, dynamic>)[name] = {
      'left': rect.left,
      'top': rect.top,
      'width': rect.width,
      'height': rect.height,
    };
  }

  void textStyle(WidgetTester tester, String name, Finder finder) {
    if (finder.evaluate().isEmpty) return;
    final widget = tester.widget<Text>(finder.first);
    final style = widget.style;
    if (style == null) return;
    (_current!['styles'] as Map<String, dynamic>)[name] = {
      'fontFamily': style.fontFamily,
      'fontSize': style.fontSize,
      'fontWeight': style.fontWeight?.value,
      'height': style.height,
      'letterSpacing': style.letterSpacing,
    };
  }

  Future<void> finish() async {
    if (!mh08AuditWritesArtifacts) return;
    await Directory(mh08AuditArtifactDirectory).create(recursive: true);
    final payload = {
      'task': 'MH08-04A',
      'renderer': 'Mh08PreviewApp(showControls: false)',
      'expectedCommand':
          'flutter test --no-pub test/visual_refinement/mh08_04a_*_test.dart',
      'outputFlag': 'MH08_04A_OUTPUT=1',
      'cases': cases,
      'failures': globalFailures,
    };
    await File('$mh08AuditArtifactDirectory/$fileName')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
  }
}
