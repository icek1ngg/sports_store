import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/cod/presentation/pages/cod_route_page.dart';
import '../../features/auth/presentation/pages/register_screen.dart';
import '../../features/auth/presentation/view_models/auth_providers.dart';
import '../../features/chat/presentation/pages/conversation_detail_screen.dart';
import '../../features/cod/presentation/view_models/cod_providers.dart';
import '../../features/deliveries/data/repositories/operational_providers.dart';
import '../../features/deliveries/presentation/pages/delivery_route_pages.dart';
import '../../features/deliveries/presentation/view_models/delivery_providers.dart';
import '../shells/shipper_shell.dart';
import 'operational_route_guard.dart';
import 'dung_an_route_pages.dart';

/// Bảo can supply MH17 without replacing the shared router or implementing it
/// inside deliveries. Null is an explicit missing-integration boundary.
final notificationRouteBuilderProvider = Provider<WidgetBuilder?>(
  (ref) => null,
);

final operationalRouteGuardProvider = Provider<OperationalRouteGuard>((ref) {
  final guard = OperationalRouteGuard(
    access: ref.watch(operationalReadAccessProvider),
    deliveries: ref.watch(deliveryRepositoryProvider),
    cod: ref.watch(codRepositoryProvider),
  );
  ref.onDispose(guard.dispose);
  return guard;
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final guard = ref.watch(operationalRouteGuardProvider);
  final navigatorKey = GlobalKey<NavigatorState>();
  late final GoRouter router;
  void recheckAfterPop() => scheduleMicrotask(() {
    if (ref.mounted) router.refresh();
  });
  router = GoRouter(
    navigatorKey: navigatorKey,
    observers: [_RecheckOnPop(recheckAfterPop)],
    refreshListenable: guard,
    redirect: (context, state) async {
      final operationalRedirect = await guard.redirect(state);
      if (operationalRedirect != null) return operationalRedirect;
      if (!const {'/', '/login', '/register'}.contains(state.uri.path)) {
        return null;
      }
      final session = ref.read(authSessionProvider);
      final profile = ref.read(currentProfileProvider);
      final identity = session.asData?.value;
      final account = profile.asData?.value;
      if (!session.isLoading &&
          !profile.isLoading &&
          identity?.signedIn == true &&
          account != null &&
          account.id == identity!.userId) {
        return homeRouteForRole(account.role);
      }
      return null;
    },
    errorBuilder: (context, state) =>
        const _NavigationStatusPage(message: 'Không tìm thấy trang.'),
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const DungAnRoutePage(key: ValueKey('app-entry')),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const DungAnRoutePage(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => Scaffold(
          body: SafeArea(
            child: RegisterScreen(onLogin: () => context.go('/login')),
          ),
        ),
      ),
      GoRoute(
        path: '/manager/products',
        builder: (context, state) => const DungAnRoutePage(),
      ),
      GoRoute(
        path: '/customer/products',
        builder: (context, state) => const DungAnRoutePage(),
      ),
      GoRoute(
        path: '/manager/orders',
        builder: (context, state) => const DungAnRoutePage(),
      ),
      GoRoute(
        path: '/chat',
        builder: (context, state) => const DungAnRoutePage(inbox: true),
        routes: [
          GoRoute(
            path: ':conversationId',
            builder: (context, state) {
              final id = state.pathParameters['conversationId']!;
              if (!RegExp(
                r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
              ).hasMatch(id)) {
                return const _NavigationStatusPage(
                  message: 'Mã hội thoại không hợp lệ.',
                );
              }
              return DungAnRoutePage(
                inbox: true,
                detailBuilder: (_) =>
                    ConversationDetailScreen(conversationId: id),
              );
            },
          ),
        ],
      ),
      ShellRoute(
        observers: [_RecheckOnPop(recheckAfterPop)],
        builder: (context, state, child) => _OperationalRouteBoundary(
          guard: guard,
          location: state.uri,
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/shipper/tasks',
            caseSensitive: true,
            builder: (context, state) => const DeliveryTasksRoutePage(),
            routes: [
              GoRoute(
                path: ':taskId',
                caseSensitive: true,
                builder: (context, state) => DeliveryTaskRoutePage(
                  taskId: state.pathParameters['taskId']!,
                ),
                routes: [
                  GoRoute(
                    path: 'map',
                    caseSensitive: true,
                    builder: (context, state) => DeliveryTaskMapRoutePage(
                      taskId: state.pathParameters['taskId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/cod',
            caseSensitive: true,
            builder: (context, state) => CodRoutePage(
              orderId: OperationalRouteLocation.parse(state.uri).orderId,
            ),
          ),
          GoRoute(
            path: '/notifications',
            caseSensitive: true,
            builder: (context, state) => Consumer(
              builder: (context, ref, _) =>
                  ref.watch(notificationRouteBuilderProvider)?.call(context) ??
                  const Center(
                    key: ValueKey('mh17-integration-unavailable'),
                    child: Text('Màn thông báo chưa được tích hợp.'),
                  ),
            ),
          ),
        ],
      ),
    ],
  );
  // Role resolution completes independently of the Auth SDK event. Refresh the
  // redirect when the trusted profile becomes available, without recreating the
  // router and losing its navigator stack.
  ref.listen(currentProfileProvider, (_, _) {
    scheduleMicrotask(() {
      if (ref.mounted) router.refresh();
    });
  });
  var observedSession = false;
  String? observedUserId;
  ref.listen(authSessionProvider, (previous, next) {
    if (!next.hasValue || next.isLoading) return;
    final userId = next.requireValue.userId;
    final switched = observedSession && observedUserId != userId;
    observedSession = true;
    observedUserId = userId;
    if (switched) {
      scheduleMicrotask(() {
        if (!ref.mounted) return;
        // Imperative editor sheets belong to the old account too.
        navigatorKey.currentState?.popUntil((route) => route.isFirst);
        router.go('/');
      });
    }
  });
  ref.onDispose(router.dispose);
  return router;
});

// go_router 18.0.2 removes an imperative pop from its match list without
// rerunning top-level redirect. Recheck the revealed page rather than reuse
// the authorization decision of the page that was popped.
class _RecheckOnPop extends NavigatorObserver {
  _RecheckOnPop(this.recheck);
  final VoidCallback recheck;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => recheck();
}

class _OperationalRouteBoundary extends ConsumerWidget {
  const _OperationalRouteBoundary({
    required this.guard,
    required this.location,
    required this.child,
  });
  final OperationalRouteGuard guard;
  final Uri location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(operationalSessionProvider).asData?.value;
    final decision = guard.decisionFor(location);
    if (decision?.invalidId == true) {
      return const _NavigationStatusPage(
        key: ValueKey('navigation-invalid-id'),
        message: 'Mã truy cập không hợp lệ.',
      );
    }
    if (decision?.failure != null) {
      return _NavigationStatusPage(
        key: const ValueKey('navigation-access-error'),
        message: decision!.failure!.message,
        onRetry: () => ref.read(operationalReadAccessProvider).refreshSession(),
      );
    }
    if (session == null ||
        decision == null ||
        !decision.allowed ||
        !identical(session, decision.session)) {
      return const _NavigationStatusPage(
        key: ValueKey('navigation-checking-access'),
        message: 'Đang kiểm tra quyền truy cập…',
      );
    }
    return ShipperShell(
      key: ValueKey(session),
      role: decision.role!,
      location: location,
      child: child,
    );
  }
}

class _NavigationStatusPage extends StatelessWidget {
  const _NavigationStatusPage({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sports Store')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Thử lại')),
          TextButton(
            onPressed: () => context.go('/'),
            child: const Text('Về trang đầu'),
          ),
        ],
      ),
    ),
  );
}
