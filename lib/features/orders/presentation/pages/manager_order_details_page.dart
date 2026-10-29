import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/feature_access_gate.dart';
import '../widgets/order_notification_theme.dart';
import 'mh09/mh09_detail_content.dart';

/// MH09 keeps its existing entrypoint and session boundary.
class ManagerOrderDetailsPage extends ConsumerWidget {
  const ManagerOrderDetailsPage({
    required this.orderId,
    this.onOpenCod,
    this.onOpenReturn,
    this.onOpenChat,
    this.onCallRecipient,
    this.enablePolling = true,
    super.key,
  });

  final String orderId;
  final ValueChanged<String>? onOpenCod;
  final ValueChanged<String>? onOpenReturn;
  final ValueChanged<String>? onOpenChat;
  final ValueChanged<String>? onCallRecipient;
  final bool enablePolling;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OrderNotificationTheme(
      child: FeatureAccessGate(
        roles: const {'manager'},
        child: Mh09DetailContent(
          orderId: orderId,
          enablePolling: enablePolling,
          onOpenCod: onOpenCod,
          onOpenReturn: onOpenReturn,
          onOpenChat: onOpenChat,
          onCallRecipient: onCallRecipient,
        ),
      ),
    );
  }
}
