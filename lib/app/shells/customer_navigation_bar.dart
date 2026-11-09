import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/view_models/auth_providers.dart';
import '../../features/auth/presentation/widgets/logout_button.dart';
import '../theme/storefront_theme.dart';

class CustomerNavigationBar extends ConsumerWidget {
  const CustomerNavigationBar({required this.location, super.key});
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = location == '/customer/orders'
        ? 1
        : location == '/customer/cart'
        ? 2
        : 0;
    const labels = ['Sản phẩm', 'Đơn hàng', 'Giỏ hàng', 'Tài khoản'];
    const icons = [
      Icons.grid_view_outlined,
      Icons.receipt_long_outlined,
      Icons.shopping_bag_outlined,
      Icons.person_outline,
    ];
    return StorefrontTheme(
      child: Material(
        key: const ValueKey('customer-navigation'),
        color: Colors.white,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xffeeeeee))),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 64 + MediaQuery.textScalerOf(context).scale(11),
              child: Row(
                children: [
                  for (var index = 0; index < labels.length; index++)
                    Expanded(
                      child: Semantics(
                        selected: selected == index,
                        button: true,
                        label: labels[index],
                        child: Tooltip(
                          message: labels[index],
                          child: InkWell(
                            key: ValueKey('customer-tab-$index'),
                            onTap: () {
                              if (index == 3) {
                                showCustomerAccount(context);
                                return;
                              }
                              if (selected == index) return;
                              if (index == 2) {
                                context.push('/customer/cart');
                                return;
                              }
                              context.go(
                                index == 0
                                    ? '/customer/products'
                                    : '/customer/orders',
                              );
                            },
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 23,
                                  height: 3,
                                  margin: const EdgeInsets.only(bottom: 7),
                                  decoration: BoxDecoration(
                                    color: selected == index
                                        ? StorefrontTheme.ink
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                Icon(
                                  icons[index],
                                  size: 23,
                                  color: selected == index
                                      ? StorefrontTheme.ink
                                      : StorefrontTheme.muted,
                                ),
                                const SizedBox(height: 5),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                  ),
                                  child: Text(
                                    labels[index],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: selected == index
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: selected == index
                                          ? StorefrontTheme.ink
                                          : StorefrontTheme.muted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showCustomerAccount(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StorefrontTheme(
        child: Consumer(
          builder: (context, ref, _) {
            final profile = ref.watch(currentProfileProvider);
            if (profile.isLoading) {
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (profile.hasError || profile.asData?.value == null) {
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Không tải được thông tin tài khoản.'),
                      TextButton(
                        onPressed: () => ref.invalidate(currentProfileProvider),
                        child: const Text('Thử lại'),
                      ),
                      const LogoutButton(),
                    ],
                  ),
                ),
              );
            }
            final account = profile.requireValue!;
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TÀI KHOẢN',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 18),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        backgroundColor: StorefrontTheme.cloud,
                        child: Icon(
                          Icons.person_outline,
                          color: StorefrontTheme.ink,
                        ),
                      ),
                      title: Text(
                        account.fullName?.trim().isNotEmpty == true
                            ? account.fullName!
                            : 'Tài khoản của bạn',
                      ),
                      subtitle: Text(
                        account.phone?.trim().isNotEmpty == true
                            ? account.phone!
                            : 'Khách hàng STRIDE',
                      ),
                    ),
                    const Divider(height: 28),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: const Text('Đơn hàng của tôi'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        final router = GoRouter.of(context);
                        Navigator.pop(sheetContext);
                        router.go('/customer/orders');
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.chat_bubble_outline),
                      title: const Text('Liên hệ cửa hàng'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        final router = GoRouter.of(context);
                        Navigator.pop(sheetContext);
                        router.push('/chat');
                      },
                    ),
                    const Divider(height: 28),
                    const Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Đăng xuất',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        LogoutButton(),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
