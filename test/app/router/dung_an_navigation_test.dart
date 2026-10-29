import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/router/app_router.dart';
import 'package:sports_store/app/sports_store_app.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/catalog/presentation/pages/product_management_screen.dart';
import 'package:sports_store/features/chat/presentation/pages/conversation_list_screen.dart';

import '../../features/support/operational_supabase_fixture.dart';

const manager = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const customer = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

Future<void> until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 150 && !ready(); i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(ready(), isTrue);
}

void main() {
  testWidgets(
    'manager navigation uses live repositories; sign out removes private UI',
    (tester) async {
      final calls = <String>[];
      final client = (await tester.runAsync(
        () => fixtureClient((request) async {
          calls.add(request.url.path);
          if (request.url.path.endsWith('/profiles')) {
            if (request.url.queryParameters['select'] == 'role') {
              return jsonResponse(request, {'role': 'manager'});
            }
            return jsonResponse(request, [
              {
                'id': manager,
                'role': 'manager',
                'full_name': 'Quản lý',
                'phone': null,
              },
            ]);
          }
          if (request.url.path.endsWith('/categories') ||
              request.url.path.endsWith('/products') ||
              request.url.path.endsWith('/product_variants') ||
              request.url.path.endsWith('/list_chat_conversations')) {
            return jsonResponse(request, []);
          }
          if (request.url.path.endsWith('/logout')) {
            return jsonResponse(request, {});
          }
          throw StateError('Unexpected request ${request.url.path}');
        }, userId: manager),
      ))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [supabaseClientProvider.overrideWithValue(client)],
          child: const SportsStoreApp(),
        ),
      );
      await until(
        tester,
        () => find.text('Không có sản phẩm phù hợp.').evaluate().isNotEmpty,
      );
      expect(calls.any((p) => p.endsWith('/products')), isTrue);
      expect(calls.any((p) => p.endsWith('/profiles')), isTrue);
      final router = ProviderScope.containerOf(
        tester.element(find.byType(SportsStoreApp)),
      ).read(appRouterProvider);
      router.go('/chat');
      await until(
        tester,
        () => find.text('Chưa có hội thoại phù hợp.').evaluate().isNotEmpty,
      );
      expect(calls.any((p) => p.endsWith('/list_chat_conversations')), isTrue);
      expect(find.byType(ConversationListScreen), findsOneWidget);
      // Account changes must close imperative forms/sheets as well as route pages.
      showModalBottomSheet<void>(
        context: tester.element(find.byType(ConversationListScreen)),
        builder: (_) =>
            const SizedBox(height: 100, child: Text('Private manager draft')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Private manager draft'), findsOneWidget);
      await tester.runAsync(() => recoverFixtureSession(client, customer));
      await until(
        tester,
        () => find.text('Private manager draft').evaluate().isEmpty,
      );
      // Restore the manager and exercise the real logout button separately.
      await tester.runAsync(() => recoverFixtureSession(client, manager));
      await until(tester, () => find.text('Đăng xuất').evaluate().isNotEmpty);
      await tester.tap(find.text('Đăng xuất'));
      await until(tester, () => find.text('Đăng nhập').evaluate().isNotEmpty);
      expect(find.byType(ConversationListScreen), findsNothing);
      expect(find.byType(ProductManagementScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    },
  );

  testWidgets(
    'customer metadata cannot authorize manager products and can start own chat',
    (tester) async {
      var productReads = 0;
      final client = (await tester.runAsync(
        () => fixtureClient((request) async {
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {
                'id': customer,
                'role': 'customer',
                'full_name': 'Khách hàng',
                'phone': null,
              },
            ]);
          }
          if (request.url.path.endsWith('/products')) productReads++;
          if (request.url.path.endsWith('/list_chat_conversations')) {
            return jsonResponse(request, []);
          }
          return jsonResponse(request, {});
        }, userId: customer),
      ))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [supabaseClientProvider.overrideWithValue(client)],
          child: const SportsStoreApp(),
        ),
      );
      await until(
        tester,
        () => find.text('Liên hệ cửa hàng').evaluate().isNotEmpty,
      );
      final router = ProviderScope.containerOf(
        tester.element(find.byType(SportsStoreApp)),
      ).read(appRouterProvider);
      await tester.tap(find.byTooltip('Danh mục sản phẩm'));
      await until(tester, () => router.state.uri.path == '/customer/products');
      router.go('/');
      await until(
        tester,
        () => find.text('Liên hệ cửa hàng').evaluate().isNotEmpty,
      );
      router.go('/manager/products');
      await until(
        tester,
        () => find
            .text('Chỉ quản lý được truy cập màn sản phẩm.')
            .evaluate()
            .isNotEmpty,
      );
      expect(productReads, 0);
      router.go('/chat/not-a-uuid');
      await until(
        tester,
        () => find.text('Mã hội thoại không hợp lệ.').evaluate().isNotEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    },
  );
}
