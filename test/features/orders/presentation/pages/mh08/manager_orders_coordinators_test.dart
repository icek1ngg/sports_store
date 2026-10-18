import 'package:flutter_test/flutter_test.dart';

import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/core/state/read_snapshot.dart';
import 'package:sports_store/features/orders/domain/models/order_page.dart';
import 'package:sports_store/features/orders/domain/models/order_query.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/presentation/view_models/mh08/mh08_feed_coordinator.dart';
import 'package:sports_store/features/orders/presentation/view_models/mh08/mh08_query_coordinator.dart';

import '../../../../../fixtures/order_list_page_fixtures.dart';

ReadSnapshot<OrderPage> _fresh(OrderPage page) => ReadSnapshot(data: page);

void main() {
  test(
    'ignores head and next responses from old query and session generations',
    () {
      final feed = Mh08FeedCoordinator();
      final first = listFixturePage(nextCursor: 'cursor-old', totalCount: 3);
      final late = listFixturePage(
        items: [
          listFixtureSummary(
            id: listFixtureSecondOrderId,
            status: OrderStatus.preparing,
          ),
        ],
        totalCount: 1,
      );

      expect(feed.consumeCanonical(feed.generation, _fresh(first)), isTrue);
      expect(feed.beginMore(canRead: true), isTrue);
      final oldQueryGeneration = feed.generation;
      feed.reset();

      expect(feed.generation, oldQueryGeneration + 1);
      expect(feed.consumeCanonical(oldQueryGeneration, _fresh(late)), isFalse);
      expect(
        feed.consumeNext(oldQueryGeneration, 'cursor-old', _fresh(late)),
        Mh08NextResult.ignored,
      );

      expect(feed.consumeCanonical(feed.generation, _fresh(first)), isTrue);
      expect(feed.beginMore(canRead: true), isTrue);
      final oldSessionGeneration = feed.generation;
      feed.reset(sessionChanged: true);

      expect(feed.generation, oldSessionGeneration + 1);
      expect(feed.canonicalPage, isNull);
      expect(feed.visibleRows(_fresh(late)), isEmpty);
      expect(
        feed.consumeCanonical(oldSessionGeneration, _fresh(late)),
        isFalse,
      );
      expect(
        feed.consumeNext(oldSessionGeneration, 'cursor-old', _fresh(late)),
        Mh08NextResult.ignored,
      );
      expect(feed.canonicalPage, isNull);
      expect(feed.privateDataFailure, isNull);

      expect(feed.consumeCanonical(feed.generation, _fresh(late)), isTrue);
      expect(feed.findSummary(listFixtureSecondOrderId), isNotNull);
    },
  );

  test('deduplicates next rows and keeps canonical counts and asOf', () {
    final feed = Mh08FeedCoordinator();
    final first = listFixturePage(
      nextCursor: 'cursor-one',
      totalCount: 7,
      counts: listFixtureCounts(pending: 4, delivering: 2),
    );
    final next = OrderPage(
      items: [
        listFixtureSummary(status: OrderStatus.preparing),
        listFixtureSummary(
          id: listFixtureSecondOrderId,
          status: OrderStatus.delivering,
        ),
      ],
      nextCursor: 'cursor-two',
      totalCount: 2,
      statusCounts: listFixtureCounts(delivering: 2),
      asOf: listFixtureTime.add(const Duration(minutes: 1)),
    );

    expect(feed.consumeCanonical(feed.generation, _fresh(first)), isTrue);
    expect(feed.beginMore(canRead: true), isTrue);
    expect(feed.beginMore(canRead: true), isFalse);
    expect(
      feed.consumeNext(feed.generation, 'cursor-one', _fresh(next)),
      Mh08NextResult.changed,
    );

    expect(feed.visibleRows(_fresh(first)), hasLength(2));
    expect(feed.canonicalPage!.totalCount, first.totalCount);
    expect(feed.canonicalPage!.statusCounts, first.statusCounts);
    expect(feed.canonicalPage!.asOf, first.asOf);
    expect(feed.nextCursor, 'cursor-two');
    expect(feed.canLoadMore, isTrue);

    expect(feed.beginMore(canRead: true), isTrue);
    expect(
      feed.consumeNext(
        feed.generation,
        'cursor-two',
        const ReadSnapshot(
          failure: AppFailure(code: AppFailure.externalDependencyUnavailable),
        ),
      ),
      Mh08NextResult.changed,
    );
    expect(feed.beginMore(canRead: true), isFalse);
    expect(feed.beginMore(canRead: true, force: true), isTrue);
  });

  test(
    'invalid cursor resets paging state and asks the page to refresh head',
    () {
      final feed = Mh08FeedCoordinator();
      final first = listFixturePage(nextCursor: 'cursor-invalid');
      expect(feed.consumeCanonical(feed.generation, _fresh(first)), isTrue);
      expect(feed.beginMore(canRead: true), isTrue);

      final result = feed.consumeNext(
        feed.generation,
        'cursor-invalid',
        const ReadSnapshot(failure: AppFailure(code: AppFailure.invalidCursor)),
      );
      expect(result, Mh08NextResult.refreshHead);
      expect(feed.canonicalFresh, isFalse);
      expect(feed.nextCursor, isNull);
      expect(feed.loadingMore, isFalse);
      expect(feed.moreFailure, isNull);
      expect(feed.visibleRows(_fresh(first)), hasLength(1));
    },
  );

  test(
    'next-page private failure hides all cached data until refresh succeeds',
    () {
      final feed = Mh08FeedCoordinator();
      final first = listFixturePage(
        nextCursor: 'cursor-private',
        totalCount: 9,
        counts: listFixtureCounts(pending: 5),
      );
      final replacement = listFixturePage(
        items: [
          listFixtureSummary(
            id: listFixtureThirdOrderId,
            status: OrderStatus.delivered,
          ),
        ],
        totalCount: 1,
      );
      expect(feed.consumeCanonical(feed.generation, _fresh(first)), isTrue);
      expect(feed.beginMore(canRead: true), isTrue);

      expect(
        feed.consumeNext(
          feed.generation,
          'cursor-private',
          const ReadSnapshot(
            failure: AppFailure(code: AppFailure.unauthenticated),
          ),
        ),
        Mh08NextResult.changed,
      );
      expect(feed.privateDataFailure!.code, AppFailure.unauthenticated);
      expect(feed.canonicalPage, isNull);
      expect(feed.visiblePage(_fresh(first)), isNull);
      expect(feed.visibleRows(_fresh(first)), isEmpty);
      expect(feed.effectiveSnapshot(_fresh(first)).failure, isNotNull);

      expect(
        feed.consumeCanonical(feed.generation, _fresh(replacement)),
        isFalse,
      );
      expect(feed.canonicalPage, isNull);
      feed.reset();
      expect(feed.privateDataFailure, isNotNull);
      expect(
        feed.consumeCanonical(feed.generation, _fresh(replacement)),
        isFalse,
      );

      feed.beginRefresh();
      expect(
        feed.consumeCanonical(feed.generation, _fresh(replacement)),
        isTrue,
      );
      expect(feed.privateDataFailure, isNull);
      expect(feed.visiblePage(_fresh(replacement))!.totalCount, 1);
    },
  );

  test(
    'stale head snapshot locks freshness while retaining the cached page',
    () {
      final feed = Mh08FeedCoordinator();
      final first = listFixturePage(nextCursor: 'cursor-stale');
      expect(feed.consumeCanonical(feed.generation, _fresh(first)), isTrue);
      expect(
        feed.consumeCanonical(
          feed.generation,
          ReadSnapshot(data: first, stale: true),
        ),
        isTrue,
      );
      expect(feed.canonicalFresh, isFalse);
      expect(feed.canLoadMore, isFalse);
      expect(feed.beginMore(canRead: true), isFalse);
      expect(feed.canonicalPage, same(first));

      expect(feed.consumeCanonical(feed.generation, _fresh(first)), isTrue);
      expect(feed.canonicalFresh, isTrue);
      expect(feed.canLoadMore, isTrue);
    },
  );

  testWidgets(
    'query coordinator debounces, trims, cancels pending edits and disposes',
    (tester) async {
      final query = Mh08QueryCoordinator();
      final applied = <OrderQuery>[];
      void apply(OrderQuery next) {
        applied.add(next);
        query.apply(next);
      }

      query.edit('first', apply);
      query.edit('  buyer  ', apply);
      await tester.pump(const Duration(milliseconds: 349));
      expect(applied, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(applied, hasLength(1));
      expect(applied.single.search, 'buyer');
      expect(query.query.search, 'buyer');

      final oversized = String.fromCharCodes(List.filled(201, 0x1f600));
      query.edit(oversized, apply);
      expect(query.error, 'Từ khóa tìm kiếm tối đa 200 ký tự Unicode.');
      await tester.pump(const Duration(milliseconds: 350));
      expect(applied, hasLength(1));

      query.edit('next', apply);
      query.dispose();
      await tester.pump(const Duration(milliseconds: 350));
      expect(applied, hasLength(1));
    },
  );

  testWidgets(
    'query clear cancels its timer and preserves the selected status',
    (tester) async {
      final query = Mh08QueryCoordinator();
      final applied = <OrderQuery>[];
      query.apply(
        OrderQuery(search: 'buyer', statuses: [OrderStatus.delivering]),
      );
      query.edit('pending', applied.add);
      final cleared = query.clear();

      expect(cleared.search, isNull);
      expect(cleared.statuses, [OrderStatus.delivering]);
      expect(query.value, isEmpty);
      expect(query.error, isNull);
      await tester.pump(const Duration(milliseconds: 350));
      expect(applied, isEmpty);
    },
  );
}
