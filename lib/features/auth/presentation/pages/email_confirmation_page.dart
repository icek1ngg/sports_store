import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/email_confirmation_result.dart';

class EmailConfirmationPage extends StatelessWidget {
  const EmailConfirmationPage({super.key, required this.result});

  final EmailConfirmationResult result;

  @override
  Widget build(BuildContext context) {
    final success = result == EmailConfirmationResult.success;
    final (title, message) = switch (result) {
      EmailConfirmationResult.success => (
        'Xác nhận email thành công!',
        'Email của bạn đã được xác nhận. Bạn có thể tiếp tục sử dụng tài khoản.',
      ),
      EmailConfirmationResult.expired => (
        'Liên kết xác nhận đã hết hạn',
        'Liên kết đã hết hạn hoặc đã được sử dụng. Vui lòng dùng email xác nhận '
            'mới nhất. Nếu đã xác nhận trước đó, bạn có thể đăng nhập.',
      ),
      EmailConfirmationResult.invalid => (
        'Liên kết xác nhận không hợp lệ',
        'Vui lòng mở đầy đủ liên kết trong email xác nhận đăng ký.',
      ),
      EmailConfirmationResult.failed => (
        'Chưa thể xác nhận email',
        'Không thể xác thực liên kết. Vui lòng thử mở lại email xác nhận mới nhất.',
      ),
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Sports Store')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        success
                            ? Icons.check_circle_outline_rounded
                            : Icons.mark_email_unread_outlined,
                        size: 64,
                        color: success
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 20),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(message, textAlign: TextAlign.center),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => context.go('/login'),
                        child: Text(success ? 'Tiếp tục' : 'Về đăng nhập'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
