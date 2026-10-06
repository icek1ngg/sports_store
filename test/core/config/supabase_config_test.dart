import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/config/supabase_config.dart';

void main() {
  const validUrl = 'https://bqoyfytmrtvjwrpshuhh.supabase.co';

  group('SupabaseConfig.validate', () {
    test('accepts a modern publishable key', () {
      const config = SupabaseConfig(
        url: validUrl,
        publishableKey: 'sb_publishable_test-key',
      );

      expect(config.validate, returnsNormally);
    });

    test('rejects missing URL and key without exposing values', () {
      const config = SupabaseConfig(url: '', publishableKey: '');

      expect(
        () => config.validate(),
        throwsA(
          predicate(
            (Object error) =>
                error is ArgumentError &&
                !error.toString().contains('sb_publishable'),
          ),
        ),
      );
    });

    test('rejects a missing key when the URL is valid', () {
      const config = SupabaseConfig(url: validUrl, publishableKey: '');

      expect(() => config.validate(), throwsA(isA<ArgumentError>()));
    });

    test('rejects malformed and non-HTTPS URLs', () {
      for (final url in ['https://', 'http://example.supabase.co']) {
        final config = SupabaseConfig(
          url: url,
          publishableKey: 'sb_publishable_test-key',
        );

        expect(() => config.validate(), throwsA(isA<ArgumentError>()));
      }
    });

    test('rejects surrounding whitespace in URL or key', () {
      const key = 'sb_publishable_test-key';

      expect(
        () => const SupabaseConfig(
          url: ' https://bqoyfytmrtvjwrpshuhh.supabase.co',
          publishableKey: key,
        ).validate(),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => const SupabaseConfig(
          url: validUrl,
          publishableKey: 'sb_publishable_test-key ',
        ).validate(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects secret and service-role keys', () {
      for (final key in [
        'sb_secret_test-key',
        'service_role_test-key',
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.c2lnbmF0dXJl',
      ]) {
        final config = SupabaseConfig(url: validUrl, publishableKey: key);

        expect(() => config.validate(), throwsA(isA<ArgumentError>()));
      }
    });

    test('accepts a legacy JWT whose role is anon', () {
      const anonJwt =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiJ9.c2lnbmF0dXJl';
      const config = SupabaseConfig(url: validUrl, publishableKey: anonJwt);

      expect(config.validate, returnsNormally);
    });
  });
}
