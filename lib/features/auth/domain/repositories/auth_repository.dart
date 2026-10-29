import '../models/app_profile.dart';

abstract interface class AuthRepository {
  AuthSession get currentSession;
  Stream<AuthSession> watchSession();
  Future<AppProfile?> getCurrentProfile();
  Future<void> login({required String email, required String password});
  Future<RegistrationResult> register({
    required String fullName,
    required String phone,
    required String email,
    required String password,
  });
  Future<void> logout();
}
