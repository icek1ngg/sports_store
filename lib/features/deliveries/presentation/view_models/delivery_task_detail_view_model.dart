import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/operational_providers.dart';
import '../../domain/models/delivery_task_details.dart';
import 'delivery_providers.dart';

/// Read-only state holder for MH11.
///
/// The repository and [deliveryTaskDetailsProvider] remain the single source
/// of truth for authorization, session epochs, and mapping failures.  This
/// ViewModel only adapts that provider to the screen-facing notifier API and
/// exposes a scoped refresh/retry operation.  It deliberately has no write
/// actions and does not subscribe to auth independently.
final deliveryTaskDetailViewModelProvider = NotifierProvider.autoDispose
    .family<
      DeliveryTaskDetailViewModel,
      AsyncValue<DeliveryTaskDetails>,
      String
    >(DeliveryTaskDetailViewModel.new);

class DeliveryTaskDetailViewModel
    extends Notifier<AsyncValue<DeliveryTaskDetails>> {
  DeliveryTaskDetailViewModel(this.taskId);

  int _buildRevision = 0;
  Completer<void>? _activeRefreshCancellation;

  /// The route/task key for this provider instance.  It is never placed in a
  /// URL by this ViewModel and is only used to select the authorized read
  /// projection.
  final String taskId;

  @override
  AsyncValue<DeliveryTaskDetails> build() {
    final buildRevision = ++_buildRevision;
    // Riverpod invokes onDispose before a dependency-triggered rebuild as
    // well as on final autoDispose teardown. Defer the cancellation check so
    // a normal rebuild from this ViewModel's own refresh gets a new revision
    // first; only a genuinely disposed provider cancels the refresh Future.
    ref.onDispose(() {
      if (_activeRefreshCancellation == null) return;
      scheduleMicrotask(() {
        if (_buildRevision == buildRevision) {
          final cancellation = _activeRefreshCancellation;
          if (cancellation != null && !cancellation.isCompleted) {
            cancellation.complete();
          }
        }
      });
    });

    // The underlying provider drops previous values on reload and auth-epoch
    // changes.  Applying the same normalization here makes that invariant
    // explicit at the screen boundary as well.
    return withoutPreviousOperationalData(
      ref.watch(deliveryTaskDetailsProvider(taskId)),
    );
  }

  /// Re-fetches this task detail only.
  ///
  /// The old projection is cleared before invalidation so a task from the
  /// previous assignment/account cannot remain visible while the authorized
  /// read is being rechecked.  Errors are surfaced by the existing provider;
  /// no success value is manufactured here.
  Future<void> refresh() async {
    if (!ref.mounted) return;

    // Preserve the same session gate as the public projection.  In
    // particular, do not set a terminally signed-out view to synthetic
    // loading and then read the private FutureProvider: that could issue an
    // unauthorized RPC and would hide the typed expiry/permission state.
    final sessionState = ref.read(operationalSessionProvider);
    final sessionFailure = operationalSessionFailure(sessionState);
    state = sessionFailure == null
        ? const AsyncLoading()
        : AsyncError(sessionFailure, StackTrace.empty);
    final cancellation = Completer<void>();
    final previousCancellation = _activeRefreshCancellation;
    if (previousCancellation != null && !previousCancellation.isCompleted) {
      previousCancellation.complete();
    }
    _activeRefreshCancellation = cancellation;
    try {
      await refreshDeliveryTaskDetails(
        ref,
        taskId,
        lifecycleCancellation: cancellation.future,
      );
    } finally {
      if (identical(_activeRefreshCancellation, cancellation)) {
        _activeRefreshCancellation = null;
      }
    }
  }
}
