import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/pages/login_screen.dart';
import '../../features/auth/presentation/pages/register_screen.dart';
import '../../features/catalog/presentation/pages/product_list_page.dart';
import '../../features/catalog/presentation/pages/product_details_page.dart';
import '../../features/catalog/presentation/pages/product_management_screen.dart';
import '../../features/cart/presentation/pages/cart_page.dart';
import '../../features/checkout/presentation/pages/checkout_page.dart';
import '../../features/chat/presentation/pages/conversation_list_screen.dart';
import '../../features/chat/presentation/pages/conversation_detail_screen.dart';
import '../../features/cod/presentation/pages/cod_route_page.dart';
import '../../features/deliveries/presentation/pages/delivery_task_list_page.dart';
import '../../features/deliveries/presentation/pages/delivery_task_detail_page.dart';
import '../../features/deliveries/presentation/pages/delivery_task_map_page.dart';
import '../../features/notifications/domain/models/notification_target.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/notifications/presentation/providers/notification_providers.dart';
import '../../features/orders/presentation/pages/customer_orders_page.dart';
import '../../features/orders/presentation/pages/manager_orders_page.dart';
import '../../features/orders/presentation/pages/manager_order_details_page.dart';
import '../../features/orders/presentation/view_models/order_providers.dart';
import '../../features/returns/presentation/pages/return_request_flow_page.dart';
import '../../features/returns/presentation/pages/return_tracking_page.dart';
import '../../features/returns/presentation/pages/manager_returns_page.dart';
import '../../features/returns/presentation/pages/manager_return_detail_page.dart';
import '../demo/data/local_demo_store.dart';
import 'data/local_auth_repository.dart';

String devHome(String role) => switch (role) {
  'manager' => '/manager/orders',
  'shipper' => '/shipper/tasks',
  _ => '/customer/home',
};

typedef _Destination = ({
  String path,
  String label,
  IconData icon,
  Widget Function(BuildContext) page,
  List<RouteBase> children,
});

GoRouter createDevRouter({
  required LocalAuthRepository auth,
  required LocalDemoStore store,
  required VoidCallback reset,
}) {
  final role = auth.currentSession.signedIn ? store.session.role! : 'customer';
  final root = '/$role';
  final accountPath = '$root/account';
  void back(BuildContext c, String fallback) =>
      c.canPop() ? c.pop() : c.go(fallback);
  final destinations = <_Destination>[
    if (role == 'customer') ...[
      (
        path: '/customer/home',
        label: 'Trang chủ',
        icon: Icons.home_outlined,
        page: (c) => const _HomePage(),
        children: [],
      ),
      (
        path: '/customer/products',
        label: 'Sản phẩm',
        icon: Icons.storefront_outlined,
        page: (c) => const ProductListPage(),
        children: [
          GoRoute(
            path: ':productId',
            builder: (c, s) =>
                ProductDetailsPage(productId: s.pathParameters['productId']!),
          ),
        ],
      ),
      (
        path: '/customer/cart',
        label: 'Giỏ hàng',
        icon: Icons.shopping_bag_outlined,
        page: (c) => const CartPage(),
        children: [
          GoRoute(path: 'checkout', builder: (c, s) => const CheckoutPage()),
        ],
      ),
      (
        path: '/customer/orders',
        label: 'Đơn hàng',
        icon: Icons.receipt_long_outlined,
        page: (c) => CustomerOrdersPage(
          enablePolling: false,
          onOpenCatalog: () => c.go('/customer/products'),
          onOpenOrder: (id) async {
            await c.push('/customer/orders/$id');
            if (c.mounted) {
              ProviderScope.containerOf(
                c,
                listen: false,
              ).invalidate(orderListFoundationProvider);
            }
          },
          onCreateReturn: (id) => c.push('/customer/orders/$id/return'),
          onOpenReturn: (id) => c.push('/customer/returns/$id'),
        ),
        children: [
          GoRoute(
            path: ':orderId',
            builder: (c, s) => CustomerOrderDetailsPage(
              orderId: s.pathParameters['orderId']!,
              onCreateReturn: (id) => c.push('/customer/orders/$id/return'),
              onOpenReturn: (id) => c.push('/customer/returns/$id'),
            ),
            routes: [
              GoRoute(
                path: 'return',
                builder: (c, s) => ReturnRequestFlowPage(
                  orderId: s.pathParameters['orderId']!,
                  onExit: () => back(c, '/customer/orders'),
                  onOpenReturn: (id) => c.go('/customer/returns/$id'),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
    if (role == 'manager') ...[
      (
        path: '/manager/orders',
        label: 'Đơn hàng',
        icon: Icons.receipt_long_outlined,
        page: (c) => ManagerOrdersPage(
          enablePolling: false,
          onOpenOrder: (id) => c.push('/manager/orders/$id'),
        ),
        children: [
          GoRoute(
            path: ':orderId',
            builder: (c, s) => ManagerOrderDetailsPage(
              orderId: s.pathParameters['orderId']!,
              enablePolling: false,
              onOpenCod: (id) => c.push('/cod?orderId=$id'),
              onOpenReturn: (id) => c.push('/manager/returns/$id'),
            ),
          ),
        ],
      ),
      (
        path: '/manager/products',
        label: 'Sản phẩm',
        icon: Icons.inventory_2_outlined,
        page: (c) => const ProductManagementScreen(),
        children: [],
      ),
      (
        path: '/manager/returns',
        label: 'Trả hàng',
        icon: Icons.assignment_return_outlined,
        page: (c) =>
            ManagerReturnsPage(onOpen: (id) => c.push('/manager/returns/$id')),
        children: [
          GoRoute(
            path: ':returnId',
            builder: (c, s) => ManagerReturnDetailPage(
              returnId: s.pathParameters['returnId']!,
              onBack: () => back(c, '/manager/returns'),
            ),
          ),
        ],
      ),
    ],
    if (role == 'shipper') ...[
      (
        path: '/shipper/tasks',
        label: 'Giao hàng',
        icon: Icons.local_shipping_outlined,
        page: (c) => const DeliveryTaskListPage(),
        children: [
          GoRoute(
            path: ':taskId',
            builder: (c, s) => _TitledPage(
              title: 'Chi tiết giao hàng',
              child: DeliveryTaskDetailPage(
                taskId: s.pathParameters['taskId']!,
              ),
            ),
            routes: [
              GoRoute(
                path: 'map',
                builder: (c, s) =>
                    DeliveryTaskMapPage(taskId: s.pathParameters['taskId']!),
              ),
            ],
          ),
        ],
      ),
      (
        path: '/shipper/cod',
        label: 'Thu hộ COD',
        icon: Icons.payments_outlined,
        page: (c) => _TitledPage(
          title: 'Tiền thu hộ',
          child: CodRoutePage(
            orderId: GoRouterState.of(c).uri.queryParameters['orderId'],
          ),
        ),
        children: [],
      ),
    ],
    (
      path: accountPath,
      label: 'Tài khoản',
      icon: Icons.person_outline,
      page: (c) => _AccountPage(auth: auth, store: store, reset: reset),
      children: [
        GoRoute(
          path: 'notifications',
          builder: (c, s) => NotificationsScreen(
            enablePolling: false,
            onNavigate: (target) async {
              final id = target.entityId;
              final path = switch (target.screen) {
                NotificationTargetScreen.customerOrder =>
                  '/customer/orders/$id',
                NotificationTargetScreen.managerOrder => '/manager/orders/$id',
                NotificationTargetScreen.shipperTask => '/shipper/tasks/$id',
                NotificationTargetScreen.cod => '/cod?orderId=$id',
                NotificationTargetScreen.customerReturn =>
                  '/customer/returns/$id',
                NotificationTargetScreen.managerReturn =>
                  '/manager/returns/$id',
                NotificationTargetScreen.conversation => '/chat/$id',
                _ => null,
              };
              if (path == null) return false;
              await c.push(path);
              return true;
            },
          ),
        ),
        if (role != 'shipper')
          GoRoute(
            path: 'chat',
            builder: (c, s) => _TitledPage(
              title: 'Hỗ trợ & hội thoại',
              child: ConversationListScreen(
                isCustomer: role == 'customer',
                onOpenConversation: (id) => c.push('/chat/$id'),
              ),
            ),
            routes: [
              GoRoute(
                path: ':conversationId',
                builder: (c, s) => ConversationDetailScreen(
                  conversationId: s.pathParameters['conversationId']!,
                ),
              ),
            ],
          ),
        if (role == 'manager')
          GoRoute(
            path: 'cod',
            builder: (c, s) => _TitledPage(
              title: 'Đối soát COD',
              child: CodRoutePage(orderId: s.uri.queryParameters['orderId']),
            ),
          ),
        if (role == 'customer')
          GoRoute(
            path: 'returns/:returnId',
            builder: (c, s) => ReturnTrackingPage(
              returnId: s.pathParameters['returnId']!,
              onBack: () => back(c, accountPath),
            ),
          ),
      ],
    ),
  ];
  return GoRouter(
    initialLocation: auth.currentSession.signedIn ? devHome(role) : '/login',
    redirect: (c, s) {
      final signedIn = auth.currentSession.signedIn;
      final path = s.uri.path;
      if (!signedIn) {
        return {'/login', '/register'}.contains(path) ? null : '/login';
      }
      if ({'/', '/login', '/register'}.contains(path)) return devHome(role);
      if (RegExp(r'^/(customer|manager|shipper)/').hasMatch(path) &&
          !path.startsWith('$root/')) {
        return devHome(role);
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (c, s) => devHome(role)),
      GoRoute(
        path: '/login',
        builder: (c, s) => Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: LoginScreen(
                    onRegister: () => c.push('/register'),
                    onAuthenticated: () => c.go(devHome(store.session.role!)),
                  ),
                ),
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: c,
                    builder: (d) => const AlertDialog(
                      title: Text('Tài khoản trên thiết bị'),
                      content: Text(
                        'customer@local.test\nmanager@local.test\nshipper@local.test\ncustomer.c@local.test\n\nMật khẩu local: sports123\n\nChỉ dùng dữ liệu RAM trên máy này, không đăng nhập Supabase.',
                      ),
                    ),
                  ),
                  child: const Text('Thông tin đăng nhập trên thiết bị'),
                ),
              ],
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/register',
        builder: (c, s) => Scaffold(
          body: SafeArea(child: RegisterScreen(onLogin: () => c.go('/login'))),
        ),
      ),
      GoRoute(
        path: '/notifications',
        redirect: (c, s) => '$accountPath/notifications',
      ),
      GoRoute(
        path: '/chat',
        redirect: (c, s) =>
            role == 'shipper' ? accountPath : '$accountPath/chat',
      ),
      GoRoute(
        path: '/chat/:conversationId',
        redirect: (c, s) => role == 'shipper'
            ? accountPath
            : '$accountPath/chat/${s.pathParameters['conversationId']}',
      ),
      GoRoute(
        path: '/cod',
        redirect: (c, s) => role == 'customer'
            ? accountPath
            : Uri(
                path: role == 'shipper' ? '/shipper/cod' : '$accountPath/cod',
                queryParameters: s.uri.queryParameters,
              ).toString(),
      ),
      if (role == 'customer') ...[
        GoRoute(
          path: '/customer/checkout',
          redirect: (c, s) => '/customer/cart/checkout',
        ),
        GoRoute(
          path: '/customer/returns/:returnId',
          redirect: (c, s) =>
              '$accountPath/returns/${s.pathParameters['returnId']}',
        ),
      ],
      StatefulShellRoute.indexedStack(
        builder: (c, s, shell) => Scaffold(
          body: SafeArea(bottom: false, child: shell),
          bottomNavigationBar: NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: (index) {
              if (destinations[index].path.endsWith('/orders')) {
                ProviderScope.containerOf(
                  c,
                  listen: false,
                ).invalidate(orderListFoundationProvider);
              }
              shell.goBranch(
                index,
                initialLocation: index == shell.currentIndex,
              );
            },
            destinations: [
              for (final dest in destinations)
                NavigationDestination(icon: Icon(dest.icon), label: dest.label),
            ],
          ),
        ),
        branches: [
          for (final dest in destinations)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: dest.path,
                  builder: (c, s) => dest.page(c),
                  routes: dest.children,
                ),
              ],
            ),
        ],
      ),
    ],
  );
}

class _TitledPage extends StatelessWidget {
  const _TitledPage({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: child,
  );
}

class _Bell extends ConsumerWidget {
  const _Bell();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count =
        ref.watch(unreadCountFoundationProvider).asData?.value.data ?? 0;
    return IconButton(
      tooltip: 'Thông báo',
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sports Store'), actions: const [_Bell()]),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.asset(
            'assets/images/stride-runner.png',
            height: 230,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Sẵn sàng cho mọi chuyển động',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        const Text(
          'Khám phá sản phẩm thể thao, chọn biến thể phù hợp và theo dõi đơn hàng của bạn.',
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => context.go('/customer/products'),
          icon: const Icon(Icons.storefront_outlined),
          label: const Text('Khám phá sản phẩm'),
        ),
        OutlinedButton.icon(
          onPressed: () => context.go('/customer/orders'),
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('Đơn hàng của tôi'),
        ),
        TextButton.icon(
          onPressed: () => context.push('/chat'),
          icon: const Icon(Icons.chat_outlined),
          label: const Text('Liên hệ cửa hàng'),
        ),
      ],
    ),
  );
}

class _AccountPage extends StatelessWidget {
  const _AccountPage({
    required this.auth,
    required this.store,
    required this.reset,
  });
  final LocalAuthRepository auth;
  final LocalDemoStore store;
  final VoidCallback reset;
  @override
  Widget build(BuildContext context) {
    final role = store.session.role;
    return Scaffold(
      appBar: AppBar(title: const Text('Tài khoản'), actions: const [_Bell()]),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          const CircleAvatar(radius: 32, child: Icon(Icons.person, size: 40)),
          const SizedBox(height: 16),
          Text(
            switch (role) {
              'manager' => 'Quản lý cửa hàng',
              'shipper' => 'Nhân viên giao hàng',
              _ => 'Khách hàng',
            },
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Thông báo'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/notifications'),
          ),
          if (role != 'shipper')
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text('Hội thoại'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/chat'),
            ),
          if (role == 'manager')
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text('Đối soát COD'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/cod'),
            ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Thông tin ứng dụng'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'Sports Store',
              applicationVersion: 'PRM393',
              children: [
                const Text(
                  'Phiên bản chạy dữ liệu trên thiết bị. Không kết nối Supabase Cloud.',
                ),
              ],
            ),
          ),
          ListTile(
            key: const ValueKey('dev-logout'),
            leading: const Icon(Icons.logout),
            title: const Text('Đăng xuất'),
            onTap: auth.logout,
          ),
          const SizedBox(height: 60),
          GestureDetector(
            onLongPress: () => showDialog<void>(
              context: context,
              builder: (d) => AlertDialog(
                title: const Text('Cài đặt phát triển'),
                content: const Text('Khôi phục dữ liệu local ban đầu?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(d),
                    child: const Text('Đóng'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(d);
                      reset();
                    },
                    child: const Text('Khôi phục'),
                  ),
                ],
              ),
            ),
            child: const Center(
              child: Text(
                'Sports Store · PRM393',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
