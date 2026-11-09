import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/view_models/auth_providers.dart';
import '../../features/auth/presentation/view_models/auth_view_model.dart';
import '../../features/notifications/presentation/providers/notification_providers.dart';

/// One role navigation surface. Authentication and route authorization remain
/// owned by the production router; this widget never constructs another app.
class SportsStoreShell extends StatelessWidget {
  const SportsStoreShell({
    required this.child,
    required this.role,
    required this.location,
    this.onDestinationSelected,
    this.showNavigation = true,
    super.key,
  });

  final Widget child;
  final String role;
  final Uri location;
  final ValueChanged<int>? onDestinationSelected;
  final bool showNavigation;

  @override
  Widget build(BuildContext context) {
    final destinations = switch (role) {
      'customer' => const [
        ('/customer/home', 'Trang chủ', Icons.home_outlined),
        ('/customer/products', 'Sản phẩm', Icons.storefront_outlined),
        ('/customer/cart', 'Giỏ hàng', Icons.shopping_bag_outlined),
        ('/customer/orders', 'Đơn hàng', Icons.receipt_long_outlined),
        ('/customer/account', 'Tài khoản', Icons.person_outline),
      ],
      'manager' => const [
        ('/manager/orders', 'Đơn hàng', Icons.receipt_long_outlined),
        ('/manager/products', 'Sản phẩm', Icons.inventory_2_outlined),
        ('/manager/returns', 'Trả hàng', Icons.assignment_return_outlined),
        ('/manager/account', 'Tài khoản', Icons.person_outline),
      ],
      'shipper' => const [
        ('/shipper/tasks', 'Giao hàng', Icons.local_shipping_outlined),
        ('/cod', 'Thu hộ COD', Icons.payments_outlined),
        ('/shipper/account', 'Tài khoản', Icons.person_outline),
      ],
      _ => const <(String, String, IconData)>[],
    };

    final selected = destinations.indexWhere(
      (destination) =>
          location.path == destination.$1 ||
          location.path.startsWith('${destination.$1}/'),
    );
    // Shared inbox/chat/COD pages belong to the account menu for a manager or
    // customer. Keep their account tab selected instead of inventing a tab.
    final index = selected < 0 ? destinations.length - 1 : selected;
    final taskPage =
        role == 'shipper' &&
        (location.path == '/shipper/tasks' ||
            location.path.startsWith('/shipper/tasks/'));
    final codPage = location.path == '/cod';
    final taskDetail = taskPage && location.path != '/shipper/tasks';
    return Scaffold(
      // Trusted profile revalidation temporarily clears role. Keep the shell
      // and its Navigator mounted; route boundaries hide private content.
      key: const ValueKey('sports-store-shell'),
      // Delivery/map/COD pages are content outlets: their previous shell owned
      // the app bar. Keep that affordance here rather than mounting that shell.
      appBar: showNavigation && (taskPage || codPage)
          ? AppBar(
              title: Text(
                codPage
                    ? 'Thu hộ COD'
                    : location.path.endsWith('/map')
                    ? 'Bản đồ'
                    : taskDetail
                    ? 'Chi tiết giao hàng'
                    : 'Giao hàng',
              ),
              leading: taskDetail || (codPage && role == 'manager')
                  ? BackButton(
                      onPressed: () => context.canPop()
                          ? context.pop()
                          : context.go(
                              role == 'shipper'
                                  ? '/shipper/tasks'
                                  : '/manager/account',
                            ),
                    )
                  : null,
              actions: const [SportsStoreNotificationBell()],
            )
          : null,
      body: SafeArea(bottom: false, child: child),
      bottomNavigationBar: showNavigation && destinations.isNotEmpty
          ? NavigationBar(
              key: ValueKey('$role-navigation'),
              selectedIndex: index,
              onDestinationSelected:
                  onDestinationSelected ??
                  (index) => context.go(destinations[index].$1),
              destinations: [
                for (final destination in destinations)
                  NavigationDestination(
                    icon: Icon(destination.$3),
                    label: destination.$2,
                  ),
              ],
            )
          : null,
    );
  }
}

class SportsStoreNotificationBell extends ConsumerWidget {
  const SportsStoreNotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(unreadCountFoundationProvider).asData?.value;
    final count = snapshot?.isFresh == true ? snapshot!.data : null;
    return IconButton(
      key: const ValueKey('open-notifications'),
      tooltip: 'Thông báo',
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        isLabelVisible: count != null && count > 0,
        label: Text('${count ?? 0}'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}

/// Shared home presentation; catalog and orders continue reading their
/// production repositories after navigation.
class SportsStoreHomePage extends StatelessWidget {
  const SportsStoreHomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Sports Store'),
      actions: const [SportsStoreNotificationBell()],
    ),
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

class SportsStoreAccountPage extends ConsumerWidget {
  const SportsStoreAccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    final form = ref.watch(authViewModelProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tài khoản'),
        actions: const [SportsStoreNotificationBell()],
      ),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(currentProfileProvider),
            child: const Text('Không tải được hồ sơ. Thử lại'),
          ),
        ),
        data: (account) {
          if (account == null) {
            return const Center(child: Text('Phiên đăng nhập không khả dụng.'));
          }
          final roleLabel = switch (account.role) {
            AppRole.manager => 'Quản lý cửa hàng',
            AppRole.shipper => 'Nhân viên giao hàng',
            AppRole.customer => 'Khách hàng',
          };
          return ListView(
            children: [
              const SizedBox(height: 24),
              const CircleAvatar(
                radius: 32,
                child: Icon(Icons.person, size: 40),
              ),
              const SizedBox(height: 16),
              Text(
                account.fullName ?? roleLabel,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (account.fullName != null)
                Text(roleLabel, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Thông báo'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/notifications'),
              ),
              if (account.role != AppRole.shipper)
                ListTile(
                  leading: const Icon(Icons.chat_outlined),
                  title: const Text('Hội thoại'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/chat'),
                ),
              if (account.role == AppRole.manager)
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
                ),
              ),
              if (form.error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    form.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ListTile(
                key: const ValueKey('account-logout'),
                enabled: !form.busy,
                leading: const Icon(Icons.logout),
                title: Text(form.busy ? 'Đang đăng xuất…' : 'Đăng xuất'),
                onTap: () async {
                  final ok = await ref
                      .read(authViewModelProvider.notifier)
                      .logout();
                  if (ok) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (context.mounted) {
                        context.go('/login');
                      }
                    });
                    WidgetsBinding.instance.ensureVisualUpdate();
                  }
                },
              ),
              const SizedBox(height: 32),
              const Center(child: Text('Sports Store · PRM393')),
            ],
          );
        },
      ),
    );
  }
}
