import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../shared/widgets/prm_preview_widgets.dart';
import '../view_models/chat_providers.dart';

class ConversationDetailScreen extends ConsumerStatefulWidget {
  const ConversationDetailScreen({super.key, required this.conversationId});
  final String conversationId;
  @override
  ConsumerState<ConversationDetailScreen> createState() =>
      _ConversationDetailScreenState();
}

class _ConversationDetailScreenState
    extends ConsumerState<ConversationDetailScreen> {
  final _body = TextEditingController();
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      final provider = chatThreadProvider(widget.conversationId);
      final value = ref.read(provider).asData?.value;
      if (value != null && !value.busy && value.error == null) {
        unawaited(ref.read(provider.notifier).refreshLatest());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _body.text;
    final sent = await ref
        .read(chatThreadProvider(widget.conversationId).notifier)
        .send(text);
    if (mounted && sent && _body.text == text) _body.clear();
  }

  @override
  Widget build(BuildContext context) {
    final provider = chatThreadProvider(widget.conversationId);
    final thread = ref.watch(provider);
    final ownId = ref.watch(supabaseClientProvider).auth.currentUser?.id;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết hội thoại'),
        actions: [
          IconButton(
            tooltip: 'Tải tin nhắn mới',
            onPressed: thread.isLoading || thread.asData?.value.busy == true
                ? null
                : () {
                    if (thread.hasError) {
                      ref.invalidate(provider);
                    } else {
                      unawaited(ref.read(provider.notifier).refreshLatest());
                    }
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: thread.when(
        skipLoadingOnRefresh: false,
        skipLoadingOnReload: false,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(chatErrorMessage(e)),
              TextButton(
                onPressed: () => ref.invalidate(provider),
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
        data: (value) => Column(
          children: [
            if (value.refreshing) const LinearProgressIndicator(),
            Expanded(
              child: value.page.messages.isEmpty
                  ? const Center(
                      child: Text('Bắt đầu cuộc trò chuyện với cửa hàng.'),
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount:
                          value.page.messages.length +
                          (value.page.hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == value.page.messages.length) {
                          return TextButton(
                            onPressed: value.busy
                                ? null
                                : () => ref.read(provider.notifier).loadOlder(),
                            child: Text(
                              value.loadingOlder
                                  ? 'Đang tải…'
                                  : 'Xem tin nhắn cũ hơn',
                            ),
                          );
                        }
                        final m = value
                            .page
                            .messages[value.page.messages.length - 1 - index];
                        final own = m.senderId == ownId;
                        return Align(
                          alignment: own
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.all(12),
                            constraints: const BoxConstraints(maxWidth: 520),
                            decoration: BoxDecoration(
                              color: own ? mint : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: line),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SelectableText(m.body),
                                const SizedBox(height: 4),
                                Text(
                                  '${m.createdAt.toLocal().day}/${m.createdAt.toLocal().month} '
                                  '${m.createdAt.toLocal().hour.toString().padLeft(2, '0')}:'
                                  '${m.createdAt.toLocal().minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (value.error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  value.error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _body,
                        enabled: !value.sending,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 4000,
                        decoration: const InputDecoration(
                          hintText: 'Nhập tin nhắn…',
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Gửi tin nhắn',
                      onPressed: value.busy ? null : _send,
                      icon: value.sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
