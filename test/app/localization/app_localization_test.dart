import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/sports_store_app.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/main.dart';

import '../../features/support/operational_supabase_fixture.dart';

void main() {
  for (final app in <Widget>[
    const SportsStoreApp(),
    const StartupFailureApp(),
  ]) {
    testWidgets(
      '${app.runtimeType} keeps system controls Vietnamese on an English device',
      (tester) async {
        tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
        addTearDown(tester.platformDispatcher.clearLocaleTestValue);
        final client = (await tester.runAsync(
          () => fixtureClient(
            (request) async => jsonResponse(request, []),
            userId: null,
          ),
        ))!;
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(client.dispose);
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [supabaseClientProvider.overrideWithValue(client)],
            child: app,
          ),
        );
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(Scaffold).first);
        expect(Localizations.localeOf(context).languageCode, 'vi');
        final labels = MaterialLocalizations.of(context);
        expect(labels.backButtonTooltip, 'Quay lại');
        expect(labels.pasteButtonLabel, 'Dán');
        expect(labels.selectAllButtonLabel, 'Chọn tất cả');
      },
    );
  }
}
