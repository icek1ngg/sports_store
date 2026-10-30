import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/view_models/auth_providers.dart';
import '../../features/auth/presentation/view_models/auth_view_model.dart';
import 'manager_navigation_bar.dart';

/// Navigation for the connected Dung An screens. The profile comes from RLS.
class StoreManagementShell extends ConsumerWidget {
  const StoreManagementShell({
    super.key,
    required this.profile,
    required this.inbox,
    required this.child,
  });

  final AppProfile profile;
  final bool inbox;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final form = ref.watch(authViewModelProvider);
    final manager = profile.role == AppRole.manager;
    return Scaffold(
      appBar: AppBar(
        title: Text(profile.fullName ?? 'Sports Store'),
        actions: [
          if (profile.role == AppRole.customer)
            IconButton(
              tooltip: 'Danh mục sản phẩm',
              onPressed: () => context.go('/customer/products'),
              icon: const Icon(Icons.storefront_outlined),
            ),
          TextButton.icon(
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
      body: SafeArea(
        child: Column(
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
      ),
      bottomNavigationBar: manager
          ? ManagerNavigationBar(selectedIndex: inbox ? 1 : 0)
          : null,
    );
  }
}
