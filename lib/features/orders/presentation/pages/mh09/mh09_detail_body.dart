import 'package:flutter/material.dart';

import '../../../domain/models/order_details.dart';
import '../../widgets/order_lifecycle_sections.dart';
import '../../widgets/order_timeline.dart';
import '../../widgets/mh09/mh09_items_section.dart';
import '../../widgets/mh09/mh09_operational_actions.dart';
import '../../widgets/mh09/mh09_order_identity.dart';
import '../../widgets/mh09/mh09_payment_section.dart';
import '../../widgets/mh09/mh09_recipient_section.dart';

/// The scrollable read projection for MH09.
///
/// The page owns refresh, session and navigation decisions. This body only
/// composes the accepted [OrderDetails] aggregate into its visual sections.
class Mh09DetailBody extends StatelessWidget {
  const Mh09DetailBody({
    required this.details,
    required this.onRefresh,
    this.contactEnabled = false,
    this.onCall,
    this.onChat,
    this.onOpenCod,
    this.onOpenReturn,
    super.key,
  });

  final OrderDetails details;
  final Future<void> Function() onRefresh;
  final bool contactEnabled;
  final VoidCallback? onCall;
  final VoidCallback? onChat;
  final ValueChanged<String>? onOpenCod;
  final ValueChanged<String>? onOpenReturn;

  @override
  Widget build(BuildContext context) {
    final order = details.order;
    final sections = <Widget>[
      Mh09OrderIdentity(order: order),
      Mh09RecipientSection(
        order: order,
        buyer: details.buyer,
        contactEnabled: contactEnabled,
        onCall: onCall,
        onChat: onChat,
      ),
      Mh09ItemsSection(items: details.items),
      Mh09PaymentSection(order: order, codSummary: details.codSummary),
      OrderLifecycleSections(
        deliverySummary: details.deliverySummary,
        codSummary: details.codSummary,
        returnSummaries: details.returnSummaries,
        onOpenCod: onOpenCod,
        onOpenReturn: onOpenReturn,
      ),
      OrderTimeline(
        entries: details.timeline,
        historyComplete: details.historyComplete,
      ),
      Mh09OperationalActions(capabilities: details.capabilities),
    ];

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < sections.length; index++) ...[
              if (index > 0) const SizedBox(height: 16),
              sections[index],
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
