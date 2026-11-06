import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/view_models/auth_view_model.dart';
import 'manager_navigation_bar.dart';

/// Shared operational shell. Managers use COD without shipper-only navigation.
class ShipperShell extends ConsumerWidget {
  const ShipperShell({
    super.key,
    required this.role,
    required this.location,
    required this.child,
    this.shipperId,
  });
  final String role;
  final Uri location;
  final Widget child;
  final String? shipperId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final form = ref.watch(authViewModelProvider);
    // Return management draws its own header (same as MH13/MH14); only the
    // list shows the manager navigation.
    if (role == 'manager' && location.path.startsWith('/manager/returns')) {
      return Scaffold(
        body: child,
        bottomNavigationBar: location.path == '/manager/returns'
            ? const ManagerNavigationBar(selectedIndex: 4)
            : null,
      );
    }
    final cod = location.path == '/cod';
    final notifications = location.path == '/notifications';
    final map =
        location.pathSegments.length == 4 &&
        location.pathSegments[0] == 'shipper' &&
        location.pathSegments[1] == 'tasks' &&
        location.pathSegments[3] == 'map';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          notifications
              ? 'Thông báo'
              : cod
              ? 'Đối soát tiền thu hộ'
              : map
              ? 'Bản đồ'
              : location.path == '/shipper/tasks' && shipperId != null
              ? shipperId!
              : 'Nhiệm vụ',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: role == 'manager' && cod
            ? IconButton(
                key: const ValueKey('manager-home'),
                tooltip: 'Về quản lý đơn hàng',
                icon: const Icon(Icons.home_outlined),
                onPressed: () => context.go('/manager/orders'),
              )
            : location.path != '/shipper/tasks' && !cod
            ? BackButton(
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go(role == 'shipper' ? '/shipper/tasks' : '/'),
              )
            : null,
        actions: [
          if (!notifications)
            IconButton(
              key: const ValueKey('open-notifications'),
              tooltip: 'Thông báo',
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () => context.push('/notifications'),
            ),
          TextButton.icon(
            key: const ValueKey('shipper-logout'),
            onPressed: form.busy
                ? null
                : () async {
                    final ok = await ref
                        .read(authViewModelProvider.notifier)
                        .logout();
                    if (ok && context.mounted) context.go('/login');
                  },
            icon: const Icon(Icons.logout),
            label: const Text('Đăng xuất'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (form.error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                form.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: role == 'shipper'
          ? NavigationBar(
              key: const ValueKey('shipper-navigation'),
              selectedIndex: cod ? 1 : 0,
              onDestinationSelected: (index) =>
                  context.go(index == 0 ? '/shipper/tasks' : '/cod'),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.local_shipping_outlined),
                  label: 'Nhiệm vụ',
                ),
                NavigationDestination(
                  icon: Icon(Icons.payments_outlined),
                  label: 'Tiền thu hộ',
                ),
              ],
            )
          : role == 'manager' && cod
          ? const ManagerNavigationBar(selectedIndex: 3)
          : null,
    );
  }
}
