import 'package:flutter/material.dart';

import '../../../../shared/widgets/prm_preview_widgets.dart';

class _Conversation {
  const _Conversation({
    required this.name,
    required this.order,
    required this.preview,
    required this.time,
    required this.initials,
    required this.status,
    this.unread = 0,
  });
  final String name;
  final String order;
  final String preview;
  final String time;
  final String initials;
  final String status;
  final int unread;
}

class ConversationListScreen extends StatefulWidget {
  const ConversationListScreen({super.key});
  @override
  State<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends State<ConversationListScreen> {
  final _search = TextEditingController();
  String _filter = 'Tất cả';
  static const _conversations = <_Conversation>[
    _Conversation(
      name: 'Nguyễn Minh Anh',
      order: '#DH00125',
      preview: 'Shop ơi, giày đi êm còn đổi size không ạ?',
      time: '10:24',
      initials: 'NA',
      status: 'Chưa trả lời',
      unread: 2,
    ),
    _Conversation(
      name: 'Trần Hùng Nam',
      order: '#DH00108',
      preview: 'Khi nào có hàng lại?',
      time: '09:15',
      initials: 'TK',
      status: 'Đang xử lý',
    ),
    _Conversation(
      name: 'Lê Thu Hà',
      order: '#DH00102',
      preview: 'Có thể đổi size được không ạ?',
      time: 'Hôm qua',
      initials: 'LH',
      status: 'Chờ phản hồi',
    ),
    _Conversation(
      name: 'Phạm Việt Anh',
      order: '#DH00099',
      preview: 'Cảm ơn shop! Sản phẩm rất đẹp.',
      time: '12/09',
      initials: 'PR',
      status: 'Đã hoàn tất',
    ),
  ];
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<_Conversation> get _filtered => _conversations.where((c) {
    final q = _search.text.trim().toLowerCase();
    final matches =
        q.isEmpty ||
        c.name.toLowerCase().contains(q) ||
        c.order.toLowerCase().contains(q);
    final status = switch (_filter) {
      'Chưa trả lời' => c.status == 'Chưa trả lời',
      'Đang xử lý' => c.status == 'Đang xử lý',
      'Đã hoàn tất' => c.status == 'Đã hoàn tất',
      _ => true,
    };
    return matches && status;
  }).toList();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(17, 12, 17, 14),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _adminHeader(),
                    const SizedBox(height: 15),
                    const Text(
                      'Hội thoại',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.45,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Quản lý các cuộc hội thoại với khách hàng.',
                      style: TextStyle(fontSize: 10, color: muted),
                    ),
                    const SizedBox(height: 13),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children:
                            [
                                  'Tất cả',
                                  'Chưa trả lời',
                                  'Đang xử lý',
                                  'Đã hoàn tất',
                                ]
                                .map(
                                  (label) => Padding(
                                    padding: const EdgeInsets.only(right: 5),
                                    child: _filterChip(label),
                                  ),
                                )
                                .toList(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Tìm mã đơn hàng hoặc tên khách hàng...',
                        prefixIcon: Icon(Icons.search_rounded, size: 17),
                        contentPadding: EdgeInsets.symmetric(vertical: 9),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 11),
                  ],
                ),
              ),
            ),
            if (_filtered.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'Không có hội thoại phù hợp.',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(13, 0, 13, 17),
                sliver: SliverList.separated(
                  itemCount: _filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 5),
                  itemBuilder: (context, index) =>
                      _conversationRow(_filtered[index]),
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _adminHeader() => Row(
    children: [
      const BrandMark(compact: true),
      const Spacer(),
      Container(
        width: 29,
        height: 29,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Color(0xFFE7EEE9),
          shape: BoxShape.circle,
        ),
        child: const Text(
          'A',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
        ),
      ),
    ],
  );

  int _count(String label) => switch (label) {
    'Tất cả' => _conversations.length,
    'Chưa trả lời' => _conversations.where((c) => c.status == label).length,
    'Đang xử lý' => _conversations.where((c) => c.status == label).length,
    'Đã hoàn tất' => _conversations.where((c) => c.status == label).length,
    _ => 0,
  };

  Widget _filterChip(String label) {
    final selected = _filter == label;
    return ChoiceChip(
      label: Text('$label  ${_count(label)}'),
      selected: selected,
      onSelected: (_) => setState(() => _filter = label),
      showCheckmark: false,
      labelStyle: TextStyle(
        fontSize: 9,
        color: selected ? Colors.white : muted,
        fontWeight: FontWeight.w700,
      ),
      backgroundColor: Colors.white,
      selectedColor: ink,
      side: BorderSide(color: selected ? ink : line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 2),
    );
  }

  Widget _conversationRow(_Conversation c) => InkWell(
    onTap: () => _openConversation(c),
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.fromLTRB(8, 9, 8, 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEAF0F2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 35,
            height: 35,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFEDEFF2),
              shape: BoxShape.circle,
            ),
            child: Text(
              c.initials,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xFF555B61),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _statusBadge(c.status),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  c.order,
                  style: const TextStyle(fontSize: 8, color: muted),
                ),
                const SizedBox(height: 3),
                Text(
                  c.preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9, color: Color(0xFF535D59)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(c.time, style: const TextStyle(fontSize: 8, color: muted)),
              if (c.unread > 0) ...[
                const SizedBox(height: 4),
                Container(
                  width: 16,
                  height: 16,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE65353),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${c.unread}',
                    style: const TextStyle(
                      fontSize: 8,
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    ),
  );

  Widget _statusBadge(String status) {
    final (background, foreground) = switch (status) {
      'Chưa trả lời' => (const Color(0xFFFFE4E4), const Color(0xFFD75C5C)),
      'Đang xử lý' => (const Color(0xFFE4EFFC), const Color(0xFF5886C2)),
      'Chờ phản hồi' => (const Color(0xFFFFF1D7), const Color(0xFFB68528)),
      _ => (const Color(0xFFE2F2E9), const Color(0xFF4D9771)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 7,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }

  void _openConversation(_Conversation c) {
    showNotice(context, 'Màn hình chi tiết MH20 nằm ngoài phạm vi Dung An.');
  }
}
