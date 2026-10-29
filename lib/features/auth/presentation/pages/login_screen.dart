import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/prm_preview_widgets.dart';
import '../view_models/auth_view_model.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({
    super.key,
    required this.onRegister,
    this.onPreviewProducts,
    this.onPreviewInbox,
    this.onAuthenticated,
  });
  final VoidCallback onRegister;
  final VoidCallback? onPreviewProducts;
  final VoidCallback? onPreviewInbox;
  final VoidCallback? onAuthenticated;
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _visible = false;

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    final accepted = await ref
        .read(authViewModelProvider.notifier)
        .login(_email.text, _password.text);
    if (mounted && accepted) widget.onAuthenticated?.call();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth > 760;
      final form = _buildForm(context);
      if (wide) {
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Row(
                children: [
                  Expanded(child: _hero()),
                  const SizedBox(width: 48),
                  SizedBox(width: 390, child: form),
                ],
              ),
            ),
          ),
        );
      }

      return SingleChildScrollView(
        child: Column(
          children: [
            _hero(),
            Transform.translate(
              offset: const Offset(0, -20),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.fromLTRB(20, 19, 20, 22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x120B1720),
                      blurRadius: 24,
                      offset: Offset(0, 7),
                    ),
                  ],
                ),
                child: form,
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _hero() => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: SizedBox(
      height: 385,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/stride-runner.png',
            fit: BoxFit.cover,
            alignment: Alignment.centerRight,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  const Color(0xE9000000),
                  const Color(0x64000000),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(23, 20, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BrandMark(light: true),
                const Spacer(),
                const Text(
                  'Move\nStronger\nEveryday',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    height: .98,
                    letterSpacing: -.9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Đồng hành cùng bạn\ntrên mọi hành trình thể thao.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 19),
                const Row(
                  children: [
                    Expanded(
                      child: _Benefit(
                        icon: Icons.verified_outlined,
                        label: 'Sản phẩm\nchính hãng',
                      ),
                    ),
                    Expanded(
                      child: _Benefit(
                        icon: Icons.local_shipping_outlined,
                        label: 'Giao hàng\ntại Hà Nội',
                      ),
                    ),
                    Expanded(
                      child: _Benefit(
                        icon: Icons.support_agent_rounded,
                        label: 'Hỗ trợ\n24/7',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildForm(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 420),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Đăng nhập',
          style: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w800,
            letterSpacing: -.4,
            color: ink,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Chào mừng bạn quay trở lại!',
          style: TextStyle(fontSize: 12, color: muted),
        ),
        const SizedBox(height: 17),
        Form(
          key: _form,
          child: Column(
            children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.mail_outline_rounded, size: 19),
                  labelText: 'Email',
                  hintText: 'example@gmail.com',
                ),
                validator: (v) =>
                    v == null ||
                        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                            .hasMatch(v.trim())
                    ? 'Nhập địa chỉ email hợp lệ'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _password,
                obscureText: !_visible,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock_outline_rounded, size: 19),
                  labelText: 'Mật khẩu',
                  hintText: 'Nhập mật khẩu',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _visible = !_visible),
                    icon: Icon(
                      _visible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 19,
                    ),
                  ),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Vui lòng nhập mật khẩu' : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (ref.watch(authViewModelProvider).error case final message?)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(message, style: const TextStyle(color: Colors.red)),
          ),
        PrimaryButton(
          label: 'Đăng nhập',
          busy: ref.watch(authViewModelProvider).busy,
          onPressed: ref.watch(authViewModelProvider).busy ? null : _login,
        ),
        const SizedBox(height: 10),
        Center(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Chưa có tài khoản? ',
                style: TextStyle(fontSize: 11, color: ink),
              ),
              TextButton(
                onPressed: widget.onRegister,
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: const Text(
                  'Đăng ký ngay',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: ink,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.onPreviewProducts != null || widget.onPreviewInbox != null)
          Center(
            child: Wrap(
              spacing: 14,
              children: [
                TextButton(
                  onPressed: widget.onPreviewProducts,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                  ),
                  child: const Text(
                    'Quản lý sản phẩm',
                    style: TextStyle(fontSize: 9, color: muted),
                  ),
                ),
                TextButton(
                  onPressed: widget.onPreviewInbox,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                  ),
                  child: const Text(
                    'Hội thoại',
                    style: TextStyle(fontSize: 9, color: muted),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 29,
        height: 29,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white70),
        ),
        child: Icon(icon, color: Colors.white, size: 15),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 8,
            height: 1.2,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}
