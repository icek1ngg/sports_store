import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../data/repositories/supabase_chat_repository.dart';
import '../../domain/models/chat_models.dart';
import '../../domain/repositories/chat_repository.dart';

final chatSessionProvider = StreamProvider.autoDispose<String?>((ref) async* {
  final client = ref.watch(supabaseClientProvider);
  yield client.auth.currentSession?.accessToken;
  yield* client.auth.onAuthStateChange.map(
    (event) => event.session?.accessToken,
  );
});
final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => SupabaseChatRepository(ref.watch(supabaseClientProvider)),
);
final chatInboxProvider =
    AsyncNotifierProvider.autoDispose<
      ChatInboxViewModel,
      List<ChatConversation>
    >(ChatInboxViewModel.new, retry: (_, _) => null);

class ChatInboxViewModel extends AsyncNotifier<List<ChatConversation>> {
  @override
  Future<List<ChatConversation>> build() async {
    final token = await ref.watch(chatSessionProvider.future);
    if (token == null) {
      throw const ChatFailure('Vui lòng đăng nhập để xem hội thoại.');
    }
    return ref.watch(chatRepositoryProvider).getConversations();
  }

  Future<String> startCustomerConversation() async {
    final client = ref.read(supabaseClientProvider);
    final session = client.auth.currentSession;
    final id = await ref
        .read(chatRepositoryProvider)
        .ensureCustomerConversation();
    if (!ref.mounted || !identical(client.auth.currentSession, session)) {
      throw const ChatFailure('Phiên hội thoại đã kết thúc.');
    }
    ref.invalidateSelf();
    return id;
  }
}

final chatThreadProvider = AsyncNotifierProvider.autoDispose
    .family<ChatThreadViewModel, ChatThreadState, String>(
      ChatThreadViewModel.new,
      retry: (_, _) => null,
    );

class ChatThreadState {
  const ChatThreadState({
    required this.page,
    this.sending = false,
    this.loadingOlder = false,
    this.error,
  });
  final ChatMessagePage page;
  final bool sending;
  final bool loadingOlder;
  final String? error;
}

class ChatThreadViewModel extends AsyncNotifier<ChatThreadState> {
  ChatThreadViewModel(this.conversationId);
  final String conversationId;
  String? _pendingId;
  String? _pendingBody;
  String? _pendingOwner;
  int _epoch = 0;
  @override
  Future<ChatThreadState> build() async {
    _epoch++;
    final token = await ref.watch(chatSessionProvider.future);
    if (token == null) {
      throw const ChatFailure('Vui lòng đăng nhập để xem hội thoại.');
    }
    final owner = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (_pendingOwner != owner) {
      _pendingId = null;
      _pendingBody = null;
      _pendingOwner = owner;
    }
    final page = await ref
        .watch(chatRepositoryProvider)
        .getMessages(conversationId);
    return ChatThreadState(page: page);
  }

  Future<bool> send(String body) async {
    final current = state.asData?.value;
    if (current == null || current.sending || current.loadingOlder) {
      return false;
    }
    if (body.trim().isEmpty || body.length > 4000) return false;
    final epoch = _epoch;
    final session = ref.read(supabaseClientProvider).auth.currentSession;
    bool isCurrent() =>
        ref.mounted &&
        _epoch == epoch &&
        identical(
          ref.read(supabaseClientProvider).auth.currentSession,
          session,
        );
    if (_pendingBody != body.trim()) {
      _pendingId = _uuid();
      _pendingBody = body.trim();
    }
    state = AsyncData(ChatThreadState(page: current.page, sending: true));
    try {
      final message = await ref
          .read(chatRepositoryProvider)
          .sendMessage(conversationId, _pendingBody!, _pendingId!);
      if (!isCurrent()) return false;
      _pendingId = null;
      _pendingBody = null;
      final messages =
          [...current.page.messages.where((m) => m.id != message.id), message]
            ..sort((a, b) {
              final order = a.createdAt.compareTo(b.createdAt);
              return order == 0 ? a.id.compareTo(b.id) : order;
            });
      state = AsyncData(
        ChatThreadState(
          page: ChatMessagePage(
            messages: messages,
            hasMore: current.page.hasMore,
          ),
        ),
      );
      ref.invalidate(chatInboxProvider);
      return true;
    } catch (error) {
      if (isCurrent()) {
        state = AsyncData(
          ChatThreadState(page: current.page, error: chatErrorMessage(error)),
        );
      }
      return false;
    }
  }

  Future<void> loadOlder() async {
    final current = state.asData?.value;
    if (current == null ||
        current.sending ||
        current.loadingOlder ||
        !current.page.hasMore ||
        current.page.messages.isEmpty) {
      return;
    }
    final epoch = _epoch;
    final session = ref.read(supabaseClientProvider).auth.currentSession;
    bool isCurrent() =>
        ref.mounted &&
        _epoch == epoch &&
        identical(
          ref.read(supabaseClientProvider).auth.currentSession,
          session,
        );
    state = AsyncData(ChatThreadState(page: current.page, loadingOlder: true));
    try {
      final page = await ref
          .read(chatRepositoryProvider)
          .getMessages(
            conversationId,
            beforeMessageId: current.page.messages.first.id,
          );
      if (!isCurrent()) return;
      final byId = {
        for (final m in [...page.messages, ...current.page.messages]) m.id: m,
      };
      state = AsyncData(
        ChatThreadState(
          page: ChatMessagePage(
            messages: byId.values.toList(),
            hasMore: page.hasMore,
          ),
        ),
      );
    } catch (error) {
      if (isCurrent()) {
        state = AsyncData(
          ChatThreadState(page: current.page, error: chatErrorMessage(error)),
        );
      }
    }
  }
}

String chatErrorMessage(Object error) => error is ChatFailure
    ? error.message
    : 'Không thể tải hoặc lưu hội thoại. Vui lòng thử lại.';
String _uuid() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
