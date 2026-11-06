import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/wire_parsing.dart';
import '../../domain/models/chat_models.dart';
import '../../domain/repositories/chat_repository.dart';

class SupabaseChatRepository implements ChatRepository {
  SupabaseChatRepository(this.client);
  final SupabaseClient client;

  Future<Object?> _rpc(String name, [Map<String, dynamic>? params]) => _execute(
    (token) => client
        .rpc(name, params: params)
        .setHeader('Authorization', 'Bearer $token')
        .retry(enabled: false, requestTimeout: const Duration(seconds: 15)),
  );

  /// Runs one request with the current session token and maps every failure
  /// to a safe [ChatFailure]; a response that arrives after an account
  /// change is discarded.
  Future<Object?> _execute(
    Future<Object?> Function(String accessToken) request,
  ) async {
    final session = client.auth.currentSession;
    if (session == null || session.isExpired) {
      throw const ChatFailure(
        'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
        accessDenied: true,
      );
    }
    try {
      final result = await request(session.accessToken);
      if (!identical(client.auth.currentSession, session)) {
        throw const ChatFailure(
          'Tài khoản đã thay đổi. Vui lòng tải lại.',
          accessDenied: true,
        );
      }
      return result;
    } on ChatFailure {
      rethrow;
    } on PostgrestException catch (e) {
      if (e.code == '42501' || e.code == 'P0002') {
        throw const ChatFailure(
          'Bạn không có quyền truy cập hội thoại này.',
          accessDenied: true,
        );
      }
      if (e.code == 'PGRST202' || e.code == '42883') {
        throw const ChatFailure(
          'Chức năng hội thoại hiện chưa sẵn sàng. Vui lòng thử lại sau.',
        );
      }
      if (e.code == '22023' || e.code == '23505') {
        throw const ChatFailure('Nội dung hoặc mã gửi tin không hợp lệ.');
      }
      throw const ChatFailure(
        'Không thể tải hoặc lưu hội thoại. Vui lòng thử lại.',
      );
    } catch (_) {
      throw const ChatFailure('Không thể kết nối hội thoại. Vui lòng thử lại.');
    }
  }

  Map<String, Object?> _object(Object? value) {
    if (value is! Map) {
      throw const ChatFailure('Dữ liệu hội thoại không hợp lệ.');
    }
    return Map<String, Object?>.from(value);
  }

  ChatMessage _message(Object? value) {
    final row = _object(value);
    return ChatMessage(
      id: requiredUuid(row, 'id'),
      conversationId: requiredUuid(row, 'conversation_id'),
      senderId: requiredUuid(row, 'sender_id'),
      body: requiredString(row, 'body', nonBlank: true),
      clientMessageId: requiredUuid(row, 'client_message_id'),
      createdAt: requiredUtcTimestamp(row, 'created_at'),
    );
  }

  @override
  Future<List<ChatConversation>> getConversations() async {
    final result = await _rpc('list_chat_conversations');
    if (result is! List) {
      throw const ChatFailure('Dữ liệu hội thoại không hợp lệ.');
    }
    return result
        .map((value) {
          final row = _object(value);
          final unread = row['unread_count'];
          if (unread is! int || unread < 0) {
            throw const ChatFailure('Số tin chưa đọc không hợp lệ.');
          }
          return ChatConversation(
            id: requiredUuid(row, 'id'),
            customerId: requiredUuid(row, 'customer_id'),
            customerName: requiredString(row, 'customer_name'),
            lastMessage: nullableString(row, 'last_message'),
            lastMessageAt: row['last_message_at'] == null
                ? null
                : DateTime.parse(requiredString(row, 'last_message_at'))
                      .toUtc(),
            lastSenderId: row['last_sender_id'] == null
                ? null
                : requiredUuid(row, 'last_sender_id'),
            unreadCount: unread,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<String> ensureCustomerConversation() async {
    final result = await _rpc('ensure_customer_conversation');
    return requiredUuid(_object(result), 'id');
  }

  @override
  Future<ChatMessagePage> getMessages(
    String conversationId, {
    String? beforeMessageId,
  }) async {
    final row = _object(
      await _rpc('get_chat_messages', {
        'p_conversation_id': conversationId,
        'p_before_message_id': beforeMessageId,
      }),
    );
    if (row['conversation_id'] != conversationId ||
        row['messages'] is! List ||
        row['has_more'] is! bool) {
      throw const ChatFailure('Dữ liệu hội thoại không hợp lệ.');
    }
    final messages = (row['messages'] as List)
        .map(_message)
        .toList(growable: false);
    if (messages.any((m) => m.conversationId != conversationId)) {
      throw const ChatFailure('Dữ liệu hội thoại không khớp.');
    }
    return ChatMessagePage(
      messages: messages,
      hasMore: row['has_more'] as bool,
    );
  }

  @override
  Future<ChatActivity> getActivity(String conversationId) async {
    // Both reads are independent: run them together (one round trip).
    final conversationRead = _execute(
      (token) => client
          .from('conversations')
          .select('id,customer_id,read_at_by_user')
          .eq('id', conversationId)
          .setHeader('Authorization', 'Bearer $token')
          .maybeSingle()
          .timeout(const Duration(seconds: 15)),
    );
    final latestRead = _execute(
      (token) => client
          .from('messages')
          .select('id,sender_id,created_at')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .limit(1)
          .setHeader('Authorization', 'Bearer $token')
          .timeout(const Duration(seconds: 15)),
    );
    final [conversation, latest] = await Future.wait([
      conversationRead,
      latestRead,
    ]);
    if (conversation == null) {
      // RLS hides other customers' conversations and every shipper.
      throw const ChatFailure(
        'Bạn không có quyền truy cập hội thoại này.',
        accessDenied: true,
      );
    }
    final row = _object(conversation);
    if (row['id'] != conversationId) {
      throw const ChatFailure('Dữ liệu hội thoại không khớp.');
    }
    if (latest is! List) {
      throw const ChatFailure('Dữ liệu hội thoại không hợp lệ.');
    }
    final head = latest.isEmpty ? null : _object(latest.single);
    final rawReads = row['read_at_by_user'];
    final reads = <String, DateTime>{};
    if (rawReads is Map) {
      for (final entry in rawReads.entries) {
        final value = entry.value;
        if (entry.key is String && value is String) {
          reads[entry.key as String] = parseUtcTimestamp(
            value,
            path: 'read_at_by_user',
          );
        }
      }
    } else if (rawReads != null) {
      throw const ChatFailure('Dữ liệu đã đọc không hợp lệ.');
    }
    return ChatActivity(
      conversationId: conversationId,
      customerId: requiredUuid(row, 'customer_id'),
      readAtByUser: Map.unmodifiable(reads),
      latestMessageId: head == null ? null : requiredUuid(head, 'id'),
      latestSenderId: head == null ? null : requiredUuid(head, 'sender_id'),
      latestMessageAt: head == null
          ? null
          : requiredUtcTimestamp(head, 'created_at'),
    );
  }

  @override
  Future<ChatMessage> sendMessage(
    String conversationId,
    String body,
    String clientMessageId,
  ) async {
    if (body.trim().isEmpty || body.length > 4000) {
      throw const ChatFailure('Nhập tin nhắn từ 1 đến 4.000 ký tự.');
    }
    final senderId = client.auth.currentUser?.id;
    final message = _message(
      await _rpc('send_chat_message', {
        'p_conversation_id': conversationId,
        'p_body': body.trim(),
        'p_client_message_id': clientMessageId,
      }),
    );
    if (message.conversationId != conversationId ||
        message.senderId != senderId ||
        message.clientMessageId != clientMessageId ||
        message.body != body.trim()) {
      throw const ChatFailure(
        'Máy chủ chưa xác nhận đúng tin nhắn. Hãy thử lại.',
      );
    }
    return message;
  }
}
