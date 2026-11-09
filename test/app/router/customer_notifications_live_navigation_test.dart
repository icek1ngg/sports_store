import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sports_store/app/integration/production_feature_composition.dart';
import 'package:sports_store/app/router/app_router.dart';
import 'package:sports_store/app/sports_store_app.dart';
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
              path.endsWith('/cart_items') ||
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
      await _until(
        tester,
        () =>
            find.byKey(const ValueKey('customer-tab-3')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const ValueKey('customer-tab-3')));
      await _until(
        tester,
        () => find.text('Liên hệ cửa hàng').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Liên hệ cửa hàng'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Liên hệ cửa hàng'));
      await _until(
        tester,
        () => find.byType(ConversationListScreen).evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('Thông báo'));
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
      final router = ProviderScope.containerOf(
        tester.element(find.byType(SportsStoreApp)),
      ).read(appRouterProvider);
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
