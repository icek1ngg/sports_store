import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/auth/data/email_confirmation_callback.dart';
import 'package:sports_store/features/auth/domain/models/email_confirmation_result.dart';

void main() {
  test('detects query, implicit fragment and dedicated callback URLs', () {
    for (final url in [
      'http://localhost:57604/?code=test-code&type=signup',
      'http://localhost:57604/#access_token=test-token&type=signup',
      'http://localhost:57604/auth/confirm-email?code=test-code',
      'http://localhost:57604/#/auth/confirm-email',
    ]) {
      expect(EmailConfirmationCallback.isCallback(Uri.parse(url)), isTrue);
    }
  });

  test('OAuth PKCE code at the site root is not an email confirmation', () {
    final uri = Uri.parse('http://localhost:57604/?code=oauth-code');
    expect(EmailConfirmationCallback.isCallback(uri), isFalse);
    expect(
      EmailConfirmationCallback.resolveAfterSdkInitialization(uri, null),
      EmailConfirmationResult.invalid,
    );
  });

  test(
    'the expired link from the screenshot reports expiry rather than 404',
    () {
      final uri = Uri.parse(
        'http://localhost:57604/?error=access_denied&error_code=otp_expired'
        '&error_description=Email+link+is+invalid+or+has+expired'
        '#error=access_denied&error_code=otp_expired',
      );
      expect(EmailConfirmationCallback.isCallback(uri), isTrue);
      expect(
        EmailConfirmationCallback.resolveAfterSdkInitialization(uri, null),
        EmailConfirmationResult.expired,
      );
    },
  );

  test('a bare callback or a success query flag cannot prove confirmation', () {
    for (final url in [
      'http://localhost:57604/auth/confirm-email',
      'http://localhost:57604/auth/confirm-email?success=true',
    ]) {
      expect(
        EmailConfirmationCallback.resolveAfterSdkInitialization(
          Uri.parse(url),
          null,
        ),
        EmailConfirmationResult.invalid,
      );
    }
  });

  test(
    'tokens and codes without a verified SDK session cannot prove confirmation',
    () {
      for (final url in [
        'http://localhost:57604/?code=invalid&type=signup',
        'http://localhost:57604/#access_token=invalid&type=signup',
      ]) {
        expect(
          EmailConfirmationCallback.resolveAfterSdkInitialization(
            Uri.parse(url),
            null,
          ),
          EmailConfirmationResult.failed,
        );
      }
    },
  );

  test('recovery callbacks are not reported as signup confirmation', () {
    expect(
      EmailConfirmationCallback.resolveAfterSdkInitialization(
        Uri.parse('http://localhost:57604/#access_token=test&type=recovery'),
        null,
      ),
      EmailConfirmationResult.invalid,
    );
  });

  test('normal navigation including reload after continuing is preserved', () {
    for (final url in [
      'http://localhost:57604/',
      'http://localhost:57604/#/register',
      'http://localhost:57604/auth/confirm-email#/login',
      'http://localhost:57604/auth/confirm-email#/customer/products',
      'http://localhost:57604/?error=access_denied&error_code=otp_expired#/login',
    ]) {
      expect(EmailConfirmationCallback.isCallback(Uri.parse(url)), isFalse);
    }
  });
}
