import '../models/chat_models.dart';

abstract interface class ChatRepository {
  Future<List<ChatConversation>> getConversations();
  Future<String> ensureCustomerConversation();
  Future<ChatMessagePage> getMessages(
    String conversationId, {
    String? beforeMessageId,
  });
  Future<ChatMessage> sendMessage(
    String conversationId,
    String body,
    String clientMessageId,
  );
}
