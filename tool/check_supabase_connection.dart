import 'dart:convert';
import 'dart:io';

import 'package:sports_store/core/config/supabase_config.dart';

Future<void> main(List<String> args) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final file = File(args.isEmpty ? 'config/supabase.json' : args.single);
    final values =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final config = SupabaseConfig(
      url: values['SUPABASE_URL'] as String? ?? '',
      publishableKey: values['SUPABASE_PUBLISHABLE_KEY'] as String? ?? '',
    );
    config.validate();

    for (final path in [
      '/auth/v1/settings',
      '/rest/v1/__connection_probe__?select=*&limit=0',
    ]) {
      final request = await client
          .getUrl(Uri.parse(config.url).resolve(path))
          .timeout(const Duration(seconds: 15));
      request.headers.set('apikey', config.publishableKey);
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 15));
      final payload = jsonDecode(body);
      final authOk =
          path.startsWith('/auth/') &&
          response.statusCode == HttpStatus.ok &&
          payload is Map;
      // Public keys cannot read the OpenAPI root. A missing-table response
      // confirms the request reached PostgREST with an accepted client key.
      // limit=0 prevents reading any rows even if this probe table exists.
      final dataApiOk =
          path.startsWith('/rest/') &&
          ((response.statusCode == HttpStatus.notFound &&
                  payload is Map &&
                  payload['code'] == 'PGRST205') ||
              (response.statusCode == HttpStatus.ok &&
                  payload is List &&
                  payload.isEmpty));
      if (!authOk && !dataApiOk) {
        stderr.writeln(
          'Unexpected API response: $path HTTP ${response.statusCode}',
        );
        throw StateError('API check failed: $path HTTP ${response.statusCode}');
      }
      stdout.writeln('OK $path (HTTP ${response.statusCode})');
    }
  } catch (error) {
    // Do not print responses, API keys or user data.
    stderr.writeln('Supabase connection check failed (${error.runtimeType}).');
    exitCode = 1;
  } finally {
    client.close(force: true);
  }
}
