import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/operational_providers.dart';
import '../../data/repositories/supabase_outbound_retry_repository.dart';
import '../../domain/models/delivery_task_details.dart';
import '../../domain/repositories/outbound_retry_repository.dart';
import 'delivery_providers.dart';
import 'delivery_task_list_view_model.dart';
import 'outbound_action_providers.dart';

final outboundRetryRepositoryProvider = Provider<OutboundRetryRepository>(
  (ref) => SupabaseOutboundRetryRepository(
    access: ref.watch(operationalReadAccessProvider),
  ),
);

/// Request IDs are generated once per command and retained by the ViewModel
/// when a response is uncertain. Reusing the same ID is required by the RPC's
/// idempotency contract.
final outboundRetryRequestIdProvider = Provider<String Function()>(
  (ref) => ref.watch(outboundTaskRequestIdProvider),
);

final outboundRetryDetailsReloadProvider =
    Provider<Future<DeliveryTaskDetails> Function(String)>((ref) {
      return (taskId) => refetchDeliveryTaskAfterCommand(ref, taskId);
    });

/// Refresh the list after creating task 2. Resetting the state-group/search
/// filters is intentional: the old task was in the failed bucket, while the
/// new assigned task belongs to the waiting bucket.
final outboundRetryTaskListReloadProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    invalidateLegacyDeliveryTaskReads(ref);
    await ref.read(deliveryTaskListViewModelProvider.notifier).resetFilters();
    if (!ref.mounted) return;
    final error = ref.read(deliveryTaskListViewModelProvider).error;
    if (error != null) throw error;
  },
);
