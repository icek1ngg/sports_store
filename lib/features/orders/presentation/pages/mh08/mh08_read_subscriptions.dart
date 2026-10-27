import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/state/foundation_providers.dart';
import '../../../../../core/state/read_snapshot.dart';
import '../../../../../core/state/session_scope.dart';
import '../../../domain/models/order_page.dart';
import '../../../domain/models/order_query.dart';
import '../../view_models/mh08/mh08_feed_coordinator.dart';
import '../../view_models/order_providers.dart';
import '../../widgets/order_feed.dart';

/// Stateless subscription wiring. The page owns both state and callback lifetime.
ReadSnapshot<OrderPage> watchMh08Reads(
  WidgetRef ref, {
  required Mh08FeedCoordinator feed,
  required OrderQuery query,
  required bool Function() canAccept,
  required VoidCallback onSessionChanged,
  required void Function(int, ReadSnapshot<OrderPage>) onCanonical,
  required void Function(int, String, ReadSnapshot<OrderPage>) onNext,
}) {
  ref.watch(featureSessionScopeProvider);
  ref.listen<SessionScope>(featureSessionScopeProvider, (previous, next) {
    if (previous != next && canAccept()) onSessionChanged();
  });
  final generation = feed.generation;
  final canonicalQuery = query.copyWith(cursor: null);
  final canonical = orderListFoundationProvider(canonicalQuery);
  final snapshot = orderPageSnapshot(ref.watch(canonical));
  ref.listen<AsyncValue<ReadSnapshot<OrderPage>>>(canonical, (_, next) {
    if (canAccept()) onCanonical(generation, orderPageSnapshot(next));
  });
  if (feed.shouldSeed(snapshot)) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (canAccept() && feed.shouldSeed(snapshot)) {
        onCanonical(generation, snapshot);
      }
    });
  }
  final cursor = feed.nextCursor;
  if ((feed.loadingMore || feed.moreFailure != null) && cursor != null) {
    final provider = orderListFoundationProvider(
      canonicalQuery.copyWith(cursor: cursor),
    );
    final nextSnapshot = orderPageSnapshot(ref.watch(provider));
    ref.listen<AsyncValue<ReadSnapshot<OrderPage>>>(provider, (_, next) {
      if (canAccept()) onNext(generation, cursor, orderPageSnapshot(next));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (canAccept() && !nextSnapshot.loading) {
        onNext(generation, cursor, nextSnapshot);
      }
    });
  }
  return snapshot;
}

void refreshMh08NextAfterBuild(
  WidgetRef ref, {
  required Mh08FeedCoordinator feed,
  required OrderQuery query,
  required bool Function() canAccept,
}) {
  final cursor = feed.nextCursor;
  final generation = feed.generation;
  if (cursor == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!canAccept() ||
        generation != feed.generation ||
        !feed.loadingMore ||
        feed.nextCursor != cursor) {
      return;
    }
    unawaited(
      ref
          .read(
            orderListFoundationProvider(query.copyWith(cursor: cursor))
                .notifier,
          )
          .refresh(),
    );
  });
}
