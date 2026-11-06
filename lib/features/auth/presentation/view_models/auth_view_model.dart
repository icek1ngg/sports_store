import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_providers.dart';

class AuthFormState {
  const AuthFormState({this.busy = false, this.error, this.notice});
  final bool busy;
  final String? error;
  final String? notice;
}

final authViewModelProvider =
    NotifierProvider.autoDispose<AuthViewModel, AuthFormState>(
      AuthViewModel.new,
    );

class AuthViewModel extends Notifier<AuthFormState> {
  @override
  AuthFormState build() => const AuthFormState();

  Future<bool> login(String email, String password) async {
    if (state.busy) return false;
    state = const AuthFormState(busy: true);
    try {
      await ref
          .read(authRepositoryProvider)
          .login(email: email, password: password);
      if (!ref.mounted) return false;
      ref.invalidate(currentProfileProvider);
      state = const AuthFormState();
      return true;
    } catch (error) {
      if (ref.mounted) state = AuthFormState(error: _message(error));
      return false;
    }
  }

  Future<RegistrationResult?> register({
    required String fullName,
    required String phone,
    required String email,
    required String password,
  }) async {
    if (state.busy) return null;
    state = const AuthFormState(busy: true);
    try {
      final result = await ref
          .read(authRepositoryProvider)
          .register(
            fullName: fullName,
            phone: phone,
            email: email,
            password: password,
          );
      if (!ref.mounted) return null;
      ref.invalidate(currentProfileProvider);
      state = AuthFormState(
        notice: result.needsEmailConfirmation
            ? 'Vui lòng kiểm tra email và mở liên kết xác nhận, sau đó đăng nhập.'
            : 'Đã tạo tài khoản.',
      );
      return result;
    } catch (error) {
      if (ref.mounted) state = AuthFormState(error: _message(error));
      return null;
    }
  }

  Future<bool> logout() async {
    if (state.busy) return false;
    state = const AuthFormState(busy: true);
    try {
      await ref.read(authRepositoryProvider).logout();
      if (!ref.mounted) return false;
      ref.invalidate(currentProfileProvider);
      state = const AuthFormState();
      return true;
    } catch (error) {
      if (ref.mounted) state = AuthFormState(error: _message(error));
      return false;
    }
  }

  String _message(Object error) => error is AuthenticationFailure
      ? error.message
      : 'Không thể hoàn tất thao tác. Vui lòng thử lại.';
}
