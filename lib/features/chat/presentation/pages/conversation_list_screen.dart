import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../shared/widgets/prm_preview_widgets.dart';
import '../../domain/models/chat_models.dart';
import '../view_models/chat_providers.dart';

class ConversationListScreen extends ConsumerStatefulWidget {
  const ConversationListScreen({
    super.key,
    this.onOpenConversation,
    this.isCustomer = false,
  });
  final ValueChanged<String>? onOpenConversation;
  final bool isCustomer;
  @override
  ConsumerState<ConversationListScreen> createState() =>
      _ConversationListScreenState();
}

class _ConversationListScreenState
    extends ConsumerState<ConversationListScreen> {
  final _search = TextEditingController();
  String _filter = 'Tất cả';
  bool _starting = false;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted &&
          ModalRoute.of(context)?.isCurrent == true &&
          !ref.read(chatInboxProvider).isLoading) {
        ref.invalidate(chatInboxProvider);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      final id = await ref
          .read(chatInboxProvider.notifier)
          .startCustomerConversation();
      if (mounted) widget.onOpenConversation?.call(id);
    } catch (error) {
      if (mounted) showNotice(context, chatErrorMessage(error));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(chatInboxProvider);
    final userId = ref.watch(supabaseClientProvider).auth.currentUser?.id;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Hội thoại',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tải lại',
                    onPressed: inbox.isLoading
                        ? null
                        : () => ref.invalidate(chatInboxProvider),
                    icon: const Icon(Icons.refresh),
                  ),
                  if (widget.isCustomer)
                    FilledButton.icon(
                      onPressed: _starting || widget.onOpenConversation == null
                          ? null
                          : _start,
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: Text(_starting ? 'Đang mở…' : 'Liên hệ cửa hàng'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Tìm khách hàng hoặc nội dung tin nhắn…',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['Tất cả', 'Chưa đọc', 'Chờ cửa hàng trả lời']
                    .map(
                      (label) => ChoiceChip(
                        label: Text(label),
                        selected: _filter == label,
                        onSelected: (_) => setState(() => _filter = label),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
        Expanded(
          child: inbox.when(
            skipLoadingOnRefresh: false,
            skipLoadingOnReload: false,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _error(e),
            data: (conversations) {
              final query = _search.text.trim().toLowerCase();
              final rows = conversations
                  .where(
                    (c) =>
                        (query.isEmpty ||
                            c.customerName.toLowerCase().contains(query) ||
                            (c.lastMessage ?? '').toLowerCase().contains(
                              query,
                            )) &&
                        (_filter != 'Chưa đọc' || c.unreadCount > 0) &&
                        (_filter != 'Chờ cửa hàng trả lời' ||
                            c.needsManagerReply),
                  )
                  .toList();
              if (rows.isEmpty) {
                return const Center(child: Text('Chưa có hội thoại phù hợp.'));
              }
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(chatInboxProvider);
                  await ref.read(chatInboxProvider.future);
                },
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) => _row(rows[index], userId),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _error(Object error) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(chatErrorMessage(error)),
          TextButton(
            onPressed: () => ref.invalidate(chatInboxProvider),
            child: const Text('Thử lại'),
          ),
        ],
      ),
    ),
  );
  Widget _row(ChatConversation c, String? userId) => Card(
    child: ListTile(
      onTap: widget.onOpenConversation == null
          ? null
          : () => widget.onOpenConversation!(c.id),
      leading: CircleAvatar(
        child: Text(
          c.customerName.trim().isEmpty
              ? '?'
              : c.customerName.trim().substring(0, 1),
        ),
      ),
      title: Text(
        widget.isCustomer ? 'Cửa hàng STRIDE' : c.customerName,
        style: TextStyle(
          fontWeight: c.unreadCount > 0 ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      subtitle: Text(
        c.lastMessage == null
            ? 'Chưa có tin nhắn'
            : '${c.lastSenderId == userId ? 'Bạn: ' : ''}${c.lastMessage}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c.lastMessageAt != null)
            Text(
              _date(c.lastMessageAt!),
              style: const TextStyle(fontSize: 11, color: muted),
            ),
          if (c.unreadCount > 0) Badge(label: Text('${c.unreadCount}')),
        ],
      ),
    ),
  );
}

String _date(DateTime value) {
  final d = value.toLocal();
  return '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
