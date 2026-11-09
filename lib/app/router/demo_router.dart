import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/orders/presentation/pages/customer_orders_page.dart';
import '../../features/orders/presentation/pages/manager_order_details_page.dart';
import '../../features/orders/presentation/pages/manager_orders_page.dart';
import '../demo/data/local_demo_store.dart';

/// Alternate application composition; uses the same role routes and approved
/// pages without importing the production Auth/operational router.
GoRouter createDemoRouter({
  required LocalDemoStore store,
  required GlobalKey<NavigatorState> navigatorKey,
  required Widget Function(BuildContext, GoRouterState, Widget) shellBuilder,
}) => GoRouter(
  navigatorKey: navigatorKey,
  initialLocation: store.session.role == 'manager'
      ? '/manager/orders'
      : '/customer/orders',
  redirect: (_, state) {
    final manager = store.session.role == 'manager';
    if ((manager && state.uri.path.startsWith('/customer/')) ||
        (!manager && state.uri.path.startsWith('/manager/'))) {
      return manager ? '/manager/orders' : '/customer/orders';
    }
    return null;
  },
  routes: [
    ShellRoute(
      builder: shellBuilder,
      routes: [
        GoRoute(
          path: '/customer/orders',
          builder: (_, _) => const CustomerOrdersPage(enablePolling: false),
        ),
        GoRoute(
          path: '/manager/orders',
          builder: (context, _) => ManagerOrdersPage(
            enablePolling: false,
            onOpenOrder: (id) => context.push('/manager/orders/$id'),
          ),
        ),
        GoRoute(
          path: '/manager/orders/:orderId',
          builder: (_, state) => ManagerOrderDetailsPage(
            orderId: state.pathParameters['orderId']!,
            enablePolling: false,
          ),
        ),
        GoRoute(
          path: '/notifications',
          builder: (_, _) => const NotificationsScreen(enablePolling: false),
        ),
      ],
    ),
  ],
);
