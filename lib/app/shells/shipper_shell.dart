import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shared operational shell. Managers use COD without shipper-only navigation.
class ShipperShell extends StatelessWidget {
  const ShipperShell({
    super.key,
    required this.role,
    required this.location,
    required this.child,
  });
  final String role;
  final Uri location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cod = location.path == '/cod';
    final notifications = location.path == '/notifications';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          notifications
              ? 'Thông báo'
              : cod
              ? 'Đối soát tiền thu hộ'
              : 'Nhiệm vụ',
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
        ],
      ),
      body: child,
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
          : null,
    );
  }
}
