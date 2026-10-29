import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sports_store/features/chat/data/repositories/supabase_chat_repository.dart';
import 'package:sports_store/features/chat/domain/models/chat_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const userId = '10000000-0000-4000-8000-000000000001';
const otherId = '10000000-0000-4000-8000-000000000002';
const conversationId = '20000000-0000-4000-8000-000000000001';
const messageId = '30000000-0000-4000-8000-000000000001';
const clientId = '40000000-0000-4000-8000-000000000001';

Map<String, Object?> message({
  String sender = userId,
  String conversation = conversationId,
}) => {
  'id': messageId,
  'conversation_id': conversation,
  'sender_id': sender,
  'client_message_id': clientId,
  'body': 'Xin chào',
  'created_at': '2026-10-29T10:00:00Z',
};

class Harness {
  Harness() {
    client = SupabaseClient(
      'https://chat-test.invalid',
      'sb_publishable_test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        final response = await handler(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
    repository = SupabaseChatRepository(client);
  }
  late final SupabaseClient client;
  late final SupabaseChatRepository repository;
  final requests = <http.Request>[];
  Future<http.Response> Function(http.Request) handler = (_) async => json([]);
  static http.Response json(Object data, {int status = 200}) => http.Response(
    jsonEncode(data),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  Future<void> signIn([String id = userId]) async {
    String part(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token = [
      part({'alg': 'HS256', 'typ': 'JWT'}),
      part({
        'sub': id,
        'role': 'authenticated',
        'exp':
            DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
      }),
      part('test'),
    ].join('.');
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': token,
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'user': {
          'id': id,
          'aud': 'authenticated',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
  }
}

void main() {
  late Harness h;
  setUp(() => h = Harness());
  tearDown(() async => h.client.dispose());

  test('anonymous inbox fails without issuing an API call', () async {
    await expectLater(
      h.repository.getConversations(),
      throwsA(isA<ChatFailure>()),
    );
    expect(h.requests, isEmpty);
  });
  test('inbox reads canonical unread count and actual last sender', () async {
    await h.signIn();
    h.handler = (_) async => Harness.json([
      {
        'id': conversationId,
        'customer_id': userId,
        'customer_name': 'Khách hàng',
        'last_message': 'Xin chào',
        'last_message_at': '2026-10-29T10:00:00Z',
        'last_sender_id': userId,
        'unread_count': 3,
      },
    ]);
    final rows = await h.repository.getConversations();
    expect(rows.single.unreadCount, 3);
    expect(rows.single.needsManagerReply, isTrue);
    expect(h.requests.single.url.path, '/rest/v1/rpc/list_chat_conversations');
    expect(h.requests.single.headers['Authorization'], startsWith('Bearer '));
  });
  test('negative unread count is rejected', () async {
    await h.signIn();
    h.handler = (_) async => Harness.json([
      {'unread_count': -1},
    ]);
    await expectLater(
      h.repository.getConversations(),
      throwsA(isA<ChatFailure>()),
    );
  });
  test('customer support creation returns real conversation UUID', () async {
    await h.signIn();
    h.handler = (_) async => Harness.json({'id': conversationId});
    expect(await h.repository.ensureCustomerConversation(), conversationId);
    expect(
      h.requests.single.url.path,
      '/rest/v1/rpc/ensure_customer_conversation',
    );
  });
  test('messages cursor is sent and page envelope validated', () async {
    await h.signIn();
    h.handler = (_) async => Harness.json({
      'conversation_id': conversationId,
      'messages': [message()],
      'has_more': true,
    });
    final page = await h.repository.getMessages(
      conversationId,
      beforeMessageId: messageId,
    );
    expect(page.hasMore, isTrue);
    expect(page.messages.single.body, 'Xin chào');
    expect(jsonDecode(h.requests.single.body), {
      'p_conversation_id': conversationId,
      'p_before_message_id': messageId,
    });
  });
  test('messages belonging to a different conversation are rejected', () async {
    await h.signIn();
    h.handler = (_) async => Harness.json({
      'conversation_id': conversationId,
      'messages': [message(conversation: otherId)],
      'has_more': false,
    });
    await expectLater(
      h.repository.getMessages(conversationId),
      throwsA(isA<ChatFailure>()),
    );
  });
  test('send transmits trimmed body and stable idempotency key', () async {
    await h.signIn();
    h.handler = (_) async => Harness.json(message());
    final sent = await h.repository.sendMessage(
      conversationId,
      '  Xin chào  ',
      clientId,
    );
    expect(sent.id, messageId);
    expect(jsonDecode(h.requests.single.body), {
      'p_conversation_id': conversationId,
      'p_body': 'Xin chào',
      'p_client_message_id': clientId,
    });
  });
  test('send refuses a canonical ACK for another sender', () async {
    await h.signIn();
    h.handler = (_) async => Harness.json(message(sender: otherId));
    await expectLater(
      h.repository.sendMessage(conversationId, 'Xin chào', clientId),
      throwsA(isA<ChatFailure>()),
    );
  });
  test('blank or oversized message never reaches server', () async {
    await h.signIn();
    await expectLater(
      h.repository.sendMessage(conversationId, '  ', clientId),
      throwsA(isA<ChatFailure>()),
    );
    await expectLater(
      h.repository.sendMessage(conversationId, 'a' * 4001, clientId),
      throwsA(isA<ChatFailure>()),
    );
    expect(h.requests, isEmpty);
  });
  test('backend permission error is a failure with no fallback rows', () async {
    await h.signIn();
    h.handler = (_) async =>
        Harness.json({'code': '42501', 'message': 'denied'}, status: 403);
    await expectLater(
      h.repository.getConversations(),
      throwsA(isA<ChatFailure>()),
    );
  });
  test('response after account change is rejected', () async {
    await h.signIn();
    final gate = Completer<http.Response>();
    final started = Completer<void>();
    h.handler = (_) async {
      started.complete();
      return gate.future;
    };
    final pending = h.repository.getConversations();
    await started.future;
    await h.signIn(otherId);
    gate.complete(Harness.json([]));
    await expectLater(pending, throwsA(isA<ChatFailure>()));
  });
}
