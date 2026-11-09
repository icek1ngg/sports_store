import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/auth/data/oauth_sign_in_callback.dart';

void main() {
  test('OAuth query/fragment failures map to a safe localized notice', () {
    for (final suffix in [
      '#error=access_denied&error_description=private-provider-diagnostic',
      '?error=server_error&error_code=unexpected_failure',
    ]) {
      final notice = OAuthSignInCallback.errorMessage(
        Uri.parse('https://example.test/$suffix'),
      );
      expect(notice, 'Đăng nhập Google chưa hoàn tất. Vui lòng thử lại.');
      expect(notice, isNot(contains('private-provider-diagnostic')));
    }
  });

  test('successful OAuth and email/other routes are not OAuth failures', () {
    for (final url in [
      'https://example.test/?code=oauth-code',
      'https://example.test/#access_token=token',
      'https://example.test/#error=access_denied&type=signup',
      'https://example.test/#error=access_denied&error_code=otp_expired',
      'https://example.test/auth/confirm-email?error=access_denied',
      'https://example.test/#/customer/products?error=ordinary-filter',
    ]) {
      expect(OAuthSignInCallback.errorMessage(Uri.parse(url)), isNull);
    }
  });
}
