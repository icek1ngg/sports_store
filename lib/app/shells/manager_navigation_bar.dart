import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shared manager destinations, including the role-protected MH12 route.
class ManagerNavigationBar extends StatelessWidget {
  const ManagerNavigationBar({super.key, required this.selectedIndex});

  final int selectedIndex;

  @override
  Widget build(BuildContext context) => NavigationBar(
    key: const ValueKey('manager-navigation'),
    selectedIndex: selectedIndex,
    onDestinationSelected: (index) => context.go(
      const ['/manager/orders', '/manager/products', '/chat', '/cod'][index],
    ),
    destinations: const [
      NavigationDestination(
        icon: Icon(Icons.receipt_long_outlined),
        label: 'Đơn hàng',
      ),
      NavigationDestination(
        icon: Icon(Icons.inventory_2_outlined),
        label: 'Sản phẩm',
      ),
      NavigationDestination(
        icon: Icon(Icons.chat_bubble_outline),
        label: 'Hội thoại',
      ),
      NavigationDestination(icon: Icon(Icons.payments_outlined), label: 'COD'),
    ],
  );
}
