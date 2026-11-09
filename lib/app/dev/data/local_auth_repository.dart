import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../demo/data/local_demo_store.dart';
import '../../../../features/auth/domain/repositories/auth_repository.dart';
import '../../../../features/auth/domain/models/app_profile.dart';

/// Device-only identities. This adapter never creates a Supabase session.
class LocalAuthRepository extends ChangeNotifier implements AuthRepository {
  LocalAuthRepository(this.store) {
    store.suspendSession();
  }
  final LocalDemoStore store;
  final _changes = StreamController<AuthSession>.broadcast(sync: true);
  AuthSession _session = const AuthSession();
  int epoch = 0;
  final _accounts = <String, (DemoAccount, String, String)>{
    'customer@local.test': (
      DemoAccount.customerA,
      'sports123',
      'Nguyễn Minh Anh',
    ),
    'manager@local.test': (
      DemoAccount.managerB,
      'sports123',
      'Quản lý cửa hàng',
    ),
    'shipper@local.test': (
      DemoAccount.shipper,
      'sports123',
      'Nhân viên giao hàng',
    ),
    'customer.c@local.test': (
      DemoAccount.customerC,
      'sports123',
      'Trần Thu Chi',
    ),
  };
  String? _email;
  final _registeredIds = <String, String>{};
  @override
  AuthSession get currentSession => _session;
  @override
  Stream<AuthSession> watchSession() async* {
    yield _session;
    yield* _changes.stream;
  }

  @override
  Future<AppProfile?> getCurrentProfile() async {
    if (!_session.signedIn) return null;
    return AppProfile(
      id: store.session.userId!,
      role: AppRole.values.byName(store.session.role!),
      fullName: _accounts[_email]?.$3,
      phone: '0901234567',
    );
  }

  @override
  Future<void> login({required String email, required String password}) async {
    final account = _accounts[email.trim().toLowerCase()];
    if (account == null || account.$2 != password) {
      throw const AuthenticationFailure(
        'Email hoặc mật khẩu tài khoản local không đúng.',
      );
    }
    final registeredId = _registeredIds[email.trim().toLowerCase()];
    if (registeredId != null) {
      store.switchLocalCustomer(registeredId);
    } else {
      store.switchAccount(account.$1);
    }
    _email = email.trim().toLowerCase();
    epoch++;
    _session = AuthSession(
      userId: store.session.userId,
      accessToken: 'local-session-$epoch',
    );
    _changes.add(_session);
    // Let the existing Auth ViewModel finish before its provider is disposed.
    scheduleMicrotask(notifyListeners);
  }

  @override
  Future<void> loginWithGoogle() async {
    throw const AuthenticationFailure(
      'Đăng nhập Google chỉ khả dụng ở bản kết nối Supabase.',
    );
  }

  @override
  Future<void> logout() async {
    store.suspendSession();
    _email = null;
    epoch++;
    _session = const AuthSession();
    _changes.add(_session);
    scheduleMicrotask(notifyListeners);
  }

  @override
  Future<RegistrationResult> register({
    required String fullName,
    required String phone,
    required String email,
    required String password,
  }) async {
    final address = email.trim().toLowerCase();
    if (_accounts.containsKey(address)) {
      throw const AuthenticationFailure(
        'Email đã được sử dụng trên thiết bị này.',
      );
    }
    // A new local customer has its own empty namespace, never C's private data.
    _registeredIds[address] = const Uuid().v4();
    _accounts[address] = (DemoAccount.customerC, password, fullName.trim());
    return const RegistrationResult(needsEmailConfirmation: false);
  }

  @override
  void dispose() {
    unawaited(_changes.close());
    super.dispose();
  }
}
