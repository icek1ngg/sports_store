import 'package:flutter/material.dart';

/// The two recipient contact affordances rendered inside the MH09 card.
///
/// Availability is decided by the owning recipient section. This widget only
/// renders the immutable flags, reasons and callbacks it receives.
class Mh09ContactActions extends StatelessWidget {
  const Mh09ContactActions({
    this.callEnabled = false,
    this.chatEnabled = false,
    this.callReason,
    this.chatReason,
    this.onCall,
    this.onChat,
    super.key,
  });

  final bool callEnabled;
  final bool chatEnabled;
  final String? callReason;
  final String? chatReason;
  final VoidCallback? onCall;
  final VoidCallback? onChat;

  @override
  Widget build(BuildContext context) {
    final explanation = <String>[
      if (callReason != null) 'Gọi: $callReason',
      if (chatReason != null) 'Nhắn tin: $chatReason',
    ].join(' ');

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final stack = constraints.maxWidth < 300 * (scale < 1 ? 1 : scale);
        final controls = [
          _contactButton(
            key: const ValueKey('mh09-recipient-call'),
            icon: Icons.call_outlined,
            label: 'Gọi',
            enabled: callEnabled,
            reason: callReason,
            callback: onCall,
          ),
          _contactButton(
            key: const ValueKey('mh09-recipient-chat'),
            icon: Icons.chat_bubble_outline,
            label: 'Nhắn tin',
            enabled: chatEnabled,
            reason: chatReason,
            callback: onChat,
          ),
        ];
        final actions = stack
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [controls[0], const SizedBox(height: 8), controls[1]],
              )
            : Row(
                children: [
                  Expanded(child: controls[0]),
                  const SizedBox(width: 8),
                  Expanded(child: controls[1]),
                ],
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            actions,
            if (explanation.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(explanation, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        );
      },
    );
  }

  Widget _contactButton({
    required String label,
    required IconData icon,
    required bool enabled,
    required String? reason,
    required VoidCallback? callback,
    required Key key,
  }) {
    return Semantics(
      button: true,
      enabled: enabled,
      excludeSemantics: true,
      label: reason == null ? label : '$label. $reason',
      onTap: enabled ? callback : null,
      child: FilledButton.tonalIcon(
        key: key,
        onPressed: enabled ? callback : null,
        icon: Icon(icon),
        label: Text(label, softWrap: true),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}
