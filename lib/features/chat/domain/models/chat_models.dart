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
  const ChatFailure(this.message, {this.accessDenied = false});
  final String message;
  final bool accessDenied;
  @override
  String toString() => message;
}

/// Cheap, read-only freshness probe for an open thread (MH20). Reading it
/// never moves anyone's read marker; only loading the latest page does.
class ChatActivity {
  const ChatActivity({
    required this.conversationId,
    required this.customerId,
    required this.readAtByUser,
    this.latestMessageId,
    this.latestMessageAt,
    this.latestSenderId,
  });
  final String conversationId;
  final String customerId;
  final String? latestMessageId;
  final DateTime? latestMessageAt;
  final String? latestSenderId;

  /// Server read watermark per participant user id.
  final Map<String, DateTime> readAtByUser;

  /// Latest time the *other side* has read up to, seen from [viewerId]:
  /// a customer's messages are read by any manager; a manager's messages are
  /// read by the conversation's customer.
  DateTime? otherSideReadAt(String viewerId) {
    final others = viewerId == customerId
        ? readAtByUser.entries.where((e) => e.key != viewerId)
        : readAtByUser.entries.where((e) => e.key == customerId);
    DateTime? latest;
    for (final e in others) {
      if (latest == null || e.value.isAfter(latest)) latest = e.value;
    }
    return latest;
  }
}
