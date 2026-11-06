import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/operational_read_access.dart';
import '../../data/repositories/operational_providers.dart';
import '../../data/repositories/supabase_delivery_repository.dart';
import '../../domain/models/delivery_task.dart';
import '../../domain/models/delivery_task_details.dart';
import '../../domain/models/operational_failure.dart';
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

/// Invalidates only the authorized detail request for [taskId].
///
/// The public detail provider is a projection over a private,
/// session-keyed FutureProvider.  Invalidating the projection alone can
/// otherwise reuse the FutureProvider's cached value.  ViewModels use this
/// helper for pull-to-refresh/retry so the task read is actually reissued,
/// while MH10/list providers and the operational auth stream remain intact.
Future<void> refreshDeliveryTaskDetails(
  Ref ref,
  String taskId, {
  Future<void>? lifecycleCancellation,
}) async {
  final session = ref.read(operationalSessionProvider).asData?.value;
  // A terminal auth/session state is already represented by the public
  // projection.  Do not bypass that guard by reading the private
  // session-keyed FutureProvider directly: doing so would issue an
  // unauthorized RPC after logout/expiry.
  if (session == null || session.userId == null || session.failure != null) {
    ref.invalidate(deliveryTaskDetailsProvider(taskId));
    // Rebuilding the public projection is scheduled by Riverpod.  Give that
    // projection one turn to publish the typed session failure before the
    // refresh Future completes; the ViewModel must not leave the screen in a
    // synthetic loading state after logout/expiry.
    await Future<void>.delayed(Duration.zero);
    return;
  }

  final detailsProvider = _detailsForSessionProvider((session, taskId));
  // Install the epoch guard before invalidating either provider so a session
  // event that races with invalidation cannot be missed between those steps.
  final superseded = Completer<void>();
  // Listen from the container rather than the ViewModel Ref. A `ref.listen`
  // subscription is removed when the Notifier rebuilds in response to the
  // invalidation below, which would miss the next account epoch while this
  // refresh is still awaiting the old request.
  final sessionSubscription = ref.container
      .listen<AsyncValue<OperationalSession>>(operationalSessionProvider, (
        previous,
        next,
      ) {
        final nextSession = next.asData?.value;
        if (nextSession == null ||
            !_sameOperationalSession(session, nextSession)) {
          if (!superseded.isCompleted) superseded.complete();
        }
      }, fireImmediately: true);

  // Keep pull-to-refresh/retry pending until this exact authorized read
  // settles.  The ViewModel deliberately does not assign the result after
  // this await: an auth/session epoch change may have replaced this provider
  // while the request was in flight, and its watched projection owns the
  // only safe state update.
  try {
    // The immediate listener callback can observe a newer session than the
    // value captured above. Do not even start the superseded private read.
    if (superseded.isCompleted) {
      ref.invalidate(deliveryTaskDetailsProvider(taskId));
      return;
    }

    // Invalidate the session-keyed FutureProvider as well as its public
    // projection. Invalidating only the latter can reuse the cached future.
    ref.invalidate(detailsProvider);
    ref.invalidate(deliveryTaskDetailsProvider(taskId));
    if (superseded.isCompleted) return;

    final waits = <Future<void>>[
      ref.read(detailsProvider.future),
      superseded.future,
      ?lifecycleCancellation,
    ];
    await Future.any<void>(waits);
  } catch (_) {
    // The public projection observes the same future and exposes the mapped
    // failure.  Re-throwing here would make a UI RefreshIndicator surface an
    // uncaught duplicate error instead of rendering its error state.
  } finally {
    sessionSubscription.close();
  }
}

bool _sameOperationalSession(OperationalSession a, OperationalSession b) {
  // OperationalSession is also part of the private FutureProvider family
  // key, which uses object identity. A fresh auth/session object can carry
  // the same user and generation after client reinitialization while still
  // representing a different authorization epoch.
  return identical(a, b);
}

/// Write reconciliation uses the SAME backing future as MH11, rather than
/// mutating a local snapshot or invalidating only the public projection.
Future<DeliveryTaskDetails> refetchDeliveryTaskAfterCommand(
  Ref ref,
  String taskId,
) async {
  final sessionState = ref.read(operationalSessionProvider);
  final failure = operationalSessionFailure(sessionState);
  final session = sessionState.asData?.value;
  if (failure != null) throw failure;
  if (session == null || session.userId == null) {
    throw const OperationalFailure(OperationalFailureCode.sessionExpired);
  }
  final backing = _detailsForSessionProvider((session, taskId));
  ref.invalidate(backing);
  ref.invalidate(deliveryTaskDetailsProvider(taskId));
  final details = await ref.read(backing.future);
  if (!ref.mounted ||
      !identical(ref.read(operationalSessionProvider).asData?.value, session)) {
    throw const OperationalFailure(OperationalFailureCode.sessionExpired);
  }
  return details;
}

void invalidateLegacyDeliveryTaskReads(Ref ref) {
  ref.invalidate(_tasksForSessionProvider);
}
