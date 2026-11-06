import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/operational_providers.dart';
import '../../data/repositories/supabase_return_pickup_repository.dart';
import '../../domain/models/delivery_task_details.dart';
import '../../domain/models/return_pickup_command.dart';
import '../../domain/repositories/return_pickup_repository.dart';
import 'delivery_providers.dart';
import 'outbound_action_providers.dart';

/// Production adapter used by the pickup action controller.
final returnPickupRepositoryProvider = Provider<ReturnPickupRepository>((ref) {
  return SupabaseReturnPickupRepository(
    access: ref.watch(operationalReadAccessProvider),
  );
});

/// Stable request-key factory.  The ViewModel calls this exactly once per
/// user-confirmed command and retains the resulting command after an
/// uncertain acknowledgement.
final returnPickupRequestIdProvider = Provider<String Function()>((ref) {
  return ref.watch(outboundTaskRequestIdProvider);
});

/// Re-reads one authorized MH11 projection after a pickup acknowledgement.
final returnPickupDetailsReloadProvider =
    Provider<Future<DeliveryTaskDetails> Function(String)>((ref) {
      return (taskId) => refetchDeliveryTaskAfterCommand(ref, taskId);
    });

/// Reads only the server-owned handover marker. The default repository is
/// production-backed; repositories that do not implement this capability
/// fail closed instead of returning a fabricated `reported: false` value.
final returnPickupHandoverStatusProvider =
    Provider<Future<ReturnPickupHandoverStatus> Function(String)>((ref) {
      final repository = ref.watch(returnPickupRepositoryProvider);
      if (repository is ReturnPickupHandoverReader) {
        return (repository as ReturnPickupHandoverReader).getHandoverStatus;
      }
      // P08.1-only fixtures do not implement the new read capability. This
      // is an unavailable seam, never an implicit `reported: false` result.
      final dynamic candidate = repository;
      return (taskId) async {
        try {
          final result = await candidate.getHandoverStatus(taskId);
          if (result is ReturnPickupHandoverStatus) return result;
          throw const FormatException('invalid return-pickup handover marker');
        } on NoSuchMethodError {
          throw UnsupportedError(
            'return-pickup handover marker is unavailable',
          );
        }
      };
    });

/// Refreshes MH10 after a committed collect/fail command.
final returnPickupTaskListReloadProvider = Provider<Future<void> Function()>(
  (ref) =>
      () => ref.read(outboundTaskListReloadProvider)(),
);

// Short aliases keep test seams and feature-level wiring readable without
// creating a second provider or a second source of truth.
final pickupRepositoryProvider = returnPickupRepositoryProvider;
final pickupRequestIdProvider = returnPickupRequestIdProvider;
final pickupDetailsReloadProvider = returnPickupDetailsReloadProvider;
final pickupHandoverStatusProvider = returnPickupHandoverStatusProvider;
final pickupTaskListReloadProvider = returnPickupTaskListReloadProvider;
