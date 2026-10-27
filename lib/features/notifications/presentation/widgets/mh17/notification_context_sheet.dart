import 'package:flutter/material.dart';

/// Authorized display strings only; the parent owns modal and session lifetime.
class Mh17NotificationContextSheet extends StatelessWidget {
  const Mh17NotificationContextSheet({
    required this.title,
    required this.body,
    this.availabilityMessage,
    this.onClose,
    super.key,
  });

  final String title;
  final String body;
  final String? availabilityMessage;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            const SizedBox(height: 12),
            Text(body),
            if (availabilityMessage != null) ...[
              const SizedBox(height: 12),
              Semantics(liveRegion: true, child: Text(availabilityMessage!)),
            ],
            const SizedBox(height: 20),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: onClose,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: const Text('Đóng'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
