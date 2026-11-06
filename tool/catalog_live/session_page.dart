import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';

import 'session_view_model.dart';

class CatalogLiveSessionPage extends ConsumerStatefulWidget {
  const CatalogLiveSessionPage({super.key});

  @override
  ConsumerState<CatalogLiveSessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends ConsumerState<CatalogLiveSessionPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final attempt = ref
        .read(liveCatalogSessionViewModelProvider.notifier)
        .signIn(_email.text, _password.text);
    _password.clear();
    if (await attempt && mounted) context.go('/customer/products');
  }

  @override
  Widget build(BuildContext context) {
    final action = ref.watch(liveCatalogSessionViewModelProvider);
    final session = ref.watch(operationalSessionProvider);
    final signedIn =
        !session.isLoading &&
        session.asData?.value.userId != null &&
        session.asData?.value.failure == null;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Chạy thử cửa hàng')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.sports_basketball_outlined,
                      size: 56,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Sản phẩm và giỏ hàng',
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Đăng nhập bằng tài khoản khách hàng để xem sản phẩm '
                      'và sử dụng giỏ hàng. Phiên đăng nhập chỉ được lưu '
                      'trong lần chạy này.',
                    ),
                    const SizedBox(height: 24),
                    if (signedIn) ...[
                      const Text('Đã có phiên đăng nhập.'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: action.isLoading
                            ? null
                            : () => context.go('/customer/products'),
                        child: const Text('Mở danh mục sản phẩm'),
                      ),
                      TextButton(
                        onPressed: action.isLoading
                            ? null
                            : () => ref
                                  .read(
                                    liveCatalogSessionViewModelProvider
                                        .notifier,
                                  )
                                  .signOut(),
                        child: const Text('Đăng xuất / Đổi tài khoản'),
                      ),
                    ] else ...[
                      TextFormField(
                        controller: _email,
                        enabled: !action.isLoading,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Địa chỉ thư điện tử',
                        ),
                        validator: (value) =>
                            value == null || !value.trim().contains('@')
                            ? 'Nhập địa chỉ thư điện tử hợp lệ.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        enabled: !action.isLoading,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Mật khẩu',
                        ),
                        onFieldSubmitted: (_) =>
                            action.isLoading ? null : _submit(),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Nhập mật khẩu.'
                            : null,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: action.isLoading ? null : _submit,
                        child: Text(
                          action.isLoading ? 'Đang đăng nhập…' : 'Đăng nhập',
                        ),
                      ),
                    ],
                    if (action.hasError) ...[
                      const SizedBox(height: 16),
                      Text(
                        action.error! as String,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 24),
                    const Text(
                      'Đây là công cụ thử dữ liệu, không thay thế MH01 của nhóm.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
