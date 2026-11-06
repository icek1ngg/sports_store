// Test-only SDK transport/session fixtures. No real tokens or backend success.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const shipperA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const shipperB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

http.Response jsonResponse(
  http.Request request,
  Object? body, {
  int status = 200,
}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
  request: request,
);

Future<void> recoverFixtureSession(SupabaseClient client, String userId) async {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final jwt =
      '${encode({'alg': 'none'})}.${encode({'sub': userId, 'role': 'authenticated', 'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000})}.test_fixture_signature';
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': jwt,
      'refresh_token': 'test-fixture-refresh',
      'token_type': 'bearer',
      'user': {
        'id': userId,
        'aud': 'authenticated',
        'role': 'authenticated',
        // A client-editable claim must never authorize the repository.
        'user_metadata': {'role': 'manager'},
        'created_at': '2026-10-23T00:00:00Z',
      },
    }),
  );
  await Future<void>.delayed(Duration.zero);
}

Future<SupabaseClient> fixtureClient(
  Future<http.Response> Function(http.Request request) handler, {
  String? userId = shipperA,
}) async {
  final client = SupabaseClient(
    'https://test-fixture.invalid',
    'test-fixture-publishable',
    httpClient: MockClient(handler),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  if (userId != null) await recoverFixtureSession(client, userId);
  return client;
}
