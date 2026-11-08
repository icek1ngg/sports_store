import '../../demo/data/local_demo_store.dart';
import '../../../../core/state/session_scope.dart';
import '../../../../features/chat/domain/models/chat_models.dart';
import '../../../../features/chat/domain/repositories/chat_repository.dart';

/// Shared local conversations. Every operation checks the current role/owner.
/// No SDK client or transport is constructed by this adapter.
class LocalChatRepository implements ChatRepository {
  LocalChatRepository(this.session) {
    reset();
  }

  void reset() {
    _threads.clear();
    _sequence = 10;
    _seed(LocalDemoStore.customerAId, 'Nguyễn Minh Anh', 1);
    _seed(LocalDemoStore.customerCId, 'Trần Thu Chi', 2);
  }

  final SessionScope Function() session;
  final _threads = <String, _Thread>{};
  int _sequence = 10;
  DateTime get _now =>
      DateTime.utc(2026, 11, 8, 8).add(Duration(seconds: _sequence++));

  void _seed(String customer, String name, int number) {
    final id = '70000000-0000-4000-8000-${number.toString().padLeft(12, '0')}';
    final thread = _Thread(id, customer, name);
    thread.messages.add(
      ChatMessage(
        id: '71000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
        conversationId: id,
        senderId: customer,
        body: 'Chào cửa hàng, tôi cần tư vấn sản phẩm thể thao.',
        clientMessageId: 'seed-$number',
        createdAt: _now,
      ),
    );
    _threads[id] = thread;
  }

  SessionScope _identity() {
    final scope = session();
    if (scope.userId == null || !{'customer', 'manager'}.contains(scope.role)) {
      throw const ChatFailure(
        'Tài khoản không có quyền trò chuyện.',
        accessDenied: true,
      );
    }
    return scope;
  }

  _Thread _access(String id, SessionScope scope) {
    final thread = _threads[id];
    if (thread == null ||
        (scope.role != 'manager' && thread.customerId != scope.userId)) {
      throw const ChatFailure(
        'Không có quyền đọc hội thoại.',
        accessDenied: true,
      );
    }
    return thread;
  }

  @override
  Future<List<ChatConversation>> getConversations() async {
    final scope = _identity();
    return [
      for (final thread in _threads.values)
        if (scope.role == 'manager' || thread.customerId == scope.userId)
          ChatConversation(
            id: thread.id,
            customerId: thread.customerId,
            customerName: thread.name,
            lastMessage: thread.messages.lastOrNull?.body,
            lastMessageAt: thread.messages.lastOrNull?.createdAt,
            lastSenderId: thread.messages.lastOrNull?.senderId,
            unreadCount: thread.messages
                .where(
                  (m) =>
                      m.senderId != scope.userId &&
                      (thread.read[scope.userId] == null ||
                          m.createdAt.isAfter(thread.read[scope.userId]!)),
                )
                .length,
          ),
    ];
  }

  @override
  Future<String> ensureCustomerConversation() async {
    final scope = _identity();
    if (scope.role != 'customer') {
      throw const ChatFailure(
        'Chỉ khách hàng mở hội thoại.',
        accessDenied: true,
      );
    }
    final existing = _threads.values.where((t) => t.customerId == scope.userId);
    if (existing.isNotEmpty) return existing.first.id;
    final number = _sequence++;
    final id = '70000000-0000-4000-8000-${number.toString().padLeft(12, '0')}';
    _threads[id] = _Thread(id, scope.userId!, 'Khách hàng');
    return id;
  }

  @override
  Future<ChatMessagePage> getMessages(
    String conversationId, {
    String? beforeMessageId,
  }) async {
    final scope = _identity();
    final thread = _access(conversationId, scope);
    var end = thread.messages.length;
    if (beforeMessageId != null) {
      end = thread.messages.indexWhere((m) => m.id == beforeMessageId);
      if (end < 0) throw const ChatFailure('Con trỏ hội thoại không hợp lệ.');
    } else {
      thread.read[scope.userId!] =
          thread.messages.lastOrNull?.createdAt ?? _now;
    }
    final start = (end - 30).clamp(0, end);
    return ChatMessagePage(
      messages: thread.messages.sublist(start, end),
      hasMore: start > 0,
    );
  }

  @override
  Future<ChatActivity> getActivity(String conversationId) async {
    final thread = _access(conversationId, _identity());
    final last = thread.messages.lastOrNull;
    return ChatActivity(
      conversationId: thread.id,
      customerId: thread.customerId,
      readAtByUser: Map.unmodifiable(thread.read),
      latestMessageId: last?.id,
      latestMessageAt: last?.createdAt,
      latestSenderId: last?.senderId,
    );
  }

  @override
  Future<ChatMessage> sendMessage(
    String conversationId,
    String body,
    String clientMessageId,
  ) async {
    final scope = _identity();
    final thread = _access(conversationId, scope);
    final normalized = body.trim();
    if (normalized.isEmpty ||
        normalized.length > 4000 ||
        clientMessageId.isEmpty) {
      throw const ChatFailure('Nội dung tin nhắn không hợp lệ.');
    }
    final prior = thread.messages.where(
      (m) => m.senderId == scope.userId && m.clientMessageId == clientMessageId,
    );
    if (prior.isNotEmpty) {
      if (prior.first.body != normalized) {
        throw const ChatFailure('Mã yêu cầu đã có nội dung khác.');
      }
      return prior.first;
    }
    final number = _sequence++;
    final message = ChatMessage(
      id: '71000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
      conversationId: conversationId,
      senderId: scope.userId!,
      body: normalized,
      clientMessageId: clientMessageId,
      createdAt: _now,
    );
    thread.messages.add(message);
    return message;
  }
}

class _Thread {
  _Thread(this.id, this.customerId, this.name);
  final String id;
  final String customerId;
  final String name;
  final messages = <ChatMessage>[];
  final read = <String, DateTime>{};
}
