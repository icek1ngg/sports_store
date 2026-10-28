import 'package:flutter/material.dart';

import '../order_notification_theme.dart';

/// Parent-controlled search and filter controls for the manager order feed.
class Mh08SearchSection extends StatefulWidget {
  const Mh08SearchSection({
    required this.value,
    required this.onChanged,
    this.onClear,
    this.onFilter,
    this.errorText,
    this.hintText = 'Mã đơn hoặc tên khách hàng...',
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;
  final VoidCallback? onFilter;
  final String? errorText;
  final String hintText;

  @override
  State<Mh08SearchSection> createState() => _Mh08SearchSectionState();
}

class _Mh08SearchSectionState extends State<Mh08SearchSection> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant Mh08SearchSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncValue(widget.value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncValue(String value) {
    if (_controller.text == value) return;

    final selection = _controller.selection;
    final baseOffset = _boundOffset(selection.baseOffset, value.length);
    final extentOffset = _boundOffset(selection.extentOffset, value.length);
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection(
        baseOffset: baseOffset,
        extentOffset: extentOffset,
      ),
      composing: TextRange.empty,
    );
  }

  int _boundOffset(int offset, int length) {
    if (offset < 0) return 0;
    if (offset > length) return length;
    return offset;
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      key: const ValueKey('mh08-search-field'),
      controller: _controller,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: widget.hintText,
        errorText: widget.errorText,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _controller.text.isEmpty || widget.onClear == null
            ? null
            : IconButton(
                tooltip: 'Xóa tìm kiếm',
                onPressed: widget.onClear,
                icon: const Icon(Icons.clear_rounded),
              ),
        constraints: const BoxConstraints(minHeight: 40),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: field),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Lọc theo trạng thái',
          onPressed: widget.onFilter,
          icon: const Icon(Icons.tune_rounded),
          style: IconButton.styleFrom(
            backgroundColor: OrderNotificationTheme.cloud,
            disabledBackgroundColor: OrderNotificationTheme.cloud,
            minimumSize: const Size(48, 48),
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
