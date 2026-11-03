import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/utils/display_formatters.dart';
import '../../../../shared/widgets/foreground_refresh.dart';
import '../../domain/models/chat_models.dart';
import '../view_models/chat_providers.dart';

/// Server limit enforced by `send_chat_message`.
const chatMessageMaxLength = 4000;

/// MH20 "Chi tiết hội thoại": customer ↔ store plain-text thread.
class ConversationDetailScreen extends ConsumerStatefulWidget {
  const ConversationDetailScreen({
    super.key,
    required this.conversationId,
    this.onBack,
  });
  final String conversationId;

  /// Back to MH19. Defaults to popping, or `/chat` when opened directly.
  final VoidCallback? onBack;

  @override
  ConsumerState<ConversationDetailScreen> createState() =>
      _ConversationDetailScreenState();
}

class _ConversationDetailScreenState
    extends ConsumerState<ConversationDetailScreen> {
  final _body = TextEditingController();
  final _scroll = ScrollController();
  bool _atBottom = true;
  bool _probedOnce = false;

  AsyncNotifierProvider<ChatThreadViewModel, ChatThreadState> get _provider =>
      chatThreadProvider(widget.conversationId);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _body.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _scroll.dispose();
    _body.dispose();
    super.dispose();
  }

  // The list is reversed: offset 0 is the newest message.
  void _onScroll() {
    final atBottom = !_scroll.hasClients || _scroll.offset < 48;
    if (atBottom == _atBottom) return;
    setState(() => _atBottom = atBottom);
    if (atBottom) {
      unawaited(ref.read(_provider.notifier).showNewMessages());
    }
  }

  void _poll() =>
      unawaited(ref.read(_provider.notifier).poll(viewingLatest: _atBottom));

  Future<void> _send() async {
    final text = _body.text;
    final sent = await ref.read(_provider.notifier).send(text);
    if (!mounted || !sent) return;
    // Keep anything typed after pressing "Gửi"; remove only what was sent.
    final now = _body.text;
    if (now == text) {
      _body.clear();
    } else if (now.startsWith(text)) {
      _body.text = now.substring(text.length).trimLeft();
      _body.selection = TextSelection.collapsed(offset: _body.text.length);
    }
    if (_scroll.hasClients) {
      unawaited(
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  void _back() {
    if (widget.onBack != null) return widget.onBack!();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/chat');
    }
  }

  @override
  Widget build(BuildContext context) {
    final thread = ref.watch(_provider);
    final ownId = ref.watch(supabaseClientProvider).auth.currentUser?.id;
    final value = thread.asData?.value;
    if (value != null && !_probedOnce) {
      _probedOnce = true;
      // Read markers for "Đã xem" right after opening.
      scheduleMicrotask(_poll);
    }

    final Widget body = thread.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: false,
      loading: () => const Center(
        child: CircularProgressIndicator(key: ValueKey('mh20-loading')),
      ),
      error: (e, _) => _Status(
        key: const ValueKey('mh20-error'),
        text: chatErrorMessage(e),
        onRetry: () => ref.invalidate(_provider),
      ),
      data: (value) => _Thread(
        value: value,
        ownId: ownId,
        scroll: _scroll,
        onLoadOlder: () => ref.read(_provider.notifier).loadOlder(),
      ),
    );

    return AppTheme.notificationsScope(
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _Header(
                conversationId: widget.conversationId,
                ownId: ownId,
                onBack: _back,
                onRefresh: value == null || value.busy
                    ? (thread.hasError ? () => ref.invalidate(_provider) : null)
                    : () => unawaited(
                        ref.read(_provider.notifier).refreshLatest(),
                      ),
              ),
              if (value?.refreshing == true)
                const LinearProgressIndicator(minHeight: 2),
              if (value?.connectionIssue != null)
                _Banner(
                  key: const ValueKey('mh20-connection'),
                  text: value!.connectionIssue!,
                ),
              Expanded(
                child: ForegroundRefresh(
                  enabled: value != null,
                  canRefresh: () => ref.read(_provider.notifier).canPoll,
                  onRefresh: _poll,
                  child: Stack(
                    children: [
                      Positioned.fill(child: body),
                      if (value?.newBelow == true)
                        Positioned(
                          bottom: 12,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: ActionChip(
                              key: const ValueKey('mh20-new-below'),
                              avatar: const Icon(
                                Icons.arrow_downward,
                                size: 16,
                                color: AppColors.onPrimary,
                              ),
                              label: const Text('Có tin nhắn mới'),
                              labelStyle: const TextStyle(
                                color: AppColors.onPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                              backgroundColor: AppColors.primary,
                              onPressed: () {
                                if (_scroll.hasClients) _scroll.jumpTo(0);
                                unawaited(
                                  ref
                                      .read(_provider.notifier)
                                      .showNewMessages(),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (value != null)
                _Composer(controller: _body, value: value, onSend: _send),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.conversationId,
    required this.ownId,
    required this.onBack,
    required this.onRefresh,
  });

  final String conversationId;
  final String? ownId;
  final VoidCallback onBack;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(chatInboxProvider).asData?.value;
    ChatConversation? conversation;
    for (final c in inbox ?? const <ChatConversation>[]) {
      if (c.id == conversationId) conversation = c;
    }
    final viewerIsCustomer =
        conversation != null && conversation.customerId == ownId;
    final title = conversation == null
        ? 'Hội thoại'
        : viewerIsCustomer
        ? 'Cửa hàng Sports Store'
        : conversation.customerName;
    final role = conversation == null
        ? null
        : viewerIsCustomer
        ? 'Hỗ trợ khách hàng'
        : 'Khách hàng';
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.hairlineSoft)),
      ),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('mh20-back'),
            tooltip: 'Quay lại danh sách hội thoại',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: AppColors.ink),
          ),
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.softCloud,
            child: Icon(
              viewerIsCustomer || conversation == null
                  ? Icons.storefront_outlined
                  : Icons.person_outline,
              color: AppColors.ink,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Chi tiết hội thoại',
                  style: TextStyle(fontSize: 12, color: AppColors.mute),
                ),
                Text(
                  title,
                  key: const ValueKey('mh20-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
          if (role != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.softCloud,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                role,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.charcoal,
                ),
              ),
            ),
          IconButton(
            key: const ValueKey('mh20-refresh'),
            tooltip: 'Tải tin nhắn mới',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, color: AppColors.ink),
          ),
        ],
      ),
    );
  }
}

/// One row of the reversed list: a message, or a date separator before it.
sealed class _Row {
  const _Row();
}

class _DateRow extends _Row {
  const _DateRow(this.label);
  final String label;
}

class _MessageRow extends _Row {
  const _MessageRow(this.message, {required this.firstOfGroup});
  final ChatMessage message;
  final bool firstOfGroup;
}

String _hanoiDayKey(DateTime t) {
  final h = toHanoi(t);
  return '${h.year}-${h.month}-${h.day}';
}

String _dayLabel(DateTime t, DateTime now) {
  final day = _hanoiDayKey(t);
  if (day == _hanoiDayKey(now)) return 'Hôm nay, ${formatHanoiDate(t)}';
  if (day == _hanoiDayKey(now.subtract(const Duration(days: 1)))) {
    return 'Hôm qua, ${formatHanoiDate(t)}';
  }
  return formatHanoiDate(t);
}

String _hanoiTime(DateTime t) {
  final h = toHanoi(t);
  return '${h.hour.toString().padLeft(2, '0')}:'
      '${h.minute.toString().padLeft(2, '0')}';
}

/// Chronological rows (oldest first) with a date separator per Hanoi day.
List<_Row> _buildChatRows(List<ChatMessage> messages, DateTime now) {
  final rows = <_Row>[];
  String? day;
  String? sender;
  for (final m in messages) {
    final key = _hanoiDayKey(m.createdAt);
    if (key != day) {
      rows.add(_DateRow(_dayLabel(m.createdAt, now)));
      day = key;
      sender = null;
    }
    rows.add(_MessageRow(m, firstOfGroup: sender != m.senderId));
    sender = m.senderId;
  }
  return rows;
}

class _Thread extends ConsumerWidget {
  const _Thread({
    required this.value,
    required this.ownId,
    required this.scroll,
    required this.onLoadOlder,
  });

  final ChatThreadState value;
  final String? ownId;
  final ScrollController scroll;
  final VoidCallback onLoadOlder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = value.page.messages;
    if (messages.isEmpty) {
      return const _Status(
        key: ValueKey('mh20-empty'),
        text: 'Chưa có tin nhắn. Hãy gửi câu hỏi đầu tiên cho cửa hàng.',
      );
    }
    final inbox = ref.watch(chatInboxProvider).asData?.value;
    String? customerId;
    String customerName = 'Khách hàng';
    for (final c in inbox ?? const <ChatConversation>[]) {
      if (c.id == messages.first.conversationId) {
        customerId = c.customerId;
        customerName = c.customerName;
      }
    }
    final rows = _buildChatRows(messages, DateTime.now().toUtc());
    final ownLatest = messages.lastWhere(
      (m) => m.senderId == ownId,
      orElse: () => messages.first,
    );
    final extra = value.page.hasMore ? 1 : 0;
    return ListView.builder(
      key: const ValueKey('mh20-list'),
      controller: scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: rows.length + extra,
      itemBuilder: (context, index) {
        if (index == rows.length) {
          return Center(
            child: TextButton(
              key: const ValueKey('mh20-older'),
              onPressed: value.busy ? null : onLoadOlder,
              child: Text(
                value.loadingOlder ? 'Đang tải…' : 'Xem tin nhắn cũ hơn',
              ),
            ),
          );
        }
        final row = rows[rows.length - 1 - index];
        return switch (row) {
          _DateRow(:final label) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.hairlineSoft),
                ),
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: AppColors.mute),
                ),
              ),
            ),
          ),
          _MessageRow(:final message, :final firstOfGroup) => _Bubble(
            message: message,
            own: message.senderId == ownId,
            senderLabel: message.senderId == ownId
                ? null
                : message.senderId == customerId
                ? customerName
                : 'Cửa hàng',
            showSender: firstOfGroup,
            // Status only on the newest own message, like most messengers.
            status: message.senderId == ownId && message.id == ownLatest.id
                ? (value.othersReadAt != null &&
                          !value.othersReadAt!.isBefore(message.createdAt)
                      ? 'Đã xem'
                      : 'Đã gửi')
                : null,
          ),
        };
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.own,
    required this.senderLabel,
    required this.showSender,
    required this.status,
  });

  final ChatMessage message;
  final bool own;
  final String? senderLabel;
  final bool showSender;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width * 0.78;
    return Padding(
      key: ValueKey('mh20-message-${message.id}'),
      padding: EdgeInsets.only(top: showSender ? 8 : 2),
      child: Column(
        crossAxisAlignment: own
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (!own && showSender && senderLabel != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                senderLabel!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.mute,
                ),
              ),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth.clamp(200, 520)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: own ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(own ? 16 : 4),
                  bottomRight: Radius.circular(own ? 4 : 16),
                ),
                border: own ? null : Border.all(color: AppColors.hairlineSoft),
              ),
              child: SelectableText(
                message.body,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: own ? AppColors.onPrimary : AppColors.ink,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
            child: Text(
              status == null
                  ? _hanoiTime(message.createdAt)
                  : '${_hanoiTime(message.createdAt)} · $status',
              key: status == null ? null : const ValueKey('mh20-status'),
              style: const TextStyle(fontSize: 11, color: AppColors.mute),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.value,
    required this.onSend,
  });

  final TextEditingController controller;
  final ChatThreadState value;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final text = controller.text.trim();
    final tooLong = controller.text.length > chatMessageMaxLength;
    final canSend = text.isNotEmpty && !tooLong && !value.busy;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.hairlineSoft)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (value.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 16,
                    color: AppColors.sale,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${value.error!} Tin nhắn vẫn được giữ trong ô nhập.',
                      key: const ValueKey('mh20-send-error'),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.sale,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('mh20-retry'),
                    onPressed: canSend ? onSend : null,
                    child: const Text('Gửi lại'),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('mh20-input'),
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  // The user may keep typing while a message is being sent.
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: 'Nhập tin nhắn…',
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.softCloud,
                    errorText: tooLong
                        ? 'Tối đa $chatMessageMaxLength ký tự.'
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                key: const ValueKey('mh20-send'),
                tooltip: 'Gửi tin nhắn',
                onPressed: canSend ? onSend : null,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.hairline,
                ),
                icon: value.sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onPrimary,
                        ),
                      )
                    : const Icon(Icons.send, color: AppColors.onPrimary),
              ),
            ],
          ),
          if (controller.text.length > chatMessageMaxLength - 500)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${controller.text.length}/$chatMessageMaxLength',
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 11, color: AppColors.mute),
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Chỉ hỗ trợ tin nhắn văn bản giữa khách hàng và cửa hàng.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.mute),
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    color: const Color(0xfffffaee),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12.5, color: Color(0xff5c4300)),
    ),
  );
}

class _Status extends StatelessWidget {
  const _Status({required this.text, this.onRetry, super.key});
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: AppColors.charcoal),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Thử lại')),
          ],
        ],
      ),
    ),
  );
}
