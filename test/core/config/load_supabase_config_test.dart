import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/config/load_supabase_config.dart';
import 'package:sports_store/core/config/supabase_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('plain launch loads valid bundled client configuration', () async {
    final config = await loadSupabaseConfig(hasEnvironmentOverride: false);
    expect(config.validate, returnsNormally);
    expect(config.url, startsWith('https://'));
  });

  test('explicit configuration wins over bundled defaults', () async {
    const override = SupabaseConfig(
      url: 'https://example.supabase.co',
      publishableKey: 'sb_publishable_test',
    );
    final config = await loadSupabaseConfig(
      environment: override,
      hasEnvironmentOverride: true,
    );
    expect(identical(config, override), isTrue);
  });

  test('partial explicit configuration does not fall back', () async {
    await expectLater(
      loadSupabaseConfig(
        environment: const SupabaseConfig(
          url: 'https://example.supabase.co',
          publishableKey: '',
        ),
        hasEnvironmentOverride: true,
      ),
      throwsArgumentError,
    );
  });
}
