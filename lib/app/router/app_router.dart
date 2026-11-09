import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/foundation_providers.dart';
import '../../features/cod/presentation/pages/cod_route_page.dart';
import '../../features/cart/presentation/pages/cart_page.dart';
import '../../features/checkout/presentation/pages/checkout_page.dart';
import '../../features/catalog/presentation/pages/product_list_page.dart';
import '../../features/catalog/presentation/pages/product_details_page.dart';
import '../../features/auth/presentation/pages/register_screen.dart';
import '../../features/auth/presentation/pages/email_confirmation_page.dart';
import '../../features/auth/data/email_confirmation_callback.dart';
import '../../features/auth/domain/models/email_confirmation_result.dart';
import '../../features/auth/presentation/view_models/auth_providers.dart';
import '../../features/chat/presentation/pages/conversation_detail_screen.dart';
import '../../features/cod/presentation/view_models/cod_providers.dart';
import '../../features/deliveries/data/repositories/operational_providers.dart';
import '../../features/deliveries/presentation/pages/delivery_route_pages.dart';
import '../../features/deliveries/presentation/view_models/delivery_providers.dart';
import '../../features/deliveries/presentation/view_models/delivery_task_list_view_model.dart';
import '../../features/deliveries/presentation/view_models/delivery_task_detail_view_model.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/notifications/domain/models/notification_target.dart';
import '../../features/orders/presentation/pages/customer_orders_page.dart';
import '../../features/orders/presentation/view_models/order_providers.dart';
import '../../features/orders/presentation/pages/manager_order_details_page.dart';
import '../../features/orders/presentation/pages/manager_orders_page.dart';
import '../../features/returns/presentation/pages/manager_return_detail_page.dart';
import '../../features/returns/presentation/pages/manager_returns_page.dart';
import '../../features/returns/presentation/pages/return_request_flow_page.dart';
import '../../features/returns/presentation/pages/return_tracking_page.dart';
import '../shells/sports_store_shell.dart';
import 'operational_route_guard.dart';
import 'authenticated_route_page.dart';
import 'four_screen_route_boundary.dart';

/// Production MH17 uses the shared router; tests can override this builder.
final notificationRouteBuilderProvider = Provider<WidgetBuilder?>(
  (ref) =>
      (context) => NotificationsPage(
        key: const ValueKey('mh17-production-screen'),
        onNavigate: (decision) async {
          final id = decision.entityId;
          if (!decision.available ||
              id == null ||
              !isStrictUuid(id) ||
              !context.mounted) {
            return false;
          }
          final scope = ref.read(featureSessionScopeProvider);
          if (!scope.canReadPrivateData) return false;
          final path = switch (decision.screen) {
            NotificationTargetScreen.managerOrder
                when scope.role == 'manager' =>
              '/manager/orders/$id',
            NotificationTargetScreen.customerOrder
                when scope.role == 'customer' =>
              '/customer/orders/$id',
            _ => null,
          };
          if (path == null) return false;
          unawaited(GoRouter.of(context).push(path));
          return true;
        },
      ),
);

/// Test seam for public entry-route coverage. The application uses the
/// canonical Auth boundary when no test builder is supplied.
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

final appStartupFailureProvider = Provider<bool>((ref) => false);

final Provider<GoRouter> appRouterProvider = Provider<GoRouter>((ref) {
  if (ref.watch(appStartupFailureProvider)) {
    final failedRouter = GoRouter(
      initialLocation: '/startup-error',
      routes: [
        GoRoute(
          path: '/startup-error',
          builder: (_, _) => const Scaffold(
            body: Center(
              child: Text('Không thể khởi động ứng dụng. Vui lòng thử lại.'),
            ),
          ),
        ),
      ],
    );
    ref.onDispose(failedRouter.dispose);
    return failedRouter;
  }
  final guard = ref.watch(operationalRouteGuardProvider);
  final confirmation = ref.read(initialEmailConfirmationProvider);
  final navigatorKey = GlobalKey<NavigatorState>();
  final branchNavigatorKeys = List.generate(
    _branchPaths.length,
    (_) => GlobalKey<NavigatorState>(),
  );
  late final GoRouter router;
  Uri activeLocation() {
    try {
      return router.routerDelegate.state.uri;
    } on StateError {
      return router.routerDelegate.currentConfiguration.uri;
    }
  }

  var activeRedirects = 0;
  var retired = false;
  Completer<void>? redirectsDrained;
  var popCheckScheduled = false;
  var suppressPopRecheck = false;
  var profileRefreshPending = false;
  Uri? pendingPopLocation;
  void recheckAfterPop() {
    // A redirect can remove one or more pages itself. Those pops already have
    // an authorization decision and must not start another check against the
    // stale URI that go_router exposes while applying the redirect.
    if (suppressPopRecheck) return;
    if (popCheckScheduled) return;
    popCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      popCheckScheduled = false;
      if (!ref.mounted || retired || suppressPopRecheck) return;
      // A notification target is an imperative push across shell branches.
      // Replaying its old leaf during pop can restore the detail just closed.
      // Refresh the inbox base instead; its repository/session guard rechecks
      // recipient access before rendering any inbox content.
      final base = router.routerDelegate.currentConfiguration.uri;
      if (base.path == '/notifications') {
        pendingPopLocation = null;
        router.go(base.toString());
        return;
      }
      // Refresh redirects the base URI of an imperative stack in go_router 18.
      // go_router refreshes the base URI of an imperative stack. Preserve the
      // actual revealed leaf for the router-owned redirect below so the stack
      // remains mounted while that leaf is reauthorized.
      pendingPopLocation = activeLocation();
      // AppBar/Navigator.maybePop updates the delegate before the route
      // information provider reports the revealed stack. Refreshing that
      // provider here can restore the page that was just popped. Restore the
      // delegate's current stack explicitly, as GoRouter.pop itself does.
      router.restore(router.routerDelegate.currentConfiguration);
      final parts = activeLocation().pathSegments;
      if (parts.length == 3 &&
          parts[0] == 'shipper' &&
          parts[1] == 'tasks' &&
          isStrictUuid(parts[2])) {
        unawaited(
          ref
              .read(deliveryTaskDetailViewModelProvider(parts[2]).notifier)
              .refresh()
              .catchError((Object _) {}),
        );
      }
    });
  }

  final applicationRoutes = <RouteBase>[
    GoRoute(
      path: EmailConfirmationCallback.path,
      builder: (context, state) => EmailConfirmationPage(
        result: confirmation ?? EmailConfirmationResult.invalid,
      ),
    ),
    GoRoute(
      path: '/',
      builder: (context, state) =>
          ref.read(landingPageBuilderProvider)?.call(context) ??
          const AuthenticatedRoutePage(key: ValueKey('app-entry')),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const AuthenticatedRoutePage(),
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
      path: '/customer/home',
      builder: (c, s) => const FourScreenRouteBoundary(
        roles: {'customer'},
        child: SportsStoreHomePage(),
      ),
    ),
    for (final role in ['customer', 'manager', 'shipper'])
      GoRoute(
        path: '/$role/account',
        builder: (c, s) => FourScreenRouteBoundary(
          roles: {role},
          child: const SportsStoreAccountPage(),
        ),
      ),
    GoRoute(
      path: '/manager/products',
      builder: (context, state) => const AuthenticatedRoutePage(),
    ),
    GoRoute(
      path: '/manager/orders',
      caseSensitive: true,
      builder: (context, state) => FourScreenRouteBoundary(
        roles: const {'manager'},
        child: ManagerOrdersPage(
          onOpenOrder: (orderId) {
            if (!isStrictUuid(orderId)) return;
            context.push('/manager/orders/${Uri.encodeComponent(orderId)}');
          },
        ),
      ),
    ),
    GoRoute(
      path: '/manager/orders/:orderId',
      caseSensitive: true,
      builder: (context, state) {
        final orderId = state.pathParameters['orderId'];
        final valid = orderId != null && isStrictUuid(orderId);
        return FourScreenRouteBoundary(
          roles: const {'manager'},
          invalidId: !valid,
          child: valid
              ? ManagerOrderDetailsPage(
                  orderId: orderId,
                  onOpenCod: (id) {
                    if (!isStrictUuid(id)) return;
                    context.push(
                      Uri(
                        path: '/cod',
                        queryParameters: {'orderId': id},
                      ).toString(),
                    );
                  },
                  onOpenReturn: (id) {
                    if (isStrictUuid(id)) {
                      context.push('/manager/returns/$id');
                    }
                  },
                )
              : const SizedBox.shrink(),
        );
      },
    ),
    GoRoute(
      path: '/customer/orders',
      caseSensitive: true,
      builder: (context, state) => FourScreenRouteBoundary(
        roles: const {'customer'},
        child: CustomerOrdersPage(
          onOpenCatalog: () => context.go('/customer/products'),
          onOpenOrder: (id) async {
            await context.push('/customer/orders/$id');
            if (context.mounted) {
              ref.invalidate(orderListFoundationProvider);
            }
          },
          onCreateReturn: (id) {
            if (isStrictUuid(id)) {
              context.push('/customer/orders/$id/return');
            }
          },
          onOpenReturn: (id) {
            if (isStrictUuid(id)) {
              context.push('/customer/returns/$id');
            }
          },
        ),
      ),
    ),
    GoRoute(
      path: '/customer/orders/:orderId',
      builder: (c, s) => FourScreenRouteBoundary(
        roles: const {'customer'},
        invalidId: !isStrictUuid(s.pathParameters['orderId']!),
        child: CustomerOrderDetailsPage(
          orderId: s.pathParameters['orderId']!,
          onCreateReturn: (id) => c.push('/customer/orders/$id/return'),
          onOpenReturn: (id) => c.push('/customer/returns/$id'),
        ),
      ),
    ),
    GoRoute(
      path: '/chat',
      builder: (context, state) => const AuthenticatedRoutePage(inbox: true),
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
            return AuthenticatedRoutePage(
              inbox: true,
              detailBuilder: (_) =>
                  ConversationDetailScreen(conversationId: id),
            );
          },
        ),
      ],
    ),
    // MH17 is shared and can be opened from a root-level account/chat page
    // above an existing customer shell. Keep its page on the root stack so
    // that push does not add the same ShellRoute page key a second time.
    // The operational redirect and boundary still verify current access.
    GoRoute(
      path: '/notifications',
      caseSensitive: true,
      builder: (context, state) => ListenableBuilder(
        listenable: guard.decisionChanges,
        builder: (context, _) => _OperationalRouteBoundary(
          guard: guard,
          location: state.uri,
          child: Consumer(
            builder: (context, ref, _) =>
                ref.watch(notificationRouteBuilderProvider)?.call(context) ??
                const Center(
                  key: ValueKey('mh17-integration-unavailable'),
                  child: Text('Màn thông báo chưa được tích hợp.'),
                ),
          ),
        ),
      ),
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
          path: '/customer/orders/:orderId/return',
          caseSensitive: true,
          builder: (context, state) => ReturnRequestFlowPage(
            orderId: state.pathParameters['orderId']!,
            onExit: () => context.canPop()
                ? context.pop()
                : context.go('/customer/products'),
            // Replace the form so "back" from tracking does not reopen it.
            onOpenReturn: (returnId) =>
                context.go('/customer/returns/$returnId'),
          ),
        ),
        GoRoute(
          path: '/customer/returns/:returnId',
          caseSensitive: true,
          builder: (context, state) => ReturnTrackingPage(
            returnId: state.pathParameters['returnId']!,
            onBack: () => context.canPop()
                ? context.pop()
                : context.go('/customer/products'),
          ),
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
          path: '/manager/returns',
          caseSensitive: true,
          builder: (context, state) => ManagerReturnsPage(
            onOpen: (id) => context.push<void>('/manager/returns/$id'),
          ),
          routes: [
            GoRoute(
              path: ':returnId',
              caseSensitive: true,
              builder: (context, state) => ManagerReturnDetailPage(
                returnId: state.pathParameters['returnId']!,
                onBack: () => context.canPop()
                    ? context.pop()
                    : context.go('/manager/returns'),
              ),
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
      ],
    ),
  ];

  List<RouteBase> canonicalRoutes(List<RouteBase> entries) {
    GoRoute authorized(GoRoute route) => GoRoute(
      path: route.path,
      name: route.name,
      caseSensitive: route.caseSensitive,
      redirect: route.redirect,
      builder: (c, state) => ListenableBuilder(
        listenable: guard.decisionChanges,
        builder: (_, _) => _OperationalRouteBoundary(
          guard: guard,
          location: state.uri,
          child: route.builder!(c, state),
        ),
      ),
      routes: route.routes.map((r) => authorized(r as GoRoute)).toList(),
    );
    final routes = <GoRoute>[];
    for (final entry in entries) {
      if (entry is GoRoute) {
        routes.add(entry);
      } else if (entry is ShellRoute) {
        routes.addAll(entry.routes.cast<GoRoute>().map(authorized));
      }
    }
    final public = routes
        .where(
          (r) => const {
            '/',
            '/login',
            '/register',
            '/auth/confirm-email',
          }.contains(r.path),
        )
        .toList();
    final groups = List.generate(_branchPaths.length, (_) => <RouteBase>[]);
    for (final route in routes.where((r) => !public.contains(r))) {
      groups[_branchForPath(route.path)].add(route);
    }
    return [
      ...public,
      StatefulShellRoute.indexedStack(
        branches: [
          for (var i = 0; i < groups.length; i++)
            StatefulShellBranch(
              initialLocation: _branchPaths[i],
              navigatorKey: branchNavigatorKeys[i],
              observers: [_RecheckOnPop(recheckAfterPop)],
              routes: groups[i],
            ),
        ],
        builder: (c, state, shell) => _CanonicalAppShell(
          location: activeLocation(),
          guard: guard,
          child: shell,
          onDestinationSelected: (index) {
            final role = ref.read(featureSessionScopeProvider).role;
            final paths = _destinationsForRole(role);
            if (index < paths.length) {
              shell.goBranch(_branchForPath(paths[index]));
            }
          },
        ),
      ),
    ];
  }

  router = GoRouter(
    initialLocation: confirmation != null
        ? EmailConfirmationCallback.path
        : null,
    // Supabase's #access_token / #error fragment is not a Flutter hash route.
    overridePlatformDefaultLocation: confirmation != null,
    navigatorKey: navigatorKey,
    observers: [_RecheckOnPop(recheckAfterPop)],
    refreshListenable: guard,
    redirect: (context, state) async {
      activeRedirects++;
      try {
        if (retired) return null;
        if (state.uri.path == EmailConfirmationCallback.path) return null;
        final checkedLocation = pendingPopLocation ?? state.uri;
        pendingPopLocation = null;
        final destination = await guard.redirectLocation(checkedLocation);
        if (destination != null) {
          suppressPopRecheck = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              suppressPopRecheck = false;
              if (profileRefreshPending && ref.mounted) {
                profileRefreshPending = false;
                if (const {
                  '/',
                  '/login',
                  '/register',
                }.contains(activeLocation().path)) {
                  router.refresh();
                }
              }
            });
          });
          if (ref.mounted &&
              destination == '/' &&
              guard.decisionFor(checkedLocation)?.failure != null) {
            // A live authorization rejection may mean the cached profile role was
            // revoked. Refresh before the entry page chooses a role destination.
            profileRefreshPending = true;
            invalidateLegacyDeliveryTaskReads(ref);
            unawaited(
              ref.read(deliveryTaskListViewModelProvider.notifier).refresh(),
            );
            ref.invalidate(currentProfileProvider);
          }
          return destination;
        }
        if (!const {'/', '/login', '/register'}.contains(state.uri.path)) {
          return null;
        }
        if (state.uri.path == '/' &&
            ref.read(landingPageBuilderProvider) != null) {
          return null;
        }
        final session = ref.read(authSessionProvider);
        final profile = ref.read(currentProfileProvider);
        final identity = session.asData?.value;
        final account = profile.asData?.value;
        if (!session.isLoading &&
            session.hasValue &&
            identity?.signedIn != true &&
            state.uri.path == '/') {
          return '/login';
        }
        if (!session.isLoading &&
            !profile.isLoading &&
            identity?.signedIn == true &&
            account != null &&
            account.id == identity!.userId) {
          return homeRouteForRole(account.role);
        }
        return null;
      } finally {
        activeRedirects--;
        if (retired &&
            activeRedirects == 0 &&
            redirectsDrained != null &&
            !redirectsDrained!.isCompleted) {
          redirectsDrained!.complete();
        }
      }
    },
    errorBuilder: (context, state) =>
        const _NavigationStatusPage(message: 'Không tìm thấy trang.'),
    routes: [...canonicalRoutes(applicationRoutes)],
  );
  // Role resolution completes independently of the Auth SDK event. Refresh the
  // redirect when the trusted profile becomes available, without recreating the
  // router and losing its navigator stack.
  ref.listen(currentProfileProvider, (_, _) {
    scheduleMicrotask(() {
      // Entry routes need role resolution to pick a home screen. Refreshing a
      // denied protected URL here restarts its guard while its redirect to '/'
      // is still pending, repeatedly invalidating the same profile.
      if (!ref.mounted || retired) return;
      if (suppressPopRecheck) {
        profileRefreshPending = true;
        return;
      }
      if (const {'/', '/login', '/register'}.contains(activeLocation().path)) {
        router.refresh();
      }
    });
  });
  var observedSession = ref.read(authSessionProvider).hasValue;
  String? observedUserId = ref.read(authSessionProvider).asData?.value.userId;
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
        for (final key in branchNavigatorKeys) {
          key.currentState?.popUntil((route) => route.isFirst);
        }
        navigatorKey.currentState?.popUntil((route) => route.isFirst);
        if (activeLocation().path == EmailConfirmationCallback.path) return;
        // A different identity receives new branch Navigators, not hidden old tabs.
        ref.invalidateSelf();
      });
    }
  });
  String? observedRole = ref.read(featureSessionScopeProvider).role;
  ref.listen(featureSessionScopeProvider, (previous, next) {
    if (next.canReadPrivateData) {
      final changedRole = observedRole != null && observedRole != next.role;
      observedRole = next.role;
      if (changedRole) {
        scheduleMicrotask(() {
          if (ref.mounted) {
            ref.invalidateSelf();
          }
        });
        return;
      }
    }
    if (previous == null || previous == next) return;
    scheduleMicrotask(() {
      if (!ref.mounted) return;
      // Root dialogs contain account-scoped state outside the feature subtree.
      for (final key in branchNavigatorKeys) {
        key.currentState?.popUntil((route) => route is PageRoute<dynamic>);
      }
      navigatorKey.currentState?.popUntil(
        (route) => route is PageRoute<dynamic>,
      );
      if (suppressPopRecheck) {
        profileRefreshPending = true;
        return;
      }
      router.refresh();
    });
  });
  ref.onDispose(() {
    retired = true;
    void disposeAfterFrame() {
      WidgetsBinding.instance.addPostFrameCallback((_) => router.dispose());
      WidgetsBinding.instance.ensureVisualUpdate();
    }

    if (activeRedirects == 0) {
      disposeAfterFrame();
    } else {
      redirectsDrained = Completer<void>();
      unawaited(redirectsDrained!.future.then((_) => disposeAfterFrame()));
    }
  });
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
                    child: Scaffold(body: widget.child),
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
    }
    if (allowed) {
      _authorizedOperationalSession = session;
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
                child: KeyedSubtree(
                  key: ValueKey(_authorizedOperationalSession),
                  child: Scaffold(body: widget.child),
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

class _CanonicalAppShell extends ConsumerWidget {
  const _CanonicalAppShell({
    required this.location,
    required this.child,
    required this.guard,
    this.onDestinationSelected,
  });
  final Uri location;
  final Widget child;
  final OperationalRouteGuard guard;
  final ValueChanged<int>? onDestinationSelected;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(featureSessionScopeProvider);
    final entry = const {
      '/',
      '/login',
      '/register',
      '/auth/confirm-email',
    }.contains(location.path);
    // Keep the Navigator at the same element path while profile revalidation
    // temporarily makes the trusted scope unresolved. Route gates hide PII.
    final sessionState = ref.watch(operationalSessionProvider);
    final session = sessionState.asData?.value;
    return ListenableBuilder(
      listenable: guard.decisionChanges,
      builder: (context, _) {
        final decision = guard.decisionFor(location);
        final checking =
            OperationalRouteLocation.parse(location).protected &&
            (sessionState.isLoading ||
                decision == null ||
                !identical(session, decision.session));
        return SportsStoreShell(
          role: scope.role ?? '',
          location: location,
          showNavigation: !entry && scope.canReadPrivateData,
          onDestinationSelected: onDestinationSelected,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Offstage(offstage: checking, child: child),
              if (checking)
                const _NavigationStatusPage(
                  key: ValueKey('navigation-checking-access'),
                  message: 'Đang tải màn hình…',
                  loading: true,
                ),
            ],
          ),
        );
      },
    );
  }
}

const _branchPaths = <String>[
  '/customer/home',
  '/customer/products',
  '/customer/cart',
  '/customer/orders',
  '/customer/account',
  '/manager/orders',
  '/manager/products',
  '/manager/returns',
  '/manager/account',
  '/shipper/tasks',
  '/cod',
  '/shipper/account',
  '/notifications',
  '/chat',
];
List<String> _destinationsForRole(String? role) => switch (role) {
  'customer' => _branchPaths.sublist(0, 5),
  'manager' => _branchPaths.sublist(5, 9),
  'shipper' => [_branchPaths[9], _branchPaths[10], _branchPaths[11]],
  _ => const [],
};
int _branchForPath(String path) {
  if (path == '/customer/checkout') return 2;
  if (path.startsWith('/customer/returns/')) return 3;
  final index = _branchPaths.indexWhere(
    (p) => path == p || path.startsWith('$p/'),
  );
  if (index < 0) {
    throw StateError('No navigation branch for ');
  }
  return index;
}
