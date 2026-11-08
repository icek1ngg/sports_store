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

/// Injectable identity and epoch. Live defaults preserve SDK session guards.
final chatViewerIdProvider = Provider<String? Function()>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return () => client.auth.currentUser?.id;
});
final chatEpochProvider = Provider<Object? Function()>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return () => client.auth.currentSession;
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
    final session = ref.read(chatEpochProvider)();
    final id = await ref
        .read(chatRepositoryProvider)
        .ensureCustomerConversation();
    if (!ref.mounted || !identical(ref.read(chatEpochProvider)(), session)) {
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
    this.othersReadAt,
    this.newBelow = false,
    this.connectionIssue,
  });
  final ChatMessagePage page;
  final bool sending;
  final bool loadingOlder;
  final bool refreshing;

  /// Last send/load action failure; the draft stays in the input.
  final String? error;

  /// Server read watermark of the other side ("Đã xem" for own messages).
  final DateTime? othersReadAt;

  /// New messages exist but the viewer is scrolled up: not loaded, not read.
  final bool newBelow;

  /// The background freshness probe failed; history stays and it retries.
  final String? connectionIssue;
  bool get busy => sending || loadingOlder || refreshing;

  /// Copies the background freshness fields onto a new action state.
  ChatThreadState carry(ChatThreadState from) => ChatThreadState(
    page: page,
    sending: sending,
    loadingOlder: loadingOlder,
    refreshing: refreshing,
    error: error,
    othersReadAt: from.othersReadAt,
    newBelow: newBelow || from.newBelow,
    connectionIssue: from.connectionIssue,
  );
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
    final owner = ref.read(chatViewerIdProvider)();
    final session = ref.read(chatEpochProvider)();
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
        identical(ref.read(chatEpochProvider)(), session)) {
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
    final session = ref.read(chatEpochProvider)();
    bool isCurrent() =>
        ref.mounted &&
        _epoch == epoch &&
        identical(ref.read(chatEpochProvider)(), session);
    state = AsyncData(
      ChatThreadState(
        page: current.page,
        refreshing: true,
        error: current.error,
      ).carry(current),
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
          othersReadAt: current.othersReadAt,
        ),
      );
    } catch (error) {
      if (isCurrent()) {
        _handleActionError(current, error);
      }
    }
  }

  bool _probing = false;

  /// Polling is allowed with a send error on screen (the draft is kept) and
  /// with a failed probe; only a missing snapshot or a running read stops it.
  bool get canPoll {
    final current = state.asData?.value;
    return current != null && !current.busy && !_probing;
  }

  /// Foreground freshness check (shared 3 s policy). It only reads the latest
  /// message id and read markers; the latest page — which records the read
  /// marker — is loaded only while the viewer is looking at the newest
  /// messages ([viewingLatest]). Otherwise a "new messages" hint is shown.
  Future<void> poll({required bool viewingLatest}) async {
    final current = state.asData?.value;
    if (current == null || current.busy || _probing) return;
    final epoch = _epoch;

    final session = ref.read(chatEpochProvider)();
    final viewer = ref.read(chatViewerIdProvider)();
    bool isCurrent() =>
        ref.mounted &&
        _epoch == epoch &&
        identical(ref.read(chatEpochProvider)(), session);
    _probing = true;
    try {
      final activity = await ref
          .read(chatRepositoryProvider)
          .getActivity(conversationId);
      if (!isCurrent()) return;
      final latest = state.asData?.value ?? current;
      final latestId = activity.latestMessageId;
      final hasNew =
          latestId != null &&
          latest.page.messages.every((m) => m.id != latestId);
      state = AsyncData(
        ChatThreadState(
          page: latest.page,
          sending: latest.sending,
          loadingOlder: latest.loadingOlder,
          refreshing: latest.refreshing,
          error: latest.error,
          othersReadAt: viewer == null
              ? null
              : activity.otherSideReadAt(viewer),
          newBelow: hasNew && !viewingLatest,
        ),
      );
      _probing = false;
      if (hasNew && viewingLatest) await refreshLatest();
    } catch (error) {
      if (!isCurrent()) return;
      final latest = state.asData?.value ?? current;
      if (error is ChatFailure && error.accessDenied) {
        state = AsyncError(error, StackTrace.current);
      } else {
        state = AsyncData(
          ChatThreadState(
            page: latest.page,
            error: latest.error,
            othersReadAt: latest.othersReadAt,
            newBelow: latest.newBelow,
            connectionIssue: 'Mất kết nối, đang thử cập nhật lại. Lịch sử đã tải vẫn được giữ.',
          ),
        );
      }
    } finally {
      _probing = false;
    }
  }

  /// The viewer scrolled back to the newest messages: load (and read) them.
  Future<void> showNewMessages() async {
    final current = state.asData?.value;
    if (current == null || !current.newBelow) return;
    await refreshLatest();
  }

  Future<bool> send(String body) async {
    final current = state.asData?.value;
    if (current == null || current.busy) {
      return false;
    }
    if (body.trim().isEmpty || body.length > 4000) return false;
    final epoch = _epoch;
    final session = ref.read(chatEpochProvider)();
    bool isCurrent() =>
        ref.mounted &&
        _epoch == epoch &&
        identical(ref.read(chatEpochProvider)(), session);
    if (_pendingBody != body.trim()) {
      _pendingId = _uuid();
      _pendingBody = body.trim();
    }
    state = AsyncData(
      ChatThreadState(page: current.page, sending: true).carry(current),
    );
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
        ).carry(current),
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
    final session = ref.read(chatEpochProvider)();
    bool isCurrent() =>
        ref.mounted &&
        _epoch == epoch &&
        identical(ref.read(chatEpochProvider)(), session);
    state = AsyncData(
      ChatThreadState(page: current.page, loadingOlder: true).carry(current),
    );
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
        ).carry(current),
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
        ChatThreadState(
          page: current.page,
          error: chatErrorMessage(error),
        ).carry(current),
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
