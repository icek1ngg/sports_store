import 'package:flutter/material.dart';

class Mh09LegacyContactActions extends StatelessWidget {
  const Mh09LegacyContactActions({
    super.key,
    required this.customerId,
    required this.recipientPhone,
    this.onOpenChat,
    this.onCallRecipient,
  });

  final String customerId;
  final String recipientPhone;
  final ValueChanged<String>? onOpenChat;
  final ValueChanged<String>? onCallRecipient;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Liên hệ', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CallbackAction(
                  label: 'Gọi người nhận',
                  unavailableMessage: 'Tính năng gọi chưa khả dụng',
                  onPressed: onCallRecipient == null
                      ? null
                      : () => onCallRecipient!(recipientPhone),
                ),
                _CallbackAction(
                  label: 'Mở trao đổi với khách',
                  unavailableMessage: 'Điều hướng trò chuyện chưa khả dụng',
                  onPressed: onOpenChat == null
                      ? null
                      : () => onOpenChat!(customerId),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CallbackAction extends StatelessWidget {
  const _CallbackAction({
    required this.label,
    required this.unavailableMessage,
    required this.onPressed,
  });

  final String label;
  final String unavailableMessage;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (onPressed != null) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.open_in_new),
        label: Text(label),
      );
    }
    return Semantics(
      container: true,
      label: unavailableMessage,
      child: Text(unavailableMessage, softWrap: true),
    );
  }
}
