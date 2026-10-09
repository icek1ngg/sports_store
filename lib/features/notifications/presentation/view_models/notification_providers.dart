import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/state/foundation_providers.dart';
import '../../../../core/state/read_snapshot.dart';
import '../../../../core/state/snapshot_read_view_model.dart';
import '../../domain/models/notification_page.dart';
import '../../domain/models/notification_query.dart';
import '../../domain/repositories/notification_repository.dart';

final notificationRepositoryProvider = Provider<NotificationRepository?>(
  (ref) => null,
);

final notificationPageFoundationProvider = AsyncNotifierProvider.autoDispose
    .family<
      NotificationPageFoundationViewModel,
      ReadSnapshot<NotificationPage>,
      NotificationQuery
    >(NotificationPageFoundationViewModel.new, retry: (count, error) => null);

final unreadCountFoundationProvider =
    AsyncNotifierProvider.autoDispose<
      UnreadCountFoundationViewModel,
      ReadSnapshot<int>
    >(UnreadCountFoundationViewModel.new, retry: (count, error) => null);

mixin _NotificationReadFailure<T extends Object> on SnapshotReadViewModel<T> {
  @override
  bool get scopeAllowed => true;
  @override
  AppFailure readFailure(Object error) => error is TimeoutException
      ? const AppFailure(
          code: AppFailure.network,
          messageKey: 'MSG-09',
          retryable: true,
        )
      : const AppFailure(code: AppFailure.unsupportedData);
  @override
  bool shouldClearPrivateData(AppFailure failure) =>
      failure.code == AppFailure.unauthenticated ||
      failure.code == AppFailure.forbiddenOrUnavailable;
}

class NotificationPageFoundationViewModel
    extends SnapshotReadViewModel<NotificationPage>
    with _NotificationReadFailure<NotificationPage> {
  NotificationPageFoundationViewModel(this.query);
  final NotificationQuery query;
  @override
  String get resourceKey =>
      'notifications/list/${query.filter.name}/${query.limit}/${query.cursor}';
  @override
  Future<NotificationPage> Function() configureLoader() {
    final repository = ref.watch(notificationRepositoryProvider);
    final scope = ref.watch(featureSessionScopeProvider);
    return () async {
      if (repository == null) {
        throw const AppFailure(code: AppFailure.externalDependencyUnavailable);
      }
      final page = await repository.getPage(query);
      if (page.items.any(
        (item) =>
            item.recipientId != scope.userId ||
            (query.filter == NotificationFilter.unread && item.isRead),
      )) {
        throw const AppFailure(code: AppFailure.unsupportedData);
      }
      return page;
    };
  }

  @override
  bool isEmpty(NotificationPage data) => data.items.isEmpty;
}

class UnreadCountFoundationViewModel extends SnapshotReadViewModel<int>
    with _NotificationReadFailure<int> {
  @override
  String get resourceKey => 'notifications/count';
  @override
  Future<int> Function() configureLoader() {
    final repository = ref.watch(notificationRepositoryProvider);
    return () async {
      if (repository == null) {
        throw const AppFailure(code: AppFailure.externalDependencyUnavailable);
      }
      final count = await repository.getUnreadCount();
      if (count < 0) throw const AppFailure(code: AppFailure.unsupportedData);
      return count;
    };
  }

  @override
  bool isEmpty(int data) => data == 0;
}
