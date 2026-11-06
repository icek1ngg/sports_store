import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/app_profile.dart';
import '../../domain/repositories/auth_repository.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);
  final SupabaseClient _client;

  AuthSession _session(Session? value) => value == null || value.isExpired
      ? const AuthSession()
      : AuthSession(userId: value.user.id, accessToken: value.accessToken);

  @override
  AuthSession get currentSession => _session(_client.auth.currentSession);

  @override
  Stream<AuthSession> watchSession() => Stream<AuthSession>.multi((controller) {
    final subscription = _client.auth.onAuthStateChange.listen(
      (event) => controller.addSync(_session(event.session)),
      onError: controller.addErrorSync,
      onDone: controller.closeSync,
    );
    controller.addSync(currentSession);
    controller.onCancel = subscription.cancel;
  }).distinct((a, b) => a.userId == b.userId && a.accessToken == b.accessToken);

  @override
  Future<AppProfile?> getCurrentProfile() async {
    final session = currentSession;
    if (!session.signedIn) return null;
    try {
      final row = await _client
          .from('profiles')
          .select('id,role,full_name,phone')
          .eq('id', session.userId!)
          .setHeader('Authorization', 'Bearer ${session.accessToken}')
          .retry(enabled: false, requestTimeout: const Duration(seconds: 15))
          .maybeSingle();
      if (currentSession.accessToken != session.accessToken) {
        throw const AuthenticationFailure('Phiên đăng nhập đã thay đổi.');
      }
      if (row == null || row['id'] != session.userId) {
        throw const AuthenticationFailure(
          'Không tải được hồ sơ tài khoản. Vui lòng thử lại.',
        );
      }
      final role = switch (row['role']) {
        'customer' => AppRole.customer,
        'manager' => AppRole.manager,
        'shipper' => AppRole.shipper,
        _ => throw const AuthenticationFailure(
          'Tài khoản chưa có quyền truy cập hợp lệ.',
        ),
      };
      return AppProfile(
        id: row['id'] as String,
        role: role,
        fullName: row['full_name'] as String?,
        phone: row['phone'] as String?,
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> login({required String email, required String password}) async {
    try {
      final result = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (result.session == null) {
        throw const AuthenticationFailure('Không thể tạo phiên đăng nhập.');
      }
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<RegistrationResult> register({
    required String fullName,
    required String phone,
    required String email,
    required String password,
  }) async {
    try {
      final result = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'full_name': fullName.trim(), 'phone': phone.trim()},
      );
      if (result.user == null) {
        throw const AuthenticationFailure('Chưa thể tạo tài khoản.');
      }
      return RegistrationResult(needsEmailConfirmation: result.session == null);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> logout() async {
    try {
      await _client.auth.signOut();
    } catch (error) {
      throw _failure(error);
    }
  }

  AuthenticationFailure _failure(Object error) {
    if (error is AuthenticationFailure) return error;
    if (error is AuthException) {
      return AuthenticationFailure(switch (error.code) {
        'invalid_credentials' => 'Email hoặc mật khẩu không đúng.',
        'email_not_confirmed' => 'Vui lòng xác nhận email trước khi đăng nhập.',
        'user_already_exists' ||
        'email_exists' => 'Email đã được đăng ký. Vui lòng đăng nhập.',
        'weak_password' =>
          'Mật khẩu chưa đủ mạnh. Vui lòng chọn mật khẩu khác.',
        'over_email_send_rate_limit' || 'over_request_rate_limit' =>
          'Bạn thao tác quá nhanh. Vui lòng chờ rồi thử lại.',
        'signup_disabled' => 'Đăng ký tài khoản hiện chưa khả dụng.',
        _ => 'Không thể xác thực tài khoản. Vui lòng thử lại.',
      });
    }
    return const AuthenticationFailure(
      'Không thể kết nối dịch vụ tài khoản. Vui lòng thử lại.',
    );
  }
}
