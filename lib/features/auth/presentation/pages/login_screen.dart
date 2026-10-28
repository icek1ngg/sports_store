import 'package:flutter/material.dart';

import '../../../../shared/widgets/prm_preview_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.onRegister,
    required this.onPreviewProducts,
    required this.onPreviewInbox,
  });
  final VoidCallback onRegister;
  final VoidCallback onPreviewProducts;
  final VoidCallback onPreviewInbox;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _visible = false;
  bool _remember = false;

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
                        label: 'Giao hàng\ntoàn quốc',
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
        const SizedBox(height: 6),
        Row(
          children: [
            SizedBox(
              width: 23,
              height: 23,
              child: Checkbox(
                value: _remember,
                onChanged: (v) => setState(() => _remember = v ?? false),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                activeColor: forest,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 5),
            const Text(
              'Ghi nhớ đăng nhập',
              style: TextStyle(fontSize: 10, color: ink),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => showNotice(
                context,
                'Khôi phục mật khẩu sẽ khả dụng khi kết nối Supabase.',
              ),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: const Text(
                'Quên mật khẩu?',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        PrimaryButton(
          label: 'Đăng nhập',
          onPressed: () {
            if (_form.currentState!.validate()) {
              showNotice(
                context,
                'Chưa cấu hình Supabase Auth. Biểu mẫu đã sẵn sàng kết nối backend.',
              );
            }
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(child: Divider(color: line)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'hoặc',
                style: TextStyle(
                  fontSize: 11,
                  color: muted.withValues(alpha: .9),
                ),
              ),
            ),
            const Expanded(child: Divider(color: line)),
          ],
        ),
        const SizedBox(height: 9),
        _socialButton(
          context,
          'Đăng nhập với Google',
          Icons.g_mobiledata_rounded,
        ),
        const SizedBox(height: 7),
        _socialButton(context, 'Đăng nhập với Apple', Icons.apple_rounded),
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
                  'Xem trước quản lý sản phẩm',
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
                  'Hội thoại demo',
                  style: TextStyle(fontSize: 9, color: muted),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _socialButton(BuildContext context, String title, IconData icon) =>
      SizedBox(
        width: double.infinity,
        height: 40,
        child: OutlinedButton.icon(
          onPressed: () =>
              showNotice(context, 'Đăng nhập OAuth cần cấu hình provider.'),
          icon: Icon(icon, size: 19),
          label: Text(
            title,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: ink,
            side: const BorderSide(color: line),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
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
