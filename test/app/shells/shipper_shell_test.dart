import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sports_store/app/shells/shipper_shell.dart';
import 'package:sports_store/features/auth/domain/repositories/auth_repository.dart';
import 'package:sports_store/features/auth/presentation/view_models/auth_providers.dart';

class _AuthRepository implements AuthRepository {
  final completion = Completer<void>();
  int logoutCalls = 0;

  @override
  Future<void> logout() {
    logoutCalls++;
    return completion.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final succeeds in [true, false]) {
    testWidgets('logout busy and completion (success=$succeeds)', (
      tester,
    ) async {
      final repository = _AuthRepository();
      final router = GoRouter(
        initialLocation: '/shipper/tasks',
        routes: [
          GoRoute(
            path: '/shipper/tasks',
            builder: (_, state) => ShipperShell(
              role: 'shipper',
              location: state.uri,
              child: const Text('Nhiệm vụ riêng'),
            ),
          ),
          GoRoute(
            path: '/login',
            builder: (_, _) => const Scaffold(body: Text('Đăng nhập')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      final logout = find.byKey(const ValueKey('shipper-logout'));
      await tester.tap(logout);
      await tester.pump();
      expect(tester.widget<TextButton>(logout).onPressed, isNull);
      expect(repository.logoutCalls, 1);
      if (succeeds) {
        repository.completion.complete();
      } else {
        repository.completion.completeError(
          const AuthenticationFailure('Không thể đăng xuất. Vui lòng thử lại.'),
        );
      }
      await tester.pumpAndSettle();
      if (succeeds) {
        expect(router.state.uri.path, '/login');
        expect(find.text('Nhiệm vụ riêng'), findsNothing);
      } else {
        expect(router.state.uri.path, '/shipper/tasks');
        expect(
          find.text('Không thể đăng xuất. Vui lòng thử lại.'),
          findsOneWidget,
        );
        expect(tester.widget<TextButton>(logout).onPressed, isNotNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
