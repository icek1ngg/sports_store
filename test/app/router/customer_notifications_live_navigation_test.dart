import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sports_store/app/integration/production_feature_composition.dart';
import 'package:sports_store/app/router/app_router.dart';
import 'package:sports_store/app/sports_store_app.dart';
import 'package:sports_store/app/shells/sports_store_shell.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/chat/presentation/pages/conversation_list_screen.dart';
import 'package:sports_store/features/notifications/presentation/pages/notifications_page.dart';

import '../../features/support/operational_supabase_fixture.dart';

const _customer = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 200 && !ready(); i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(ready(), isTrue);
}

void main() {
  testWidgets(
    'customer catalog to chat to production notifications preserves navigator keys',
    (tester) async {
      final client = (await tester.runAsync(
        () => fixtureClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {
                'id': _customer,
                'role': 'customer',
                'full_name': 'QA Customer',
                'phone': null,
              },
            ]);
          }
          if (path.endsWith('/notifications') && request.method == 'HEAD') {
            return http.Response(
              '',
              200,
              request: request,
              headers: {'content-range': '*/0'},
            );
          }
          if (path.endsWith('/categories') ||
              path.endsWith('/products') ||
              path.endsWith('/product_variants') ||
              path.endsWith('/list_chat_conversations') ||
              path.endsWith('/notifications')) {
            return jsonResponse(request, []);
          }
          throw StateError('Unexpected fixture path $path');
        }, userId: _customer),
      ))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...productionFeatureOverrides,
            supabaseClientProvider.overrideWithValue(client),
          ],
          child: const SportsStoreApp(),
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await tester.runAsync(client.dispose);
      });
      final router = ProviderScope.containerOf(
        tester.element(find.byType(SportsStoreApp)),
      ).read(appRouterProvider);
      router.go('/customer/products');
      await _until(
        tester,
        () => find
            .widgetWithText(NavigationDestination, 'Tài khoản')
            .evaluate()
            .isNotEmpty,
      );
      await tester.tap(find.widgetWithText(NavigationDestination, 'Tài khoản'));
      await _until(
        tester,
        () => find.byType(SportsStoreAccountPage).evaluate().isNotEmpty,
      );
      await tester.tap(find.widgetWithText(ListTile, 'Hội thoại'));
      await _until(
        tester,
        () => find.byType(ConversationListScreen).evaluate().isNotEmpty,
      );
      // Shared route pushes must preserve the current imperative chat stack;
      // its old duplicate-shell toolbar no longer owns navigation.
      router.push('/notifications');
      await _until(
        tester,
        () => find.byType(NotificationsPage).evaluate().isNotEmpty,
      );
      await _until(
        tester,
        () => find.text('Chưa có thông báo').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(router.state.uri.path, '/notifications');
      router.pop();
      await _until(
        tester,
        () => find.byType(ConversationListScreen).evaluate().isNotEmpty,
      );
      expect(router.state.uri.path, '/chat');
    },
  );
}
