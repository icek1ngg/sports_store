import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/wire_parsing.dart';
import '../../domain/models/chat_models.dart';
import '../../domain/repositories/chat_repository.dart';

class SupabaseChatRepository implements ChatRepository {
  SupabaseChatRepository(this.client);
  final SupabaseClient client;

  Future<Object?> _rpc(String name, [Map<String, dynamic>? params]) async {
    final session = client.auth.currentSession;
    if (session == null || session.isExpired) {
      throw const ChatFailure(
        'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
      );
    }
    try {
      final result = await client
          .rpc(name, params: params)
          .setHeader('Authorization', 'Bearer ${session.accessToken}')
          .retry(enabled: false, requestTimeout: const Duration(seconds: 15));
      if (!identical(client.auth.currentSession, session)) {
        throw const ChatFailure('Tài khoản đã thay đổi. Vui lòng tải lại.');
      }
      return result;
    } on ChatFailure {
      rethrow;
    } on PostgrestException catch (e) {
      if (e.code == '42501' || e.code == 'P0002') {
        throw const ChatFailure('Bạn không có quyền truy cập hội thoại này.');
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
      createdAt: DateTime.parse(requiredString(row, 'created_at')).toUtc(),
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
