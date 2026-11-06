// Anonymous probes never create accounts or business rows. Deployed RPCs must
// deny this caller; PGRST202 means the expected signature is missing.
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final config = jsonDecode(
      await File(args.isEmpty ? 'config/supabase.json' : args.single)
          .readAsString(),
    ) as Map<String, dynamic>;
    final base = Uri.parse(config['SUPABASE_URL'] as String);
    final probes = <String, Map<String, Object?>>{
      'list_chat_conversations': {},
      'ensure_customer_conversation': {},
      'get_chat_messages': {
        'p_conversation_id': null,
        'p_before_message_id': null,
      },
      'send_chat_message': {
        'p_conversation_id': null,
        'p_client_message_id': null,
        'p_body': null,
      },
      'save_managed_product': {
        'p_request_id': null,
        'p_product_id': null,
        'p_expected_updated_at': null,
        'p_name': null,
        'p_category_id': null,
        'p_description': null,
        'p_image_path': null,
        'p_is_active': null,
        'p_variants': null,
      },
    };
    for (final entry in probes.entries) {
      final request = await client.postUrl(
        base.resolve('/rest/v1/rpc/${entry.key}'),
      );
      request.headers.set(
        'apikey',
        config['SUPABASE_PUBLISHABLE_KEY'] as String,
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(entry.value));
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final result =
          jsonDecode(await response.transform(utf8.decoder).join()) as Map;
      final code = result['code'];
      if (code == '42501' &&
          (response.statusCode == 401 || response.statusCode == 403)) {
        stdout.writeln('OK ${entry.key}: deployed; anonymous access denied');
      } else {
        stderr.writeln(
          'FAIL ${entry.key}: HTTP ${response.statusCode}, code $code',
        );
        exitCode = 1;
      }
    }
  } catch (error) {
    stderr.writeln('Backend check failed (${error.runtimeType}).');
    exitCode = 1;
  } finally {
    client.close(force: true);
  }
}
