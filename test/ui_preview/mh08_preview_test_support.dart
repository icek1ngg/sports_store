import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/ui_preview/mh08_manager_repository.dart';
import '../../tool/ui_preview/mh08_preview_app.dart';
import '../../tool/ui_preview/mh08_preview_environment.dart';

const previewScopeKey = ValueKey<String>('ui-preview-provider-scope');

Future<void> pumpMh08Preview(
  WidgetTester tester,
  Mh08PreviewEnvironment environment,
) async {
  await tester.pumpWidget(Mh08PreviewApp(environment: environment));
  await tester.pump();
}

ProviderContainer previewContainer(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
      listen: false,
    );

Future<void> selectPreviewScreen(WidgetTester tester, String screen) async {
  await tester.tap(find.byTooltip('Chọn màn hình'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(screen));
  await tester.pumpAndSettle();
}

Future<void> selectPreviewScenario(
  WidgetTester tester,
  Mh08PreviewScenario scenario,
) async {
  await tester.tap(find.byTooltip('Chọn trạng thái'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('preview-scenario-${scenario.name}')));
  await tester.pump();
}

Future<void> ensureVisibleInList(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 24 && finder.evaluate().isEmpty; attempt++) {
    final list = find.byType(ListView).last;
    if (list.evaluate().isEmpty) {
      await tester.pump();
      continue;
    }
    await tester.drag(list, const Offset(0, -420));
    await tester.pump();
  }
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> tapVisibleInList(WidgetTester tester, Finder finder) async {
  await ensureVisibleInList(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> openManagerConfirm(WidgetTester tester) =>
    tapVisibleInList(tester, find.byKey(const ValueKey('mh08-confirm')).first);

Future<void> openManagerReject(WidgetTester tester) =>
    tapVisibleInList(tester, find.byKey(const ValueKey('mh08-reject')).first);

Future<void> openManagerDetails(WidgetTester tester) => tapVisibleInList(
  tester,
  find.byKey(const ValueKey('mh08-open-order')).first,
);

Future<void> loadManagerNextPage(
  WidgetTester tester,
  Mh08PreviewEnvironment environment,
) async {
  final initialNextReads = environment.manager.managerReads
      .where((query) => query.cursor != null)
      .length;
  for (
    var attempt = 0;
    attempt < 24 &&
        environment.manager.managerReads
                .where((query) => query.cursor != null)
                .length ==
            initialNextReads;
    attempt++
  ) {
    final list = find.byType(ListView).last;
    if (list.evaluate().isEmpty) {
      await tester.pump();
      continue;
    }
    await tester.drag(list, const Offset(0, -420));
    await tester.pump();
  }
  await tester.pumpAndSettle();
  final nextReads = environment.manager.managerReads
      .where((query) => query.cursor != null)
      .length;
  if (nextReads == initialNextReads) {
    throw TestFailure('MH08 preview did not request a next page.');
  }
}

Future<void> disposeMh08Preview(
  WidgetTester tester,
  Mh08PreviewEnvironment environment,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  environment.dispose();
}
