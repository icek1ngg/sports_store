import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/notifications/data/repositories/supabase_notification_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../fixtures/order_notification_fixtures.dart';

export 'dart:async' show Completer, TimeoutException;
export 'dart:convert';

export 'package:http/http.dart' show Request, Response;
export 'package:sports_store/core/errors/app_failure.dart';
export 'package:sports_store/core/state/session_scope.dart';
export 'package:sports_store/features/notifications/domain/models/notification_query.dart';
export 'package:supabase_flutter/supabase_flutter.dart';

export '../../../fixtures/order_notification_fixtures.dart';

const otherRecipient = '10000000-0000-4000-8000-000000000099';

Map<String, Object?> inboxRow(
  int suffix, {
  String? recipient,
  String? readAt,
}) => {
  ...fixtureNotificationJson(),
  'id': '50000000-0000-4000-8000-${suffix.toString().padLeft(12, '0')}',
  'recipient_id': recipient ?? fixtureCustomerId,
  'created_at': '2026-10-27T01:00:00Z',
  'read_at': readAt,
};

String encodeCursor(Map<String, Object?> values) =>
    base64Url.encode(utf8.encode(jsonEncode(values))).replaceAll('=', '');

Map<String, Object?> cursorValues() => {
  'v': 1,
  'user_id': fixtureCustomerId,
  'filter': 'all',
  'limit': 2,
  'last_created_at': '2026-10-27T01:00:00Z',
  'last_id': inboxRow(2)['id'],
};

/// SDK/HTTP harness only; does not import or implement the app Auth feature.
class NotificationSupabaseHarness {
  NotificationSupabaseHarness() {
    client = SupabaseClient(
      'https://notifications-test.invalid',
      'sb_publishable_test-only',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        final response = await handle(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          request: request,
          headers: {
            ...response.headers,
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }),
    );
    repository = SupabaseNotificationRepository(
      client: client,
      readSession: () => scope,
    );
  }

  late final SupabaseClient client;
  late final SupabaseNotificationRepository repository;
  SessionScope scope = const SessionScope.unresolved();
  final requests = <http.Request>[];
  Future<http.Response> Function(http.Request) handle = (_) async =>
      http.Response('[]', 200);

  Future<void> supplySession({
    String userId = fixtureCustomerId,
    String role = 'customer',
    int generation = 1,
    int tokenVersion = 0,
  }) async {
    String part(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token = [
      part({'alg': 'HS256', 'typ': 'JWT'}),
      part({
        'sub': userId,
        'role': 'authenticated',
        'exp':
            DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
        'version': tokenVersion,
      }),
      part('test-only-signature'),
    ].join('.');
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': token,
        'refresh_token': 'test-only-refresh',
        'token_type': 'bearer',
        'user': {
          'id': userId,
          'aud': 'authenticated',
          'app_metadata': <String, Object?>{},
          'user_metadata': <String, Object?>{},
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
    scope = SessionScope(userId: userId, role: role, generation: generation);
  }

  http.Response rows(Object value) => http.Response.bytes(
    utf8.encode(jsonEncode(value)),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Future<void> dispose() => client.dispose();
}
