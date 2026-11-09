/// Classifies OAuth failures before the SDK consumes the initial browser URL.
/// Only a fixed localized message is exposed; provider diagnostics stay in URL.
class OAuthSignInCallback {
  static String? errorMessage(Uri uri) {
    if (!const {'', '/', '/login', '/register'}.contains(uri.path) ||
        uri.fragment.startsWith('/')) {
      return null;
    }
    final Map<String, String> parameters;
    try {
      parameters = {
        ...uri.queryParameters,
        ...Uri.splitQueryString(uri.fragment),
      };
    } on FormatException {
      return null;
    }
    if (parameters.containsKey('type') ||
        parameters['error_code'] == 'otp_expired' ||
        !const {
          'error',
          'error_code',
          'error_description',
        }.any(parameters.containsKey)) {
      return null;
    }
    return 'Đăng nhập Google chưa hoàn tất. Vui lòng thử lại.';
  }
}
