import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/maps/map_directions.dart';
import '../../../../core/maps/map_providers.dart';
import '../../../../core/maps/saved_destination.dart';
import '../../data/repositories/operational_providers.dart';
import '../../domain/models/delivery_task.dart';
import '../../domain/models/delivery_task_details.dart';
import '../../domain/models/operational_failure.dart';
import 'delivery_providers.dart';

/// State and authorized reads used by MH18.
///
/// MH18 consumes the same server projection as MH11, but all actions that
/// expose or launch recipient data perform a fresh task read first.  This
/// prevents a stale detail snapshot from surviving reassignment, logout, or
/// a session epoch change while the map is open.
final deliveryTaskMapViewModelProvider = NotifierProvider.autoDispose
    .family<DeliveryTaskMapViewModel, AsyncValue<DeliveryTaskDetails>, String>(
      DeliveryTaskMapViewModel.new,
    );

class DeliveryTaskMapViewModel
    extends Notifier<AsyncValue<DeliveryTaskDetails>> {
  DeliveryTaskMapViewModel(this.taskId);

  final String taskId;

  @override
  AsyncValue<DeliveryTaskDetails> build() {
    return withoutPreviousOperationalData(
      ref.watch(deliveryTaskDetailsProvider(taskId)),
    );
  }

  Future<void> refresh() async {
    if (!ref.mounted) return;
    await refreshDeliveryTaskDetails(ref, taskId);
  }

  /// Reads the task again immediately before copying contact data or opening
  /// an external application.  The returned snapshot is never taken from an
  /// old widget value.
  Future<DeliveryTaskDetails> recheckAuthorizedDetails() async {
    final sessionState = ref.read(operationalSessionProvider);
    final failure = operationalSessionFailure(sessionState);
    final session = sessionState.asData?.value;
    if (failure != null) throw failure;
    if (session == null || session.userId == null) {
      throw const OperationalFailure(OperationalFailureCode.sessionExpired);
    }

    final details = await ref
        .read(deliveryRepositoryProvider)
        .getTaskDetails(taskId);
    if (!ref.mounted ||
        !identical(
          ref.read(operationalSessionProvider).asData?.value,
          session,
        )) {
      throw const OperationalFailure(OperationalFailureCode.sessionExpired);
    }

    final task = details.task;
    if (task.taskId != taskId ||
        task.scope != DeliverySnapshotScope.current ||
        task.destination == null) {
      throw const OperationalFailure(OperationalFailureCode.staleAssignment);
    }
    return details;
  }

  Future<MapDirectionsOutcome> openDirections() async {
    final details = await recheckAuthorizedDetails();
    final destination = _toSavedDestination(details.task.destination!);
    // Re-check the epoch directly before handing the coordinate to an
    // external app.  No recipient address or phone is put in the URL.
    final session = ref.read(operationalSessionProvider).asData?.value;
    if (session == null || session.userId == null || session.failure != null) {
      throw const OperationalFailure(OperationalFailureCode.sessionExpired);
    }
    return ref.read(mapDirectionsLauncherProvider).openDirections(destination);
  }

  SavedDestination destinationFrom(DeliveryTaskDetails details) {
    final task = details.task;
    if (task.scope != DeliverySnapshotScope.current ||
        task.destination == null) {
      throw const OperationalFailure(OperationalFailureCode.staleAssignment);
    }
    return _toSavedDestination(task.destination!);
  }

  SavedDestination _toSavedDestination(DeliveryDestination destination) {
    return SavedDestination(
      latitude: destination.latitude,
      longitude: destination.longitude,
      label: destination.name,
      phone: destination.phone,
      address: destination.address,
    );
  }
}
