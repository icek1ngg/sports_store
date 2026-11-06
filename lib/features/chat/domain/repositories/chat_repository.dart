import '../models/chat_models.dart';

abstract interface class ChatRepository {
  Future<List<ChatConversation>> getConversations();
  Future<String> ensureCustomerConversation();
  Future<ChatMessagePage> getMessages(
    String conversationId, {
    String? beforeMessageId,
  });

  /// Read-only probe (latest message + read markers); never marks read.
  Future<ChatActivity> getActivity(String conversationId);
  Future<ChatMessage> sendMessage(
    String conversationId,
    String body,
    String clientMessageId,
  );
}
