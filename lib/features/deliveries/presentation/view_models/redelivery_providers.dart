import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/operational_providers.dart';
import '../../data/repositories/supabase_redelivery_repository.dart';
import '../../domain/models/delivery_task_details.dart';
import '../../domain/repositories/redelivery_repository.dart';
import 'delivery_providers.dart';
import 'delivery_task_list_view_model.dart';
import 'outbound_action_providers.dart';

/// Production repository for shipper-owned redelivery commands.
final redeliveryRepositoryProvider = Provider.autoDispose<RedeliveryRepository>(
  (ref) => SupabaseRedeliveryRepository(
    access: ref.watch(operationalReadAccessProvider),
  ),
);

/// Stable UUID factory shared with the existing delivery command flows.
/// Called exactly once per confirmed command; the ViewModel retains the
/// resulting envelope across timeout/ACK retries.
final redeliveryRequestIdProvider = Provider<String Function()>(
  (ref) => ref.watch(outboundTaskRequestIdProvider),
);

/// Authoritative MH11 detail read after a command receipt.
final redeliveryDetailsReloadProvider =
    Provider<Future<DeliveryTaskDetails> Function(String)>((ref) {
      return (taskId) => refetchDeliveryTaskAfterCommand(ref, taskId);
    });

/// Refreshes MH10 after a command has been committed and the detail read is
/// complete.  The list remains a read projection; no local row is fabricated.
final redeliveryTaskListReloadProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    invalidateLegacyDeliveryTaskReads(ref);
    await ref.read(deliveryTaskListViewModelProvider.notifier).refresh();
    if (!ref.mounted) return;
    final error = ref.read(deliveryTaskListViewModelProvider).error;
    if (error != null) throw error;
  },
);

// Short aliases keep test seams and feature-level wiring discoverable.
final deliveryRedeliveryRepositoryProvider = redeliveryRepositoryProvider;
final redeliveryDetailsRefetchProvider = redeliveryDetailsReloadProvider;
final redeliveryListRefreshProvider = redeliveryTaskListReloadProvider;
