import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/operational_providers.dart';
import '../../data/repositories/supabase_outbound_failure_repository.dart';
import '../../domain/models/delivery_task_details.dart';
import '../../domain/repositories/outbound_failure_repository.dart';
import 'delivery_providers.dart';
import 'delivery_task_list_view_model.dart';
import 'outbound_action_providers.dart';

final outboundFailureRepositoryProvider = Provider<OutboundFailureRepository>(
  (ref) => SupabaseOutboundFailureRepository(
    access: ref.watch(operationalReadAccessProvider),
  ),
);
final outboundFailureRequestIdProvider = Provider<String Function()>(
  (ref) => ref.watch(outboundTaskRequestIdProvider),
);
final outboundFailureDetailsReloadProvider =
    Provider<Future<DeliveryTaskDetails> Function(String)>(
      (ref) =>
          (taskId) => refetchDeliveryTaskAfterCommand(ref, taskId),
    );
final outboundFailureTaskListReloadProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    // A failed task can be masked in the server projection and no longer
    // match the previous state/search filter. Reset the MH10 query before
    // reloading so the shipper can discover the failed row and choose the
    // explicit second-attempt action.
    invalidateLegacyDeliveryTaskReads(ref);
    await ref.read(deliveryTaskListViewModelProvider.notifier).resetFilters();
    if (!ref.mounted) return;
    final error = ref.read(deliveryTaskListViewModelProvider).error;
    if (error != null) throw error;
  },
);
