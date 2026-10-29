import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'mh09_04a_test_support.dart';

/// Collect findings before asserting, so failed audits retain their evidence.
class Mh09AuditReport {
  Mh09AuditReport(this.name);
  final String name;
  final failures = <String>[];
  final checks = <Map<String, Object?>>[];
  final regions = <String, Object?>{};
  final facts = <String, Object?>{};
  void check(String name, bool pass, [Object? detail]) {
    checks.add({'name': name, 'pass': pass, 'detail': detail?.toString()});
    if (!pass) fail('$name: $detail');
  }

  void fail(String message) => failures.add(message);
  void collect(WidgetTester tester, String stage) {
    Object? error;
    while ((error = tester.takeException()) != null) {
      fail('$stage: $error');
    }
  }

  void region(WidgetTester tester, String name, Finder finder) {
    if (finder.evaluate().isEmpty) {
      fail('Missing region $name');
      return;
    }
    final rect = tester.getRect(finder.first);
    regions[name] = {
      'x': rect.left,
      'y': rect.top,
      'width': rect.width,
      'height': rect.height,
    };
  }

  Future<void> save() async {
    final file = File('$mh09AuditDirectory/$name.report.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'name': name,
        'checks': checks,
        'failures': failures,
        'regions': regions,
        'pass': failures.isEmpty,
        'facts': facts,
      }),
    );
  }
}
