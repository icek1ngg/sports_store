import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models/email_confirmation_result.dart';

/// Supabase owns the code/token exchange. Capture the incoming URI before
/// initialize(), because the SDK removes auth parameters after success on web.
class EmailConfirmationCallback {
  static const path = '/auth/confirm-email';

  static Map<String, String> _parameters(Uri uri) {
    try {
      final fragment = uri.fragment.startsWith('/')
          ? Uri.parse(uri.fragment).queryParameters
          : Uri.splitQueryString(uri.fragment);
      return {...uri.queryParameters, ...fragment};
    } on FormatException {
      return {};
    }
  }

  static bool isCallback(Uri uri) {
    // Hash navigation can leave the callback pathname in the address bar.
    // Reloading a later app route must not reopen the confirmation result.
    if (uri.fragment.startsWith('/') &&
        Uri.tryParse(uri.fragment)?.path != path) {
      return false;
    }
    if (uri.path == path || Uri.tryParse(uri.fragment)?.path == path) {
      return true;
    }
    if (!const {'', '/', '/login', '/register'}.contains(uri.path)) {
      return false;
    }
    final parameters = _parameters(uri);
    if (parameters['error_code'] == 'otp_expired') return true;
    if (!const {'signup', 'email'}.contains(parameters['type'])) return false;
    return const {
      'code',
      'access_token',
      'error',
      'error_code',
      'error_description',
    }.any(parameters.containsKey);
  }

  /// Call only after SDK initialization in a fresh process with session
  /// restoration disabled. A URL flag alone never proves confirmation.
  static EmailConfirmationResult resolveAfterSdkInitialization(
    Uri uri,
    Session? verifiedSession,
  ) {
    final parameters = _parameters(uri);
    final fragmentPath = Uri.tryParse(uri.fragment)?.path;
    final hasEmailConfirmationPath = uri.path == path || fragmentPath == path;
    final hasEmailConfirmationType = const {
      'signup',
      'email',
    }.contains(parameters['type']);
    if (!hasEmailConfirmationPath &&
        !hasEmailConfirmationType &&
        parameters['error_code'] != 'otp_expired') {
      return EmailConfirmationResult.invalid;
    }
    if (parameters['error_code'] == 'otp_expired') {
      return EmailConfirmationResult.expired;
    }
    if (const {
      'error',
      'error_code',
      'error_description',
    }.any(parameters.containsKey)) {
      return EmailConfirmationResult.failed;
    }
    final type = parameters['type'];
    if (type != null && type != 'signup' && type != 'email') {
      return EmailConfirmationResult.invalid;
    }
    final hasCredentials =
        (parameters['code']?.isNotEmpty ?? false) ||
        (parameters['access_token']?.isNotEmpty ?? false);
    if (!hasCredentials) return EmailConfirmationResult.invalid;
    if (verifiedSession == null ||
        verifiedSession.isExpired ||
        verifiedSession.user.emailConfirmedAt == null) {
      return EmailConfirmationResult.failed;
    }
    return EmailConfirmationResult.success;
  }
}
