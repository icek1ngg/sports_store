import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/notifications/domain/models/notification_item.dart';
import 'package:sports_store/features/notifications/domain/models/notification_page.dart';
import 'package:sports_store/features/notifications/domain/models/notification_query.dart';
import 'package:sports_store/features/notifications/presentation/view_models/mh17/notification_feed_coordinator.dart';

NotificationItem row(
  int number, {
  String title = 'Thông báo',
  bool read = false,
}) {
  final suffix = number.toString().padLeft(12, '0');
  final event = '20000000-0000-4000-8000-$suffix';
  return NotificationItem(
    id: '10000000-0000-4000-8000-$suffix',
    recipientId: '30000000-0000-4000-8000-000000000001',
    eventId: event,
    subjectType: NotificationSubjectType.notificationOnly,
    subjectId: event,
    title: title,
    body: 'Nội dung được máy chủ cung cấp',
    readAt: read ? DateTime.utc(2026, 10, 21, 9) : null,
    createdAt: DateTime.utc(2026, 10, 21, 8),
  );
}

NotificationPage page(List<NotificationItem> rows, [String? cursor]) =>
    NotificationPage(
      items: rows,
      nextCursor: cursor,
      unreadCount: 99,
      asOf: DateTime.utc(2026, 10, 21, 10),
    );

void main() {
  late NotificationFeedCoordinator feed;
  setUp(() => feed = NotificationFeedCoordinator(revision: 1));

  void head(List<NotificationItem> rows, [String? cursor = 'c1']) {
    expect(feed.acceptHead(revision: 1, page: page(rows, cursor)), isTrue);
  }

  test('initial state has no private payload, cursor or fabricated count', () {
    expect(feed.revision, 1);
    expect(feed.filter, NotificationFilter.all);
    expect(feed.items, isEmpty);
    expect(feed.nextCursor, isNull);
    expect(feed.activeCursor, isNull);
    expect(feed.hasAcceptedHead, isFalse);
    expect(feed.hasMore, isFalse);
    expect(feed.isLoadingMore, isFalse);
    expect(feed.needsLoadMoreRetry, isFalse);
  });
  test('accepts canonical head order and object identity without sorting', () {
    final first = row(2);
    final second = row(1);
    head([first, second]);
    expect(feed.items, [same(first), same(second)]);
    expect(feed.nextCursor, 'c1');
    expect(feed.hasAcceptedHead, isTrue);
    expect(feed.hasMore, isTrue);
  });
  test('head duplicate keeps first position and latest projection', () {
    final updated = row(1, title: 'Mới', read: true);
    head([row(1), row(2), updated]);
    expect(feed.items.map((item) => item.id), [updated.id, row(2).id]);
    expect(feed.items.first, same(updated));
  });
  test('tail appends new rows after accepted head', () {
    head([row(1)]);
    expect(feed.beginLoadMore(revision: 1, requestId: 1), 'c1');
    expect(feed.isLoadingMore, isTrue);
    expect(
      feed.acceptTail(revision: 1, requestId: 1, page: page([row(2)], 'c2')),
      isTrue,
    );
    expect(feed.items.map((item) => item.id), [row(1).id, row(2).id]);
    expect(feed.nextCursor, 'c2');
    expect(feed.isLoadingMore, isFalse);
  });
  test('tail duplicate replaces once in place; latest accepted value wins', () {
    final replacement = row(1, title: 'Đã cập nhật', read: true);
    final latest = row(3, title: 'Cuối cùng');
    head([row(1), row(2)]);
    feed.beginLoadMore(revision: 1, requestId: 1);
    feed.acceptTail(
      revision: 1,
      requestId: 1,
      page: page([row(3), replacement, latest, row(2)], 'c2'),
    );
    expect(feed.items.map((item) => item.id), [
      row(1).id,
      row(2).id,
      row(3).id,
    ]);
    expect(feed.items.first, same(replacement));
    expect(feed.items.last, same(latest));
  });
  test('server unread count is not inferred or copied into local rows', () {
    final canonical = page([row(1)]).copyWith(unreadCount: 999);
    feed.acceptHead(revision: 1, page: canonical);
    expect(canonical.unreadCount, 999);
    expect(feed.items.length, 1);
    expect(feed.items.single.isRead, isFalse);
    expect(feed.hasMore, isFalse);
  });
  test(
    'filter reset clears rows instead of client filtering a partial page',
    () {
      head([row(1), row(2, read: true)]);
      expect(
        feed.reset(revision: 2, filter: NotificationFilter.unread),
        isTrue,
      );
      expect(feed.filter, NotificationFilter.unread);
      expect(feed.items, isEmpty);
      expect(feed.nextCursor, isNull);
      expect(feed.acceptHead(revision: 2, page: page([row(3)])), isTrue);
      expect(feed.items.single.id, row(3).id);
    },
  );
  test('constructor supports current query filter without deriving rows', () {
    feed = NotificationFeedCoordinator(
      revision: 4,
      filter: NotificationFilter.unread,
    );
    expect(feed.filter, NotificationFilter.unread);
    expect(feed.items, isEmpty);
  });
  test('same-owner refresh retains rows until new head supersedes tail', () {
    head([row(1)]);
    feed.beginLoadMore(revision: 1, requestId: 1);
    feed.acceptTail(revision: 1, requestId: 1, page: page([row(2)], 'c2'));
    expect(feed.refreshHead(revision: 2), isTrue);
    expect(feed.items.length, 2);
    expect(feed.hasAcceptedHead, isFalse);
    expect(feed.nextCursor, isNull);
    expect(feed.beginLoadMore(revision: 2, requestId: 1), isNull);
    feed.acceptHead(revision: 2, page: page([row(3)], 'fresh'));
    expect(feed.items.single.id, row(3).id);
    expect(feed.nextCursor, 'fresh');
  });
  test(
    'old tail cannot restore discarded data before or after refreshed head',
    () {
      head([row(1)]);
      feed.beginLoadMore(revision: 1, requestId: 1);
      feed.refreshHead(revision: 2);
      expect(
        feed.acceptTail(revision: 1, requestId: 1, page: page([row(9)])),
        isFalse,
      );
      expect(feed.items.single.id, row(1).id);
      feed.acceptHead(revision: 2, page: page([row(2)], 'new'));
      expect(
        feed.acceptTail(revision: 1, requestId: 1, page: page([row(9)])),
        isFalse,
      );
      expect(feed.items.single.id, row(2).id);
      expect(feed.nextCursor, 'new');
    },
  );
  test('old query head and duplicate current head are rejected unchanged', () {
    head([row(1)]);
    expect(feed.acceptHead(revision: 0, page: page([row(9)])), isFalse);
    expect(feed.acceptHead(revision: 1, page: page([row(9)])), isFalse);
    expect(feed.items.single.id, row(1).id);
    expect(feed.nextCursor, 'c1');
  });
  test(
    'failure preserves rows and retry intent; never retries automatically',
    () {
      head([row(1)]);
      final accepted = feed.items;
      feed.beginLoadMore(revision: 1, requestId: 10);
      expect(feed.recordLoadMoreFailure(revision: 1, requestId: 10), isTrue);
      expect(feed.items, same(accepted));
      expect(feed.activeCursor, 'c1');
      expect(feed.nextCursor, 'c1');
      expect(feed.isLoadingMore, isFalse);
      expect(feed.needsLoadMoreRetry, isTrue);
      expect(feed.beginLoadMore(revision: 1, requestId: 11), isNull);
      expect(feed.retryLoadMore(revision: 1, requestId: 11), 'c1');
      expect(feed.isLoadingMore, isTrue);
      expect(feed.needsLoadMoreRetry, isFalse);
    },
  );
  test(
    'retry rejects reused request and late earlier completion or failure',
    () {
      head([row(1)]);
      feed.beginLoadMore(revision: 1, requestId: 5);
      feed.recordLoadMoreFailure(revision: 1, requestId: 5);
      expect(feed.retryLoadMore(revision: 1, requestId: 5), isNull);
      expect(feed.retryLoadMore(revision: 0, requestId: 6), isNull);
      expect(feed.needsLoadMoreRetry, isTrue);
      expect(feed.retryLoadMore(revision: 1, requestId: 6), 'c1');
      expect(
        feed.acceptTail(revision: 1, requestId: 5, page: page([row(9)])),
        isFalse,
      );
      expect(feed.recordLoadMoreFailure(revision: 1, requestId: 5), isFalse);
      expect(feed.isLoadingMore, isTrue);
      expect(
        feed.acceptTail(revision: 1, requestId: 6, page: page([row(2)])),
        isTrue,
      );
      expect(
        feed.acceptTail(revision: 1, requestId: 6, page: page([row(9)])),
        isFalse,
      );
      expect(feed.items.map((item) => item.id), [row(1).id, row(2).id]);
    },
  );
  test('begin rejects no head, busy, obsolete revision and reused intent', () {
    expect(feed.beginLoadMore(revision: 1, requestId: 1), isNull);
    head([row(1)]);
    expect(feed.beginLoadMore(revision: 0, requestId: 1), isNull);
    expect(feed.beginLoadMore(revision: 1, requestId: 2), 'c1');
    expect(feed.beginLoadMore(revision: 1, requestId: 3), isNull);
    expect(
      feed.acceptTail(revision: 1, requestId: 3, page: page([row(9)])),
      isFalse,
    );
    expect(feed.recordLoadMoreFailure(revision: 0, requestId: 2), isFalse);
    feed.acceptTail(revision: 1, requestId: 2, page: page([row(2)], 'c2'));
    expect(feed.beginLoadMore(revision: 1, requestId: 2), isNull);
    expect(feed.beginLoadMore(revision: 1, requestId: 3), 'c2');
  });
  test('self cursor is terminal after merging accepted tail', () {
    head([row(1)]);
    feed.beginLoadMore(revision: 1, requestId: 1);
    feed.acceptTail(revision: 1, requestId: 1, page: page([row(2)], 'c1'));
    expect(feed.items.length, 2);
    expect(feed.hasMore, isFalse);
    expect(feed.beginLoadMore(revision: 1, requestId: 2), isNull);
  });
  test('previously issued cursor stops a multi-page cycle', () {
    head([row(1)]);
    feed.beginLoadMore(revision: 1, requestId: 1);
    feed.acceptTail(revision: 1, requestId: 1, page: page([row(2)], 'c2'));
    feed.beginLoadMore(revision: 1, requestId: 2);
    feed.acceptTail(revision: 1, requestId: 2, page: page([row(3)], 'c1'));
    expect(feed.items.length, 3);
    expect(feed.nextCursor, isNull);
    expect(feed.hasMore, isFalse);
  });
  test('null cursor alone exhausts pagination regardless of row count', () {
    head([row(1)], null);
    expect(feed.hasMore, isFalse);
    expect(feed.beginLoadMore(revision: 1, requestId: 1), isNull);
    feed.reset(revision: 2);
    feed.acceptHead(revision: 2, page: page([], 'next'));
    expect(feed.items, isEmpty);
    expect(feed.hasMore, isTrue);
    expect(feed.beginLoadMore(revision: 2, requestId: 1), 'next');
  });
  test(
    'owner reset clears rows, history and pending tickets; old inputs fail',
    () {
      head([row(1)]);
      feed.beginLoadMore(revision: 1, requestId: 8);
      expect(feed.reset(revision: 2), isTrue);
      expect(feed.items, isEmpty);
      expect(feed.nextCursor, isNull);
      expect(feed.activeCursor, isNull);
      expect(feed.isLoadingMore, isFalse);
      expect(feed.needsLoadMoreRetry, isFalse);
      expect(feed.hasAcceptedHead, isFalse);
      expect(feed.acceptHead(revision: 1, page: page([row(9)])), isFalse);
      expect(
        feed.acceptTail(revision: 1, requestId: 8, page: page([row(9)])),
        isFalse,
      );
      expect(feed.items, isEmpty);
      feed.acceptHead(revision: 2, page: page([row(2)], 'c1'));
      expect(feed.beginLoadMore(revision: 2, requestId: 1), 'c1');
      feed.acceptTail(revision: 2, requestId: 1, page: page([], 'c2'));
      expect(feed.nextCursor, 'c2');
    },
  );
  test('nonincreasing resets and refreshes cannot change accepted state', () {
    head([row(1)]);
    feed.beginLoadMore(revision: 1, requestId: 1);
    final snapshot = feed.items;
    expect(feed.reset(revision: 1, filter: NotificationFilter.unread), isFalse);
    expect(feed.reset(revision: 0), isFalse);
    expect(feed.refreshHead(revision: 1), isFalse);
    expect(feed.refreshHead(revision: 0), isFalse);
    expect(feed.items, same(snapshot));
    expect(feed.filter, NotificationFilter.all);
    expect(feed.isLoadingMore, isTrue);
    expect(feed.activeCursor, 'c1');
  });
  test('items are immutable snapshots after head and tail replacement', () {
    head([row(1)]);
    final old = feed.items;
    expect(() => old.add(row(9)), throwsUnsupportedError);
    feed.beginLoadMore(revision: 1, requestId: 1);
    feed.acceptTail(revision: 1, requestId: 1, page: page([row(2)]));
    expect(() => feed.items.clear(), throwsUnsupportedError);
    expect(() => feed.items[0] = row(9), throwsUnsupportedError);
    expect(old.single.id, row(1).id);
    expect(feed.items.length, 2);
  });
  test('load and failure never optimistically mutate readAt', () {
    final unread = row(1);
    head([unread]);
    feed.beginLoadMore(revision: 1, requestId: 1);
    feed.recordLoadMoreFailure(revision: 1, requestId: 1);
    feed.retryLoadMore(revision: 1, requestId: 2);
    expect(feed.items.single, same(unread));
    expect(unread.readAt, isNull);
    final canonical = row(1, read: true);
    feed.refreshHead(revision: 2);
    feed.acceptHead(revision: 2, page: page([canonical]));
    expect(feed.items.single, same(canonical));
    expect(unread.readAt, isNull);
  });
  test('stale presentation retention grants no action or freshness authority', () {
    head([row(1)]);
    // Owner withholds stale input; coordinator has no timer or permission API.
    feed.refreshHead(revision: 2);
    expect(feed.items.single.id, row(1).id);
    expect(feed.hasAcceptedHead, isFalse);
    expect(feed.hasMore, isFalse);
    expect(feed.retryLoadMore(revision: 2, requestId: 1), isNull);
    feed.reset(revision: 3);
    expect(feed.items, isEmpty);
  });
  test(
    'two head refreshes reject intermediate responses deterministically',
    () {
      head([row(1)]);
      feed.refreshHead(revision: 2);
      feed.refreshHead(revision: 3);
      expect(
        feed.acceptHead(revision: 2, page: page([row(9)], 'old')),
        isFalse,
      );
      expect(feed.acceptHead(revision: 3, page: page([row(3)], 'new')), isTrue);
      expect(feed.items.single.id, row(3).id);
      expect(feed.nextCursor, 'new');
    },
  );
  test('synchronous replay yields the same rows and cursor without IO', () {
    List<Object?> replay() {
      final local = NotificationFeedCoordinator(revision: 1);
      expect(local.acceptHead(revision: 1, page: page([row(1)], 'c1')), isTrue);
      expect(local.beginLoadMore(revision: 1, requestId: 1), 'c1');
      expect(
        local.acceptTail(revision: 1, requestId: 1, page: page([row(2)])),
        isTrue,
      );
      return [
        local.items.map((item) => item.toMap()).toList(),
        local.nextCursor,
      ];
    }

    expect(replay(), replay());
  });

  for (final cursor in ['', List.filled(2049, 'x').join()]) {
    test(
      'F02 raw ${cursor.isEmpty ? 'empty' : 'oversized'} cursor is not normalized',
      () {
        head([row(1)], cursor);
        expect(feed.nextCursor, cursor);
        expect(feed.hasMore, isTrue);
        expect(feed.beginLoadMore(revision: 1, requestId: 1), cursor);
        expect(feed.activeCursor, cursor);
        // No NotificationQuery is constructed; malformed integration stays F02.
        expect(feed.recordLoadMoreFailure(revision: 1, requestId: 1), isTrue);
        expect(feed.retryLoadMore(revision: 1, requestId: 2), cursor);
      },
    );
  }
}
