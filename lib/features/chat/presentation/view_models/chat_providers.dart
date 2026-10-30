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
    this.refreshing = false,
    this.error,
  });
  final ChatMessagePage page;
  final bool sending;
  final bool loadingOlder;
  final bool refreshing;
  final String? error;
  bool get busy => sending || loadingOlder || refreshing;
}

class ChatThreadViewModel extends AsyncNotifier<ChatThreadState> {
  ChatThreadViewModel(this.conversationId);
  final String conversationId;
  String? _pendingId;
  String? _pendingBody;
  String? _pendingOwner;
  // Only a head read proves that all messages through this point were loaded.
  // A local send ACK may jump over unread messages from the other participant.
  ChatMessage? _contiguousHead;
  int _epoch = 0;
  @override
  Future<ChatThreadState> build() async {
    final epoch = ++_epoch;
    _contiguousHead = null;
    final token = await ref.watch(chatSessionProvider.future);
    if (token == null) {
      throw const ChatFailure('Vui lòng đăng nhập để xem hội thoại.');
    }
    final owner = ref.read(supabaseClientProvider).auth.currentUser?.id;
    final session = ref.read(supabaseClientProvider).auth.currentSession;
    if (_pendingOwner != owner) {
      _pendingId = null;
      _pendingBody = null;
      _pendingOwner = owner;
    }
    final page = await ref
        .watch(chatRepositoryProvider)
        .getMessages(conversationId);
    if (ref.mounted &&
        epoch == _epoch &&
        identical(
          ref.read(supabaseClientProvider).auth.currentSession,
          session,
        )) {
      _contiguousHead = page.messages.lastOrNull;
      // The head RPC has committed its read watermark. MH19 must fetch the
      // server's new unread count even when the user never sends a reply.
      ref.invalidate(chatInboxProvider);
    }
    return ChatThreadState(page: page);
  }

  /// Merge a fresh head into all loaded history. If more than one page arrived
  /// since the last read, walk backwards until the old tail is reached so the
  /// resulting list has no hidden gap between the two snapshots.
  Future<void> refreshLatest() async {
    final current = state.asData?.value;
    if (current == null || current.busy) return;
    final epoch = _epoch;
    final session = ref.read(supabaseClientProvider).auth.currentSession;
    bool isCurrent() =>
        ref.mounted &&
        _epoch == epoch &&
        identical(
          ref.read(supabaseClientProvider).auth.currentSession,
          session,
        );
    state = AsyncData(
      ChatThreadState(
        page: current.page,
        refreshing: true,
        error: current.error,
      ),
    );
    try {
      final repository = ref.read(chatRepositoryProvider);
      var page = await repository.getMessages(conversationId);
      if (!isCurrent()) return;
      ref.invalidate(chatInboxProvider);
      final head = page.messages.lastOrNull;
      final fresh = [...page.messages];
      if (current.page.messages.isNotEmpty) {
        final anchor = _contiguousHead;
        final cursors = <String>{};
        while (page.hasMore &&
            (anchor == null ||
                page.messages.isEmpty ||
                _compareMessages(page.messages.first, anchor) > 0)) {
          if (page.messages.isEmpty || !cursors.add(page.messages.first.id)) {
            throw const ChatFailure(
              'Không thể nối lịch sử hội thoại. Hãy thử lại.',
            );
          }
          page = await repository.getMessages(
            conversationId,
            beforeMessageId: page.messages.first.id,
          );
          if (!isCurrent()) return;
          fresh.addAll(page.messages);
        }
      }
      if (!isCurrent()) return;
      _contiguousHead = head;
      state = AsyncData(
        ChatThreadState(
          page: ChatMessagePage(
            messages: _mergeMessages(current.page.messages, fresh),
            // The cursor is still the oldest message already loaded, rather
            // than the oldest message in the fresh head response.
            hasMore: current.page.messages.isEmpty
                ? page.hasMore
                : current.page.hasMore,
          ),
          error: _pendingId == null ? null : current.error,
        ),
      );
    } catch (error) {
      if (isCurrent()) {
        _handleActionError(current, error);
      }
    }
  }

  Future<bool> send(String body) async {
    final current = state.asData?.value;
    if (current == null || current.busy) {
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
      final messages = _mergeMessages(current.page.messages, [message]);
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
        _handleActionError(current, error);
      }
      return false;
    }
  }

  Future<void> loadOlder() async {
    final current = state.asData?.value;
    if (current == null ||
        current.busy ||
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
      state = AsyncData(
        ChatThreadState(
          page: ChatMessagePage(
            messages: _mergeMessages(current.page.messages, page.messages),
            hasMore: page.hasMore,
          ),
        ),
      );
    } catch (error) {
      if (isCurrent()) {
        _handleActionError(current, error);
      }
    }
  }

  void _handleActionError(ChatThreadState current, Object error) {
    if (error is ChatFailure && error.accessDenied) {
      // A transport failure can preserve history; a permission failure must
      // remove it immediately, rather than showing a now-inaccessible thread.
      state = AsyncError(error, StackTrace.current);
    } else {
      state = AsyncData(
        ChatThreadState(page: current.page, error: chatErrorMessage(error)),
      );
    }
  }
}

int _compareMessages(ChatMessage a, ChatMessage b) {
  final order = a.createdAt.compareTo(b.createdAt);
  return order == 0 ? a.id.compareTo(b.id) : order;
}

List<ChatMessage> _mergeMessages(
  List<ChatMessage> existing,
  List<ChatMessage> incoming,
) => ({
  for (final message in [...existing, ...incoming]) message.id: message,
}.values.toList()..sort(_compareMessages));

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
