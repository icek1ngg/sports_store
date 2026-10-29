import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const mh08_04b2ArtifactDirectory = 'docs/features/mh08/artifacts/visual_04b2';

bool get mh08_04b2WritesArtifacts =>
    Platform.environment['MH08_04B2_OUTPUT'] == '1';

String get mh08_04b2Phase {
  final value = Platform.environment['MH08_04B2_PHASE'] ?? 'baseline';
  return value == 'refined' ? 'refined' : 'baseline';
}

class Mh08DensityReport {
  Mh08DensityReport() : fileName = 'mh08_04b2_${mh08_04b2Phase}_report.json';

  final String fileName;
  final cases = <Map<String, dynamic>>[];
  final globalFailures = <String>[];
  Map<String, dynamic>? _current;

  void beginCase({
    required String name,
    required double width,
    required double height,
    required double devicePixelRatio,
    required double textScale,
  }) {
    _current = {
      'name': name,
      'viewport': {'width': width, 'height': height},
      'devicePixelRatio': devicePixelRatio,
      'textScale': textScale,
      'checks': <Map<String, dynamic>>[],
      'failures': <String>[],
      'screenshots': <String>[],
      'regions': <String, dynamic>{},
      'styles': <String, dynamic>{},
    };
    cases.add(_current!);
  }

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
    if (!mh08_04b2WritesArtifacts) return;
    await tester.runAsync(() async {
      final object = boundaryKey.currentContext?.findRenderObject();
      if (object is! RenderRepaintBoundary || !object.hasSize) {
        fail('$label: RepaintBoundary is unavailable');
        return;
      }
      final image = await object.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        fail('$label: PNG encoding returned no bytes');
      } else {
        await Directory(mh08_04b2ArtifactDirectory).create(recursive: true);
        final path =
            '$mh08_04b2ArtifactDirectory/mh08_04b2_${mh08_04b2Phase}_$label.png';
        await File(path).writeAsBytes(bytes.buffer.asUint8List());
      }
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
    final style = tester.widget<Text>(finder.first).style;
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
    if (!mh08_04b2WritesArtifacts) return;
    await Directory(mh08_04b2ArtifactDirectory).create(recursive: true);
    final payload = {
      'task': 'MH08-04B2',
      'phase': mh08_04b2Phase,
      'renderer': 'Mh08PreviewApp(showControls: false)',
      'outputFlag': 'MH08_04B2_OUTPUT=1',
      'phaseFlag': 'MH08_04B2_PHASE=baseline|refined',
      'cases': cases,
      'failures': globalFailures,
    };
    await File('$mh08_04b2ArtifactDirectory/$fileName')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
  }
}
