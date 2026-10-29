// Bản xem thử giao diện nhập từ prm; không sử dụng backend production.
import 'package:flutter/material.dart';

import 'package:sports_store/features/auth/presentation/pages/login_screen.dart';
import 'package:sports_store/features/auth/presentation/pages/register_screen.dart';
import 'package:sports_store/features/catalog/presentation/pages/product_management_screen.dart';
import 'package:sports_store/features/chat/presentation/pages/conversation_list_screen.dart';
import 'package:sports_store/shared/widgets/prm_preview_widgets.dart';

void main() => runApp(const StrideApp());

class StrideApp extends StatefulWidget {
  const StrideApp({super.key});
  @override
  State<StrideApp> createState() => _StrideAppState();
}

class _StrideAppState extends State<StrideApp> {
  String _route = 'login';
  void _go(String route) => setState(() => _route = route);
  int get _selectedIndex => _route == 'products'
      ? 2
      : _route == 'inbox'
      ? 4
      : 0;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'STRIDE',
    debugShowCheckedModeBanner: false,
    theme: buildPrmTheme(),
    home: Scaffold(
      body: SafeArea(
        child: switch (_route) {
          'register' => RegisterScreen(onLogin: () => _go('login')),
          'products' => const ProductManagementScreen(),
          'inbox' => const ConversationListScreen(),
          _ => LoginScreen(
            onRegister: () => _go('register'),
            onPreviewProducts: () => _go('products'),
            onPreviewInbox: () => _go('inbox'),
          ),
        },
      ),
      bottomNavigationBar: _route == 'products' || _route == 'inbox'
          ? NavigationBar(
              selectedIndex: _selectedIndex,
              height: 64,
              onDestinationSelected: (index) {
                if (index == 2) {
                  _go('products');
                }
                if (index == 4) {
                  _go('inbox');
                }
                if (index != 2 && index != 4) {
                  showNotice(
                    context,
                    'Màn hình này nằm ngoài phạm vi Dung An.',
                  );
                }
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined, size: 19),
                  label: 'Tổng quan',
                ),
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined, size: 19),
                  label: 'Đơn hàng',
                ),
                NavigationDestination(
                  icon: Icon(Icons.shopping_bag_outlined, size: 19),
                  label: 'Sản phẩm',
                ),
                NavigationDestination(
                  icon: Icon(Icons.people_outline_rounded, size: 19),
                  label: 'Khách hàng',
                ),
                NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outline_rounded, size: 19),
                  label: 'Hội thoại',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined, size: 19),
                  label: 'Cài đặt',
                ),
              ],
            )
          : null,
    ),
  );
}
