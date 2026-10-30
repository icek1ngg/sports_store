import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/pages/login_screen.dart';
import '../../features/auth/presentation/view_models/auth_providers.dart';
import '../../features/auth/presentation/view_models/auth_view_model.dart';
import '../../features/catalog/presentation/pages/product_management_screen.dart';
import '../../features/chat/presentation/pages/conversation_list_screen.dart';
import '../../features/chat/presentation/view_models/chat_providers.dart';
import '../../features/orders/presentation/pages/manager_orders_page.dart';
import '../../features/orders/presentation/view_models/order_providers.dart';
import '../shells/store_management_shell.dart';

/// This boundary discards old data immediately when an auth epoch changes.
class DungAnRoutePage extends ConsumerWidget {
  const DungAnRoutePage({super.key, this.inbox = false, this.detailBuilder});
  final bool inbox;
  final WidgetBuilder? detailBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    if (session.isLoading) return const _AccessStatus();
    if (session.hasError) {
      return _AccessStatus(
        message: 'Không thể kiểm tra phiên đăng nhập.',
        retry: () => ref.invalidate(authSessionProvider),
      );
    }
    if (session.asData?.value.signedIn != true) {
      return Scaffold(
        body: SafeArea(
          child: LoginScreen(
            onRegister: () => context.go('/register'),
            onAuthenticated: () => context.go('/'),
          ),
        ),
      );
    }
    final profileState = ref.watch(currentProfileProvider);
    if (profileState.isLoading) return const _AccessStatus();
    if (profileState.hasError || profileState.asData?.value == null) {
      return _AccessStatus(
        message: 'Không tải được hồ sơ và quyền tài khoản.',
        retry: () => ref.invalidate(currentProfileProvider),
        logout: () => ref.read(authViewModelProvider.notifier).logout(),
      );
    }
    final profile = profileState.requireValue!;
    if (profile.id != session.requireValue.userId) return const _AccessStatus();
    final path = GoRouterState.of(context).uri.path;
    if (profile.role == AppRole.shipper) {
      final path = GoRouterState.of(context).uri.path;
      if (path == '/' || path == '/login') {
        return _ShipperEntry(key: ValueKey(profile.id), userId: profile.id);
      }
      return _AccessStatus(
        message: 'Tài khoản giao hàng',
        retryLabel: 'Mở nhiệm vụ giao hàng',
        retry: () => context.go('/shipper/tasks'),
        logout: () => ref.read(authViewModelProvider.notifier).logout(),
      );
    }
    if (path.startsWith('/manager/') && profile.role != AppRole.manager ||
        path.startsWith('/customer/') && profile.role != AppRole.customer) {
      return _AccessStatus(
        message: path == '/manager/products'
            ? 'Chỉ quản lý được truy cập màn sản phẩm.'
            : 'Tài khoản không có quyền truy cập màn này.',
        retryLabel: 'Về trang chính',
        retry: () => context.go(homeRouteForRole(profile.role)),
      );
    }
    final showInbox = inbox;
    Widget content;
    if (detailBuilder != null) {
      content = detailBuilder!(context);
    } else if (showInbox) {
      content = ConversationListScreen(
        isCustomer: profile.role == AppRole.customer,
        onOpenConversation: (id) async {
          final openedSession = session.requireValue;
          await context.push('/chat/$id');
          if (context.mounted &&
              identical(
                ref.read(authSessionProvider).asData?.value,
                openedSession,
              )) {
            ref.invalidate(chatInboxProvider);
          }
        },
      );
    } else if (path == '/manager/orders') {
      content = ref.watch(orderRepositoryProvider) == null
          ? const _ModuleUnavailable(
              'Dịch vụ quản lý đơn hàng chưa được tích hợp.',
            )
          : const ManagerOrdersPage();
    } else {
      content = const ProductManagementScreen();
    }
    return StoreManagementShell(
      key: ObjectKey(session.requireValue),
      profile: profile,
      inbox: showInbox,
      child: content,
    );
  }
}

class _ShipperEntry extends ConsumerStatefulWidget {
  const _ShipperEntry({super.key, required this.userId});
  final String userId;

  @override
  ConsumerState<_ShipperEntry> createState() => _ShipperEntryState();
}

class _ShipperEntryState extends ConsumerState<_ShipperEntry> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final session = ref.read(authSessionProvider);
      final profile = ref.read(currentProfileProvider);
      final path = GoRouterState.of(context).uri.path;
      if (!session.isLoading &&
          !profile.isLoading &&
          session.asData?.value.userId == widget.userId &&
          profile.asData?.value?.id == widget.userId &&
          profile.asData?.value?.role == AppRole.shipper &&
          (path == '/' || path == '/login')) {
        context.go('/shipper/tasks');
      }
    });
  }

  @override
  Widget build(BuildContext context) => const _AccessStatus();
}

class _ModuleUnavailable extends StatelessWidget {
  const _ModuleUnavailable(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}

class _AccessStatus extends ConsumerWidget {
  const _AccessStatus({
    this.message = 'Đang kiểm tra tài khoản…',
    this.retry,
    this.retryLabel = 'Thử lại',
    this.logout,
  });
  final String message;
  final VoidCallback? retry;
  final String retryLabel;
  final Future<bool> Function()? logout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final form = ref.watch(authViewModelProvider);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (retry == null && logout == null)
              const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message),
            if (logout != null && form.error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(form.error!),
              ),
            if (retry != null)
              TextButton(onPressed: retry, child: Text(retryLabel)),
            if (logout != null)
              TextButton(
                onPressed: form.busy
                    ? null
                    : () async {
                        if (await logout!() && context.mounted) {
                          context.go('/login');
                        }
                      },
                child: const Text('Đăng xuất'),
              ),
          ],
        ),
      ),
    );
  }
}
