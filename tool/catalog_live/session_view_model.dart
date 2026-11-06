import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';

final liveCatalogSessionViewModelProvider =
    AsyncNotifierProvider<LiveCatalogSessionViewModel, void>(
      LiveCatalogSessionViewModel.new,
    );

class LiveCatalogSessionViewModel extends AsyncNotifier<void> {
  @override
  void build() {}

  Future<bool> signIn(String email, String password) async {
    if (state.isLoading) return false;
    state = const AsyncLoading();
    final client = ref.read(supabaseClientProvider);
    final access = ref.read(operationalReadAccessProvider);
    try {
      await client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      access.refreshSession();
      await access.run(roles: const {'customer'}, action: (_) async {});
      if (!ref.mounted) return false;
      state = const AsyncData(null);
      return true;
    } catch (error, stack) {
      // This tool admits customer accounts only; never retain a failed login
      // as an authorized customer or print raw Auth/SQL responses.
      try {
        await client.auth.signOut(scope: SignOutScope.local);
      } catch (_) {
        // Authorization still fails closed through the router and repository.
      }
      access.refreshSession();
      if (ref.mounted) state = AsyncError(_message(error), stack);
      return false;
    }
  }

  Future<void> signOut() async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    try {
      await ref
          .read(supabaseClientProvider)
          .auth
          .signOut(scope: SignOutScope.local);
      ref.read(operationalReadAccessProvider).refreshSession();
      if (ref.mounted) state = const AsyncData(null);
    } catch (_, stack) {
      if (ref.mounted) {
        state = AsyncError('Chưa đăng xuất được. Vui lòng thử lại.', stack);
      }
    }
  }

  String _message(Object error) {
    if (error is OperationalFailure) {
      return error.code == OperationalFailureCode.permissionDenied
          ? 'Vui lòng sử dụng tài khoản khách hàng.'
          : error.message;
    }
    if (error is AuthException) {
      return switch (error.code) {
        'email_not_confirmed' => 'Địa chỉ thư điện tử chưa được xác nhận.',
        'invalid_credentials' || 'invalid_login_credentials' =>
          'Địa chỉ thư điện tử hoặc mật khẩu chưa đúng.',
        _ => 'Không đăng nhập được. Kiểm tra tài khoản và kết nối mạng.',
      };
    }
    return 'Không kết nối được máy chủ. Vui lòng thử lại.';
  }
}
