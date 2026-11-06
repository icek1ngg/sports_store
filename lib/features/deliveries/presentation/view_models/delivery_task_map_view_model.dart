import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/maps/map_directions.dart';
import '../../../../core/maps/map_providers.dart';
import '../../../../core/maps/saved_destination.dart';
import '../../data/repositories/operational_providers.dart';
import '../../data/repositories/operational_read_access.dart';
import '../../domain/models/delivery_task.dart';
import '../../domain/models/delivery_task_details.dart';
import '../../domain/models/operational_failure.dart';
import '../../domain/repositories/delivery_repository.dart';
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
  int _readRevision = 0;

  @override
  AsyncValue<DeliveryTaskDetails> build() {
    final revision = ++_readRevision;
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(taskId)) {
      return const AsyncError(
        OperationalFailure(OperationalFailureCode.invalidData),
        StackTrace.empty,
      );
    }
    final sessionState = ref.watch(operationalSessionProvider);
    final failure = operationalSessionFailure(sessionState);
    if (failure != null) return AsyncError(failure, StackTrace.empty);
    if (sessionState.isLoading) return const AsyncLoading();
    final session = sessionState.requireValue;
    final repository = ref.watch(deliveryRepositoryProvider);
    // Initial reads and explicit rechecks share one revision fence. A late
    // initial response must never restore data after a newer denial.
    unawaited(
      Future<void>.microtask(() async {
        if (!_isCurrentRead(session, revision)) return;
        try {
          final details = await _readDetails(repository);
          if (_isCurrentRead(session, revision)) {
            state = AsyncData(_validateCurrentDetails(details));
          }
        } on Object catch (error, stack) {
          if (_isCurrentRead(session, revision)) {
            state = AsyncError(mapOperationalFailure(error), stack);
          }
        }
      }),
    );
    return const AsyncLoading();
  }

  bool _isCurrentRead(OperationalSession session, int revision) =>
      ref.mounted &&
      revision == _readRevision &&
      identical(ref.read(operationalSessionProvider).asData?.value, session);

  Future<DeliveryTaskDetails> _readDetails(DeliveryRepository repository) =>
      repository is DeliveryMapReader
      ? (repository as DeliveryMapReader).getMapTaskDetails(taskId)
      : repository.getTaskDetails(taskId);

  Future<void> refresh() async {
    if (!ref.mounted) return;
    try {
      await recheckAuthorizedDetails();
    } on Object {
      // The typed error is rendered in state; retry never reports success.
    }
  }

  /// Reads the task again immediately before copying contact data or opening
  /// an external application.  The returned snapshot is never taken from an
  /// old widget value.
  Future<DeliveryTaskDetails> recheckAuthorizedDetails() async {
    final revision = ++_readRevision;
    final sessionState = ref.read(operationalSessionProvider);
    final failure = operationalSessionFailure(sessionState);
    final session = sessionState.asData?.value;
    if (failure != null) {
      state = AsyncError(failure, StackTrace.current);
      throw failure;
    }
    if (session == null || session.userId == null) {
      throw const OperationalFailure(OperationalFailureCode.sessionExpired);
    }

    try {
      final repository = ref.read(deliveryRepositoryProvider);
      final details = await _readDetails(repository);
      if (!ref.mounted ||
          revision != _readRevision ||
          !identical(
            ref.read(operationalSessionProvider).asData?.value,
            session,
          )) {
        throw const OperationalFailure(OperationalFailureCode.sessionExpired);
      }
      final authorized = _validateCurrentDetails(details);
      state = AsyncData(authorized);
      return authorized;
    } on OperationalFailure catch (error, stack) {
      // Revoked access must remove the old recipient snapshot immediately.
      // Network failures keep only the previously authorized address for the
      // existing offline fallback, and never authorize an external action.
      if (ref.mounted &&
          revision == _readRevision &&
          identical(
            ref.read(operationalSessionProvider).asData?.value,
            session,
          ) &&
          error.code != OperationalFailureCode.network &&
          error.code != OperationalFailureCode.backendUnavailable) {
        state = AsyncError(error, stack);
      }
      rethrow;
    }
  }

  DeliveryTaskDetails _validateCurrentDetails(DeliveryTaskDetails details) {
    final task = details.task;
    if (task.taskId.toLowerCase() != taskId.toLowerCase() ||
        task.scope != DeliverySnapshotScope.current) {
      throw const OperationalFailure(OperationalFailureCode.staleAssignment);
    }
    final destination = task.destination;
    if (destination == null ||
        (destination.latitude != null &&
            (!destination.latitude!.isFinite ||
                destination.latitude!.abs() > 90)) ||
        (destination.longitude != null &&
            (!destination.longitude!.isFinite ||
                destination.longitude!.abs() > 180))) {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }
    return details;
  }

  Future<MapDirectionsOutcome> openDirections({
    DeliveryTaskSnapshot? expected,
    bool Function()? canLaunch,
  }) async {
    final capturedSession = ref.read(operationalSessionProvider).asData?.value;
    final details = await recheckAuthorizedDetails();
    if (!ref.mounted) {
      throw const OperationalFailure(OperationalFailureCode.sessionExpired);
    }
    final destination = details.task.destination!;
    if (expected != null && expected.destination != details.task.destination) {
      throw const OperationalFailure(OperationalFailureCode.staleAssignment);
    }
    // Re-check the epoch directly before handing the coordinate to an
    // external app.  No recipient address or phone is put in the URL.
    final session = ref.read(operationalSessionProvider).asData?.value;
    if (session == null ||
        !identical(session, capturedSession) ||
        session.userId == null ||
        session.failure != null ||
        canLaunch?.call() == false) {
      throw const OperationalFailure(OperationalFailureCode.sessionExpired);
    }
    if (!destination.hasValidCoordinates) {
      return MapDirectionsOutcome.invalidDestination;
    }
    return ref
        .read(mapNavigationAdapterProvider)
        .openLocation(_toSavedDestination(destination).location);
  }

  SavedDestination destinationFrom(DeliveryTaskDetails details) {
    _validateCurrentDetails(details);
    final task = details.task;
    if (task.scope != DeliverySnapshotScope.current ||
        task.destination == null) {
      throw const OperationalFailure(OperationalFailureCode.staleAssignment);
    }
    if (!task.destination!.hasValidCoordinates) {
      throw const OperationalFailure(OperationalFailureCode.invalidData);
    }
    return _toSavedDestination(task.destination!);
  }

  SavedDestination _toSavedDestination(DeliveryDestination destination) {
    return SavedDestination(
      latitude: destination.latitude!,
      longitude: destination.longitude!,
      label: destination.name,
      phone: destination.phone,
      address: destination.address,
    );
  }
}
