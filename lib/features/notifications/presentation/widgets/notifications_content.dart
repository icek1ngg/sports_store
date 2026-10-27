import 'package:flutter/material.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../shared/widgets/async_content.dart';
import '../../domain/models/notification_query.dart';
import 'mh17/notification_filters.dart';

/// Screen layout and access-error presentation, without independent read state.
class NotificationsContent extends StatelessWidget {
  const NotificationsContent({
    required this.filter,
    required this.onFilterChanged,
    required this.onRefresh,
    required this.feed,
    this.failure,
    super.key,
  });
  final NotificationFilter filter;
  final ValueChanged<NotificationFilter> onFilterChanged;
  final VoidCallback onRefresh;
  final AppFailure? failure;
  final Widget feed;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Column(
      children: [
        Mh17NotificationFilters(
          selectedFilter: filter,
          onFilterChanged: onFilterChanged,
          onRefresh: onRefresh,
        ),
        Expanded(
          child: switch (failure?.code) {
            AppFailure.unauthenticated => const SessionExpiredState(
              actionLabel: null,
            ),
            AppFailure.forbiddenOrUnavailable => const SessionUnavailableState(
              actionLabel: null,
            ),
            _ => feed,
          },
        ),
      ],
    ),
  );
}
