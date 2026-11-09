import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/router/app_router.dart';
import 'package:sports_store/app/sports_store_app.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/auth/data/email_confirmation_callback.dart';
import 'package:sports_store/features/auth/data/oauth_sign_in_callback.dart';
import 'package:sports_store/features/auth/domain/models/email_confirmation_result.dart';
import 'package:sports_store/features/auth/presentation/pages/email_confirmation_page.dart';
import 'package:sports_store/features/auth/presentation/view_models/auth_providers.dart';

import '../../features/support/operational_supabase_fixture.dart';

void main() {
  testWidgets('Google denial opens login with a safe notice instead of a 404', (
    tester,
  ) async {
    final incoming = Uri.parse(
      'https://example.test/#error=access_denied&error_description=private-diagnostic',
    );
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/error=access_denied&error_description=private-diagnostic';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final client = (await tester.runAsync(
      () => fixtureClient(
        (request) async => jsonResponse(request, []),
        userId: null,
      ),
    ))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          initialOAuthErrorProvider.overrideWithValue(
            OAuthSignInCallback.errorMessage(incoming),
          ),
        ],
        child: const SportsStoreApp(),
      ),
    );
    await tester.pumpAndSettle();
    final router = ProviderScope.containerOf(
      tester.element(find.byType(SportsStoreApp)),
    ).read(appRouterProvider);
    expect(router.state.uri.path, '/login');
    expect(
      find.text('Đăng nhập Google chưa hoàn tất. Vui lòng thử lại.'),
      findsOneWidget,
    );
    expect(find.text('Không tìm thấy trang.'), findsNothing);
    expect(find.byType(EmailConfirmationPage), findsNothing);
    expect(find.textContaining('private-diagnostic'), findsNothing);
    // Returning to a normal login must not resurrect the initial OAuth failure.
    router.go('/login');
    await tester.pumpAndSettle();
    expect(
      find.text('Đăng nhập Google chưa hoàn tất. Vui lòng thử lại.'),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(client.dispose);
  });

  for (final result in [
    EmailConfirmationResult.success,
    EmailConfirmationResult.expired,
  ]) {
    testWidgets(
      'startup $result overrides an auth error hash and stays visible on session changes',
      (tester) async {
        tester.binding.platformDispatcher.defaultRouteNameTestValue =
            '/error=access_denied&error_code=otp_expired';
        addTearDown(
          tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
        );
        final client = (await tester.runAsync(
          () => fixtureClient((request) async {
            if (request.url.path.endsWith('/profiles')) {
              return jsonResponse(request, [
                {
                  'id': shipperA,
                  'role': 'shipper',
                  'full_name': 'Shipper',
                  'phone': null,
                },
              ]);
            }
            return jsonResponse(request, []);
          }, userId: null),
        ))!;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              supabaseClientProvider.overrideWithValue(client),
              initialEmailConfirmationProvider.overrideWithValue(result),
            ],
            child: const SportsStoreApp(),
          ),
        );
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(SportsStoreApp)),
        );
        final router = container.read(appRouterProvider);
        expect(router.state.uri.path, EmailConfirmationCallback.path);
        expect(find.byType(EmailConfirmationPage), findsOneWidget);
        expect(find.text('Không tìm thấy trang.'), findsNothing);
        expect(
          find.text('Xác nhận email thành công!'),
          result == EmailConfirmationResult.success
              ? findsOneWidget
              : findsNothing,
        );

        // SDK session/profile events must not dismiss the confirmation notice.
        await tester.runAsync(() => recoverFixtureSession(client, shipperA));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, EmailConfirmationCallback.path);
        expect(find.byType(EmailConfirmationPage), findsOneWidget);

        await tester.tap(
          find.text(
            result == EmailConfirmationResult.success
                ? 'Tiếp tục'
                : 'Về đăng nhập',
          ),
        );
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '/shipper/tasks');

        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(client.dispose);
      },
    );
  }

  testWidgets(
    'opening a callback without a startup result does not claim success',
    (tester) async {
      final client = (await tester.runAsync(
        () => fixtureClient(
          (request) async => jsonResponse(request, []),
          userId: null,
        ),
      ))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [supabaseClientProvider.overrideWithValue(client)],
          child: const SportsStoreApp(),
        ),
      );
      await tester.pumpAndSettle();
      final router = ProviderScope.containerOf(
        tester.element(find.byType(SportsStoreApp)),
      ).read(appRouterProvider);
      router.go(EmailConfirmationCallback.path);
      await tester.pumpAndSettle();
      expect(find.text('Liên kết xác nhận không hợp lệ'), findsOneWidget);
      expect(find.text('Xác nhận email thành công!'), findsNothing);
      await tester.tap(find.text('Về đăng nhập'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/login');
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    },
  );
}
