import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sports_store/app/router/app_router.dart';
import 'package:sports_store/app/sports_store_app.dart';
import 'package:sports_store/app/shells/store_management_shell.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/chat/presentation/pages/conversation_list_screen.dart';

import '../../features/support/operational_supabase_fixture.dart';

const _customerId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

Future<void> _until(
  WidgetTester tester,
  bool Function() condition, {
  required String description,
}) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for $description.');
}

bool _hasKey(String key) => find.byKey(ValueKey(key)).evaluate().isNotEmpty;

void main() {
  testWidgets(
    'customer catalog can return to account shell and logout without history',
    (tester) async {
      final requests = <http.Request>[];
      final client = (await tester.runAsync(
        () => fixtureClient((request) async {
          requests.add(request);
          final path = request.url.path;
          if (path.endsWith('/profiles')) {
            // The operational guard asks only for role, while Auth loads the
            // complete profile. Keep both read contracts explicit here.
            if (request.url.queryParameters['select'] == 'role') {
              return jsonResponse(request, {'role': 'customer'});
            }
            return jsonResponse(request, [
              {
                'id': _customerId,
                'role': 'customer',
                'full_name': 'Khách hàng thử nghiệm',
                'phone': '0901234567',
              },
            ]);
          }
          if (path.endsWith('/categories') ||
              path.endsWith('/products') ||
              path.endsWith('/product_variants') ||
              path.endsWith('/cart_items') ||
              path.endsWith('/list_chat_conversations')) {
            return jsonResponse(request, const <Object>[]);
          }
          if (path.endsWith('/logout')) return jsonResponse(request, {});
          throw StateError('Unexpected request $path');
        }, userId: _customerId),
      ))!;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [supabaseClientProvider.overrideWithValue(client)],
          child: const SportsStoreApp(),
        ),
      );
      await tester.pump();
      final router = ProviderScope.containerOf(
        tester.element(find.byType(SportsStoreApp)),
      ).read(appRouterProvider);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await tester.runAsync(client.dispose);
      });

      // Start directly at the operational route so this test does not get a
      // back-stack entry for the account shell.
      router.go('/customer/products');
      await _until(
        tester,
        () => _hasKey('catalog-products-empty-scroll'),
        description: 'empty customer catalog',
      );

      await tester.tap(find.byKey(const ValueKey('customer-tab-3')));
      await _until(
        tester,
        () => find.text('Liên hệ cửa hàng').evaluate().isNotEmpty,
        description: 'customer account sheet',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Liên hệ cửa hàng'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Liên hệ cửa hàng'));
      await _until(
        tester,
        () =>
            router.state.uri.path == '/chat' &&
            find.byType(StoreManagementShell).evaluate().isNotEmpty &&
            find.byType(ConversationListScreen).evaluate().isNotEmpty &&
            find.text('Đăng xuất').evaluate().isNotEmpty,
        description: 'customer account shell with chat and logout',
      );
      expect(
        find.descendant(
          of: find.byType(ConversationListScreen),
          matching: find.text('Hội thoại'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Đăng xuất'));
      await _until(
        tester,
        () =>
            router.state.uri.path == '/login' &&
            find.text('Đăng nhập').evaluate().isNotEmpty,
        description: 'login after customer logout',
      );
      expect(_hasKey('catalog-product-list'), isFalse);
      expect(_hasKey('customer-tab-3'), isFalse);
      expect(router.canPop(), isFalse);
      expect(
        requests.any((request) => request.url.path.endsWith('/logout')),
        isTrue,
      );
    },
  );
}
