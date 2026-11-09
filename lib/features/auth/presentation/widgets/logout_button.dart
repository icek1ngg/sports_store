import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../view_models/auth_view_model.dart';

class LogoutButton extends ConsumerWidget {
  const LogoutButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(authViewModelProvider.select((state) => state.busy));
    return IconButton(
      tooltip: 'Đăng xuất',
      icon: const Icon(Icons.logout),
      onPressed: busy
          ? null
          : () async {
              final success = await ref
                  .read(authViewModelProvider.notifier)
                  .logout();
              if (!context.mounted) return;
              if (success) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted) {
                    context.go('/login');
                  }
                });
                WidgetsBinding.instance.ensureVisualUpdate();
              } else {
                final error = ref.read(authViewModelProvider).error;
                if (error != null) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(error)));
                }
              }
            },
    );
  }
}
