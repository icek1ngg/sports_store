class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.lastSenderId,
    required this.unreadCount,
  });
  final String id;
  final String customerId;
  final String customerName;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String? lastSenderId;
  final int unreadCount;
  bool get needsManagerReply => lastSenderId == customerId;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    required this.clientMessageId,
    required this.createdAt,
  });
  final String id;
  final String conversationId;
  final String senderId;
  final String body;
  final String clientMessageId;
  final DateTime createdAt;
}

class ChatMessagePage {
  const ChatMessagePage({required this.messages, required this.hasMore});
  final List<ChatMessage> messages;
  final bool hasMore;
}

class ChatFailure implements Exception {
  const ChatFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
