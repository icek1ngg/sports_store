import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/cod/presentation/pages/cod_route_page.dart';
import '../../features/cart/presentation/pages/cart_page.dart';
import '../../features/checkout/presentation/pages/checkout_page.dart';
import '../../features/catalog/presentation/pages/product_list_page.dart';
import '../../features/catalog/presentation/pages/product_details_page.dart';
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

/// Temporary Auth integration slot. The live catalog tool supplies a login
/// panel here; production remains owned by the central router/Auth feature.
final landingPageBuilderProvider = Provider<WidgetBuilder?>((ref) => null);

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
      final destination = await guard.redirect(state);
      if (ref.mounted &&
          destination == '/' &&
          guard.decisionFor(state.uri)?.failure != null) {
        // A live authorization rejection may mean the cached profile role was
        // revoked. Refresh before the entry page chooses a role destination.
        ref.invalidate(currentProfileProvider);
      }
      return destination;
    },
    errorBuilder: (context, state) =>
        const _NavigationStatusPage(message: 'Không tìm thấy trang.'),
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            ref.read(landingPageBuilderProvider)?.call(context) ??
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
        builder: (context, state, child) => ListenableBuilder(
          listenable: guard.decisionChanges,
          builder: (context, _) => _OperationalRouteBoundary(
            guard: guard,
            location: state.uri,
            child: child,
          ),
        ),
        routes: [
          GoRoute(
            path: '/customer/checkout',
            caseSensitive: true,
            builder: (context, state) => const CheckoutPage(),
          ),
          GoRoute(
            path: '/customer/cart',
            caseSensitive: true,
            builder: (context, state) => const CartPage(),
          ),
          GoRoute(
            path: '/customer/products',
            caseSensitive: true,
            builder: (context, state) => const ProductListPage(),
            routes: [
              GoRoute(
                path: ':productId',
                caseSensitive: true,
                builder: (context, state) => ProductDetailsPage(
                  productId: state.pathParameters['productId']!,
                ),
              ),
            ],
          ),
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
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Closing a dialog does not reveal a different protected URL. Refreshing
    // the guard here tears down the form before the picker result is applied.
    // Session changes still trigger the guard's independent auth listener.
    if (route is! PopupRoute<dynamic>) recheck();
  }
}

class _OperationalRouteBoundary extends ConsumerStatefulWidget {
  const _OperationalRouteBoundary({
    required this.guard,
    required this.location,
    required this.child,
  });
  final OperationalRouteGuard guard;
  final Uri location;
  final Widget child;

  @override
  ConsumerState<_OperationalRouteBoundary> createState() =>
      _OperationalRouteBoundaryState();
}

class _OperationalRouteBoundaryState
    extends ConsumerState<_OperationalRouteBoundary> {
  String? _authorizedCustomerId;
  Object? _authorizedOperationalSession;
  String? _operationalRole;

  @override
  Widget build(BuildContext context) {
    final sessionState = ref.watch(operationalSessionProvider);
    final session = sessionState.isLoading || sessionState.hasError
        ? null
        : sessionState.asData?.value;
    final decision = widget.guard.decisionFor(widget.location);
    final customerOnly = OperationalRouteLocation.parse(widget.location)
        .customerOnly;
    final allowed =
        session != null &&
        decision?.allowed == true &&
        identical(session, decision!.session);

    if (!customerOnly ||
        session?.userId != _authorizedCustomerId ||
        session?.failure != null ||
        decision?.invalidId == true) {
      _authorizedCustomerId = null;
    }
    if (customerOnly && allowed) _authorizedCustomerId = session.userId;

    final status = _status(decision);
    if (customerOnly) {
      // Keep an already authorized customer's Navigator mounted while the
      // same account is rechecked. Offstage hides PII and ExcludeFocus blocks
      // keyboard input; changing account removes the subtree entirely.
      return Stack(
        fit: StackFit.expand,
        children: [
          if (_authorizedCustomerId != null)
            Offstage(
              offstage: !allowed,
              child: TickerMode(
                enabled: allowed,
                child: ExcludeFocus(
                  excluding: !allowed,
                  child: KeyedSubtree(
                    key: ValueKey(_authorizedCustomerId),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          if (!allowed) status,
        ],
      );
    }
    if (!identical(session, _authorizedOperationalSession) ||
        session?.failure != null ||
        decision?.failure != null ||
        decision?.invalidId == true) {
      _authorizedOperationalSession = null;
      _operationalRole = null;
    }
    if (allowed) {
      _authorizedOperationalSession = session;
      _operationalRole = decision.role;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_authorizedOperationalSession != null)
          Offstage(
            offstage: !allowed,
            child: TickerMode(
              enabled: allowed,
              child: ExcludeFocus(
                excluding: !allowed,
                child: ShipperShell(
                  key: ValueKey(_authorizedOperationalSession),
                  role: _operationalRole!,
                  location: widget.location,
                  child: widget.child,
                ),
              ),
            ),
          ),
        if (!allowed) status,
      ],
    );
  }

  Widget _status(OperationalRouteDecision? decision) {
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
    return const _NavigationStatusPage(
      key: ValueKey('navigation-checking-access'),
      message: 'Đang tải màn hình…',
      loading: true,
    );
  }
}

class _NavigationStatusPage extends StatelessWidget {
  const _NavigationStatusPage({
    super.key,
    required this.message,
    this.onRetry,
    this.loading = false,
  });
  final String message;
  final VoidCallback? onRetry;
  final bool loading;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sports Store')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading) ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
          ],
          Semantics(liveRegion: true, child: Text(message)),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Thử lại')),
          if (!loading)
            TextButton(
              onPressed: () => context.go('/'),
              child: const Text('Về trang đầu'),
            ),
        ],
      ),
    ),
  );
}
