import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/ui_preview/mh08_preview_environment.dart';
import '../../tool/ui_preview/mh09_preview_scenario.dart';
import 'mh08_preview_test_support.dart';

export 'mh08_preview_test_support.dart';

Future<void> selectMh09PreviewScenario(
  WidgetTester tester,
  Mh09PreviewScenario scenario, {
  bool settle = true,
  bool settleBefore = true,
}) async {
  await tester.tap(find.byTooltip('MH09: chọn kịch bản'));
  if (settleBefore) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }
  final scenarioItem = find.byKey(ValueKey('mh09-preview-${scenario.name}'));
  await tester.ensureVisible(scenarioItem);
  await tester.tap(scenarioItem);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> searchManagerOrder(WidgetTester tester, String orderId) async {
  await tester.enterText(
    find.byKey(const ValueKey('mh08-search-field')),
    orderId,
  );
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

Future<Mh08PreviewEnvironment> openMh09PreviewOrder(
  WidgetTester tester, {
  int summaryIndex = 0,
}) async {
  final environment = Mh08PreviewEnvironment()..selectScreen('MH08');
  await pumpMh08Preview(tester, environment);
  await tester.pumpAndSettle();
  final orderId = environment.manager.summaries[summaryIndex].order.id;
  if (summaryIndex > 2) await searchManagerOrder(tester, orderId);
  await openManagerDetails(tester);
  await tester.pumpAndSettle();
  return environment;
}
