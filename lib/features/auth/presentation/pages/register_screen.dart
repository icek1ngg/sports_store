import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/prm_preview_widgets.dart';
import '../view_models/auth_view_model.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, required this.onLogin});
  final VoidCallback onLogin;
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _terms = true;
  bool _showPassword = false;

  Future<void> _register() async {
    if (!_form.currentState!.validate()) return;
    if (!_terms) {
      showNotice(context, 'Vui lòng đồng ý với điều khoản để tiếp tục.');
      return;
    }
    await ref
        .read(authViewModelProvider.notifier)
        .register(
          fullName: _name.text,
          phone: _phone.text,
          email: _email.text,
          password: _password.text,
        );
    if (!mounted) return;
    final notice = ref.read(authViewModelProvider).notice;
    if (notice != null) {
      _password.clear();
      _confirm.clear();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth > 620;
      return SingleChildScrollView(
        child: Column(
          children: [
            _hero(),
            Transform.translate(
              offset: const Offset(0, -18),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 480),
                margin: EdgeInsets.symmetric(horizontal: wide ? 0 : 16),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x100B1720),
                      blurRadius: 22,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: _formContent(context),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _hero() => SizedBox(
    height: 300,
    width: double.infinity,
    child: ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/stride-products.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xDDF4FBF9),
                  Color(0x80F4FBF9),
                  Colors.transparent,
                ],
                stops: [0, .43, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BrandMark(),
                const SizedBox(height: 14),
                const Text(
                  'Bắt đầu hành trình\nthể thao cùng STRIDE',
                  style: TextStyle(
                    fontSize: 23,
                    height: 1.08,
                    letterSpacing: -.45,
                    fontWeight: FontWeight.w900,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Tạo tài khoản để khám phá hàng nghìn\nsản phẩm thể thao chính hãng.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: Color(0xFF49544F),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _formContent(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Đăng ký tài khoản',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink),
      ),
      const SizedBox(height: 3),
      const Text(
        'Chỉ mất 1 phút để bắt đầu',
        style: TextStyle(fontSize: 11, color: muted),
      ),
      const SizedBox(height: 12),
      Form(
        key: _form,
        child: Column(
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.person_outline_rounded, size: 18),
                labelText: 'Họ và tên',
                hintText: 'Nguyễn Văn A',
              ),
              validator: (v) => v == null || v.trim().length < 2
                  ? 'Vui lòng nhập họ tên'
                  : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.mail_outline_rounded, size: 18),
                labelText: 'Email',
                hintText: 'example@gmail.com',
              ),
              validator: (v) =>
                  v == null ||
                      !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())
                  ? 'Nhập địa chỉ email hợp lệ'
                  : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.phone_outlined, size: 18),
                labelText: 'Số điện thoại',
                hintText: '0123 456 789',
              ),
              validator: (v) =>
                  v == null ||
                      !RegExp(r'^(0|\+84)[0-9 .-]{8,12}$').hasMatch(v.trim())
                  ? 'Nhập số điện thoại hợp lệ tại Việt Nam'
                  : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _password,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                labelText: 'Mật khẩu',
                hintText: 'Tạo mật khẩu (tối thiểu 8 ký tự)',
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                  ),
                ),
              ),
              validator: (v) => v == null || v.length < 8
                  ? 'Mật khẩu cần ít nhất 8 ký tự'
                  : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _confirm,
              obscureText: !_showPassword,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.lock_outline_rounded, size: 18),
                labelText: 'Xác nhận mật khẩu',
                hintText: 'Nhập lại mật khẩu',
              ),
              validator: (v) =>
                  v != _password.text ? 'Mật khẩu xác nhận chưa khớp' : null,
            ),
          ],
        ),
      ),
      const SizedBox(height: 7),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Checkbox(
              value: _terms,
              onChanged: (v) => setState(() => _terms = v ?? false),
              activeColor: forest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 5),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Tôi đồng ý với Điều khoản dịch vụ và Chính sách bảo mật',
                style: TextStyle(fontSize: 10, color: ink),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 9),
      if (ref.watch(authViewModelProvider).error case final message?)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(message, style: const TextStyle(color: Colors.red)),
        ),
      if (ref.watch(authViewModelProvider).notice case final message?)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(message, style: const TextStyle(color: forest)),
        ),
      PrimaryButton(
        label: 'Đăng ký',
        busy: ref.watch(authViewModelProvider).busy,
        onPressed: ref.watch(authViewModelProvider).busy ? null : _register,
      ),
      const SizedBox(height: 5),
      Center(
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Đã có tài khoản? ',
              style: TextStyle(fontSize: 10, color: ink),
            ),
            TextButton(
              onPressed: widget.onLogin,
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: const Text(
                'Đăng nhập',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: ink,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
