import 'package:flutter/material.dart';

import '../../../../../shared/widgets/async_content.dart';
import '../../../domain/models/notification_item.dart';
import '../../../domain/models/notification_query.dart';
import '../notification_tile.dart';

/// Controlled feed presentation. The owner supplies authorized snapshots and
/// nullable callbacks, including disabling actions when access or freshness is lost.
/// Place in a bounded height; this widget owns no cursor, cache, read or route state.
class Mh17NotificationFeed extends StatelessWidget {
  Mh17NotificationFeed({
    required List<NotificationItem> items,
    required this.hasData,
    this.filter = NotificationFilter.all,
    this.isInitialLoading = false,
    this.isRefreshing = false,
    this.isStale = false,
    this.errorMessage,
    this.onRetry,
    this.onRefresh,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.loadMoreErrorMessage,
    this.onLoadMore,
    this.onOpen,
    this.onMarkRead,
    Set<String> pendingReadIds = const <String>{},
    super.key,
  }) : items = List<NotificationItem>.unmodifiable(items),
       pendingReadIds = Set<String>.unmodifiable(pendingReadIds);

  final List<NotificationItem> items;
  final bool hasData;
  final NotificationFilter filter;
  final bool isInitialLoading;
  final bool isRefreshing;
  final bool isStale;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final Future<void> Function()? onRefresh;
  final bool hasMore;
  final bool isLoadingMore;
  final String? loadMoreErrorMessage;
  final VoidCallback? onLoadMore;
  final ValueChanged<NotificationItem>? onOpen;
  final ValueChanged<NotificationItem>? onMarkRead;
  final Set<String> pendingReadIds;

  @override
  Widget build(BuildContext context) {
    final list = ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == items.length) return _pagination(context);
        final item = items[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: NotificationTile(
            key: ValueKey(item.id),
            notification: item,
            isPendingRead: pendingReadIds.contains(item.id),
            onTap: onOpen == null ? null : () => onOpen!(item),
            onMarkRead: item.isRead || onMarkRead == null
                ? null
                : () => onMarkRead!(item),
          ),
        );
      },
    );
    return AsyncContent(
      hasData: hasData,
      isInitialLoading: isInitialLoading,
      isRefreshing: isRefreshing,
      isEmpty: items.isEmpty,
      isStale: isStale,
      errorMessage: errorMessage,
      onRetry: onRetry,
      emptyMessage: filter == NotificationFilter.unread
          ? 'Không có thông báo chưa đọc'
          : 'Chưa có thông báo',
      child: onRefresh == null
          ? list
          : RefreshIndicator(onRefresh: onRefresh!, child: list),
    );
  }

  Widget _pagination(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loadMoreErrorMessage != null) ...[
            Text(loadMoreErrorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
          ],
          if (isLoadingMore)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                semanticsLabel: 'Đang tải thêm thông báo',
              ),
            )
          else
            OutlinedButton(
              onPressed: onLoadMore,
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(
                loadMoreErrorMessage == null ? 'Tải thêm' : 'Thử lại',
              ),
            ),
        ],
      ),
    );
  }
}
