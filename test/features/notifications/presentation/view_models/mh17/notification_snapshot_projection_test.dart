import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/core/state/epoch_cache.dart';
import 'package:sports_store/core/state/read_snapshot.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/notifications/domain/models/notification_page.dart';
import 'package:sports_store/features/notifications/domain/models/notification_query.dart';
import 'package:sports_store/features/notifications/presentation/view_models/mh17/notification_snapshot_projection.dart';

const ownerId = '30000000-0000-4000-8000-000000000001';
const owner = SessionScope(userId: ownerId, role: 'customer', generation: 1);

void main() {
  late EpochCache cache;
  late NotificationQuery query;
  late NotificationPage page;
  late ReadSnapshot<NotificationPage> snapshot;

  void acceptPage(NotificationQuery key, NotificationPage value) {
    final resource = NotificationSnapshotProjection.resourceKey(key);
    expect(cache.accept(cache.begin(resource), value), isTrue);
  }

  bool interact({
    SessionScope scope = owner,
    EpochCache? liveCache,
    bool active = true,
    AppFailure? failure,
    String? acceptedKey,
    ReadSnapshot<NotificationPage>? input,
  }) => NotificationSnapshotProjection.canInteract(
    isActive: active,
    accessFailure: failure,
    scope: scope,
    cache: liveCache ?? cache,
    query: query,
    acceptedScope: owner,
    acceptedCache: cache,
    acceptedQueryKey:
        acceptedKey ?? NotificationSnapshotProjection.queryKey(query),
    snapshot: input ?? snapshot,
  );

  setUp(() {
    cache = EpochCache(owner);
    query = NotificationQuery();
    page = NotificationPage(
      items: const [],
      nextCursor: 'opaque-next',
      unreadCount: 23,
      asOf: DateTime.utc(2026, 10, 22, 1),
    );
    snapshot = ReadSnapshot(data: page);
    acceptPage(query, page);
  });

  tearDown(() => cache.dispose());

  test('head and tail identity keys preserve current page conventions', () {
    expect(NotificationSnapshotProjection.queryKey(query), 'all/20/');
    expect(
      NotificationSnapshotProjection.resourceKey(query),
      'notifications/list/all/20/null',
    );
    final tail = NotificationQuery(
      filter: NotificationFilter.unread,
      limit: 7,
      cursor: 'opaque+/=token',
    );
    expect(
      NotificationSnapshotProjection.queryKey(tail),
      'unread/7/opaque+/=token',
    );
    expect(
      NotificationSnapshotProjection.resourceKey(tail),
      'notifications/list/unread/7/opaque+/=token',
    );
    expect(tail.cursor, 'opaque+/=token');
  });

  test('any-filter head resource detection preserves existing behavior', () {
    for (final resource in [
      'notifications/list/all/20/null',
      'notifications/list/unread/20/',
      'notifications/list/all/20/null/extra',
    ]) {
      expect(
        NotificationSnapshotProjection.isFirstPageResource(resource),
        true,
      );
    }
    for (final resource in [
      'notifications/count',
      'other/list/all/20/null',
      'notifications/list/all/20',
      'notifications/list/all/20/tail',
    ]) {
      expect(
        NotificationSnapshotProjection.isFirstPageResource(resource),
        false,
      );
    }
  });

  test(
    'page matching requires cached aggregate identity, not equal contents',
    () {
      expect(
        NotificationSnapshotProjection.matchesPage(cache, query, snapshot),
        true,
      );
      final other = NotificationPage(
        items: const [],
        nextCursor: page.nextCursor,
        unreadCount: page.unreadCount,
        asOf: page.asOf,
      );
      expect(
        NotificationSnapshotProjection.matchesPage(
          cache,
          query,
          ReadSnapshot(data: other),
        ),
        false,
      );
      expect(
        NotificationSnapshotProjection.matchesPage(
          cache,
          query,
          const ReadSnapshot(),
        ),
        false,
      );
      expect(
        NotificationSnapshotProjection.matchesPage(
          cache,
          NotificationQuery(filter: NotificationFilter.unread),
          snapshot,
        ),
        false,
      );
    },
  );

  test(
    'count matching is canonical and independent of empty page and metadata',
    () {
      expect(page.items, isEmpty);
      expect(page.unreadCount, 23);
      expect(
        NotificationSnapshotProjection.matchesCount(
          cache,
          const ReadSnapshot(data: 0),
        ),
        false,
      );
      expect(cache.accept(cache.begin('notifications/count'), 901), true);
      expect(
        NotificationSnapshotProjection.matchesCount(
          cache,
          const ReadSnapshot(data: 901),
        ),
        true,
      );
      expect(
        NotificationSnapshotProjection.matchesCount(
          cache,
          const ReadSnapshot(data: 23),
        ),
        false,
      );
      expect(cache.accept(cache.begin('notifications/count'), 0), true);
      expect(
        NotificationSnapshotProjection.matchesCount(
          cache,
          const ReadSnapshot(data: 0),
        ),
        true,
      );
      expect(
        NotificationSnapshotProjection.matchesCount(
          cache,
          const ReadSnapshot(),
        ),
        false,
      );
    },
  );

  test(
    'fresh current head enables preflight without mutating cache or input',
    () {
      expect(interact(), true);
      expect(interact(), true);
      expect(
        cache
            .read<NotificationPage>(
              NotificationSnapshotProjection.resourceKey(query),
            )!
            .data,
        same(page),
      );
      expect(snapshot.data, same(page));
      expect(page.nextCursor, 'opaque-next');
      expect(page.unreadCount, 23);
    },
  );

  for (final scope in [
    const SessionScope.unresolved(),
    const SessionScope(userId: null, role: null, generation: 2),
    const SessionScope(userId: ownerId, role: 'customer', generation: 2),
    const SessionScope(userId: ownerId, role: 'unknown', generation: 1),
    const SessionScope(
      userId: '30000000-0000-4000-8000-000000000002',
      role: 'customer',
      generation: 1,
    ),
  ]) {
    test(
      'changed/unavailable namespace fails closed: ${scope.userId}/${scope.role}/${scope.generation}',
      () {
        expect(NotificationSnapshotProjection.canRender(scope, cache), false);
        expect(interact(scope: scope), false);
        expect(
          snapshot.data,
          same(page),
        ); // Retained old input is not authority.
      },
    );
  }

  for (final role in ['customer', 'manager', 'shipper']) {
    test('supported $role scope renders only with matching cache', () {
      final scope = SessionScope(
        userId: owner.userId,
        role: role,
        generation: 3,
      );
      final live = EpochCache(scope);
      expect(NotificationSnapshotProjection.canRender(scope, live), true);
      expect(NotificationSnapshotProjection.canRender(scope, cache), false);
      live.dispose();
    });
  }

  test('same-scope replacement cache cannot reuse old acceptance receipt', () {
    final replacement = EpochCache(owner);
    final key = NotificationSnapshotProjection.resourceKey(query);
    replacement.accept(replacement.begin(key), page);
    expect(NotificationSnapshotProjection.canRender(owner, replacement), true);
    expect(interact(liveCache: replacement), false);
    replacement.dispose();
  });

  test('missing or mismatched accepted receipt cannot enable preflight', () {
    expect(interact(acceptedKey: 'unread/20/'), false);
    expect(
      NotificationSnapshotProjection.receiptMatches(
        scope: owner,
        cache: cache,
        acceptedScope: null,
        acceptedCache: null,
        query: query,
        acceptedQueryKey: null,
      ),
      false,
    );
  });

  test('tail action needs a current fresh head even when tail is fresh', () {
    query = NotificationQuery(cursor: 'tail');
    acceptPage(query, page);
    expect(interact(), true);
    cache.invalidate(
      NotificationSnapshotProjection.resourceKey(NotificationQuery()),
    );
    expect(interact(), false);
  });

  test('tail without a cached head fails closed', () {
    cache.forget(NotificationSnapshotProjection.resourceKey(query));
    query = NotificationQuery(cursor: 'tail');
    acceptPage(query, page);
    expect(interact(), false);
  });

  test(
    'stale cache may match for presentation but cannot authorize interaction',
    () {
      cache.invalidate(NotificationSnapshotProjection.resourceKey(query));
      expect(
        NotificationSnapshotProjection.matchesPage(cache, query, snapshot),
        true,
      );
      expect(interact(), false);
    },
  );

  for (final input in [
    ReadSnapshot<NotificationPage>(loading: true),
    ReadSnapshot<NotificationPage>(stale: true),
    ReadSnapshot<NotificationPage>(
      failure: AppFailure(code: AppFailure.network),
    ),
  ]) {
    test(
      'nonfresh snapshot rejects actions: ${input.loading}/${input.stale}/${input.failure?.code}',
      () {
        expect(
          interact(
            input: ReadSnapshot(
              data: page,
              loading: input.loading,
              stale: input.stale,
              failure: input.failure,
            ),
          ),
          false,
        );
      },
    );
  }

  test('missing snapshot rejects actions', () {
    expect(interact(input: const ReadSnapshot()), false);
  });

  test(
    'owner disposal and access latch both reject otherwise fresh inputs',
    () {
      expect(interact(active: false), false);
      expect(
        interact(failure: const AppFailure(code: AppFailure.unauthenticated)),
        false,
      );
    },
  );

  for (final dispose in [false, true]) {
    test(
      'same-object cache ${dispose ? 'dispose' : 'block'} rejects retained private inputs synchronously',
      () {
        if (dispose) {
          cache.dispose();
        } else {
          cache.blockSession();
        }
        expect(NotificationSnapshotProjection.canRender(owner, cache), false);
        expect(
          NotificationSnapshotProjection.matchesPage(cache, query, snapshot),
          false,
        );
        expect(interact(), false);
      },
    );
  }

  test(
    'only canonical access failure categories trigger access classification',
    () {
      for (final code in [
        AppFailure.unauthenticated,
        AppFailure.forbiddenOrUnavailable,
      ]) {
        expect(
          NotificationSnapshotProjection.isAccessFailure(
            AppFailure(code: code),
          ),
          true,
        );
      }
      for (final failure in [
        null,
        const AppFailure(code: AppFailure.network),
        const AppFailure(code: AppFailure.invalidCursor),
      ]) {
        expect(NotificationSnapshotProjection.isAccessFailure(failure), false);
      }
    },
  );
}
