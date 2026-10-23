import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/operational_read_access.dart';
import '../../data/repositories/operational_providers.dart';
import '../../data/repositories/supabase_delivery_repository.dart';
import '../../domain/models/delivery_task.dart';
import '../../domain/models/delivery_task_details.dart';
import '../../domain/repositories/delivery_repository.dart';

final deliveryRepositoryProvider = Provider.autoDispose<DeliveryRepository>((
  ref,
) {
  return SupabaseDeliveryRepository(
    access: ref.watch(operationalReadAccessProvider),
  );
});

final _tasksForSessionProvider = FutureProvider.autoDispose
    .family<List<DeliveryTaskSnapshot>, OperationalSession>(
      (ref, session) => ref.watch(deliveryRepositoryProvider).listTasks(),
      retry: (count, error) => null,
    );

final _detailsForSessionProvider = FutureProvider.autoDispose
    .family<DeliveryTaskDetails, (OperationalSession, String)>(
      (ref, key) =>
          ref.watch(deliveryRepositoryProvider).getTaskDetails(key.$2),
      retry: (count, error) => null,
    );

final deliveryTasksProvider =
    Provider.autoDispose<AsyncValue<List<DeliveryTaskSnapshot>>>((ref) {
      final session = ref.watch(operationalSessionProvider);
      final failure = operationalSessionFailure(session);
      if (failure != null) return AsyncError(failure, StackTrace.empty);
      if (session.isLoading) return const AsyncLoading();
      return withoutPreviousOperationalData(
        ref.watch(_tasksForSessionProvider(session.requireValue)),
      );
    });

final deliveryTaskDetailsProvider = Provider.autoDispose
    .family<AsyncValue<DeliveryTaskDetails>, String>((ref, taskId) {
      final session = ref.watch(operationalSessionProvider);
      final failure = operationalSessionFailure(session);
      if (failure != null) return AsyncError(failure, StackTrace.empty);
      if (session.isLoading) return const AsyncLoading();
      return withoutPreviousOperationalData(
        ref.watch(_detailsForSessionProvider((session.requireValue, taskId))),
      );
    });
