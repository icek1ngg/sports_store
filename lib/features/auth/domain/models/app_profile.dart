enum AppRole { customer, manager, shipper }

class AppProfile {
  const AppProfile({
    required this.id,
    required this.role,
    this.fullName,
    this.phone,
  });

  final String id;
  final AppRole role;
  final String? fullName;
  final String? phone;
}

/// A session identity only. Authorization is always read from profiles.
class AuthSession {
  const AuthSession({this.userId, this.accessToken});

  final String? userId;
  final String? accessToken;
  bool get signedIn => userId != null && accessToken != null;
}

class RegistrationResult {
  const RegistrationResult({required this.needsEmailConfirmation});
  final bool needsEmailConfirmation;
}

class AuthenticationFailure implements Exception {
  const AuthenticationFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
