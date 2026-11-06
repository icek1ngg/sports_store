import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/cod/domain/models/cod_collection.dart';
import 'package:sports_store/features/cod/domain/models/cod_collection_page.dart';
import 'package:sports_store/features/cod/domain/models/cod_collection_query.dart';
import 'package:sports_store/features/cod/domain/repositories/cod_repository.dart';
import 'package:sports_store/features/cod/presentation/view_models/cod_providers.dart';
import 'package:sports_store/features/cod/presentation/view_models/shipper_cod_view_model.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';

const _shipperA = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _shipperB = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _orderA = '11111111-1111-4111-8111-111111111111';
const _orderB = '22222222-2222-4222-8222-222222222222';

class _Repo implements CodRepository {
  final requests = <CodCollectionQuery>[];
  final responses =
      <FutureOr<CodCollectionPage> Function(CodCollectionQuery)>[];

  @override
  Future<CodCollectionPage> queryCollections(CodCollectionQuery query) async {
    requests.add(query);
    if (responses.isEmpty) throw StateError('missing fixture response');
    return responses.removeAt(0)(query);
  }

  @override
  Future<List<CodCollection>> listCollections({
    String? shipperId,
    String? orderId,
  }) => throw UnimplementedError();
}

OperationalSession _session(String userId, int generation) =>
    OperationalSession(userId: userId, generation: generation);

CodCollection _row({
  String orderId = _orderA,
  String shipperId = _shipperA,
  CodStatus status = CodStatus.collected,
  int receivedAmount = 0,
}) {
  final now = DateTime.utc(2026, 10, 25, 8);
  return CodCollection(
    orderId: orderId,
    orderCode: orderId,
    orderCodeSource: 'order_uuid',
    shipperId: shipperId,
    status: status,
    expectedAmountVnd: 550000,
    collectedAmountVnd: 550000,
    receivedAmountVnd: receivedAmount,
    collectedBy: shipperId,
    receivedBy: status == CodStatus.received ? _shipperB : null,
    collectedAt: now,
    handedOverAt: status == CodStatus.received ? now : null,
    receivedAt: status == CodStatus.received ? now : null,
    createdAt: now,
    updatedAt: now,
  );
}

List<CodCollection> _sortedCollectedRows({
  int count = 100,
}) => List<CodCollection>.generate(
  count,
  (index) => _row(
    orderId:
        'eeeeeeee-eeee-4eee-8eee-${(count - index).toRadixString(16).padLeft(12, '0')}',
  ),
);

CodCollectionPage _page(
  List<CodCollection> items, {
  int? filteredTotal,
  int? all,
  int? collected,
  int? received,
  int outstanding = 550000,
  String? nextCursor,
}) {
  final total = filteredTotal ?? items.length;
  final totalCollected =
      collected ??
      items.where((item) => item.status == CodStatus.collected).length;
  final totalReceived =
      received ??
      items.where((item) => item.status == CodStatus.received).length;
  final totalAll = all ?? total;
  return CodCollectionPage(
    items: items,
    nextCursor: nextCursor,
    filteredTotal: total,
    counts: CodCollectionCounts(
      all: totalAll,
      uncollected: totalAll - totalCollected - totalReceived,
      collected: totalCollected,
      received: totalReceived,
    ),
    outstandingVnd: outstanding,
    asOf: DateTime.utc(2026, 10, 25, 8),
  );
}

Future<void> _settle(ProviderContainer container, dynamic provider) async {
  for (var index = 0; index < 100; index++) {
    await Future<void>.delayed(Duration.zero);
    container.read(provider);
    if (!container.read(provider).isLoading) return;
  }
  fail('shipper COD provider did not settle');
}

ProviderContainer _container({
  required _Repo repository,
  required Stream<OperationalSession> sessions,
}) {
  return ProviderContainer(
    overrides: [
      codRepositoryProvider.overrideWithValue(repository),
      operationalSessionProvider.overrideWith((ref) => sessions),
    ],
  );
}

void main() {
  test('loads only own unreconciled rows and server held total', () async {
    final repo = _Repo()
      ..responses.add((query) {
        expect(query.shipperId, _shipperA);
        expect(query.statuses, [CodStatus.collected]);
        return _page(
          [_row(orderId: _orderB), _row()],
          all: 3,
          collected: 2,
          received: 1,
          outstanding: 1100000,
        );
      });
    final container = _container(
      repository: repo,
      sessions: Stream.value(_session(_shipperA, 1)),
    );
    final provider = shipperCodViewModelProvider(null);
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() {
      subscription.close();
      container.dispose();
    });

    await _settle(container, provider);
    final state = container.read(provider);
    expect(state.group, ShipperCodGroup.unreconciled);
    expect(state.items, hasLength(2));
    expect(
      state.items.every((item) => item.status == CodStatus.collected),
      isTrue,
    );
    expect(state.heldTotalVnd, 1100000);
    expect(state.filteredTotal, 2);
    expect(state.error, isNull);
  });

  test(
    'switches to reconciled group through the server status filter',
    () async {
      final repo = _Repo()
        ..responses.add((_) => _page([_row()]))
        ..responses.add((query) {
          expect(query.statuses, [CodStatus.received]);
          return _page([
            _row(status: CodStatus.received, receivedAmount: 550000),
          ], outstanding: 550000);
        });
      final container = _container(
        repository: repo,
        sessions: Stream.value(_session(_shipperA, 1)),
      );
      final provider = shipperCodViewModelProvider(null);
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(() {
        subscription.close();
        container.dispose();
      });

      await _settle(container, provider);
      await container
          .read(provider.notifier)
          .setGroup(ShipperCodGroup.reconciled);
      await _settle(container, provider);
      final state = container.read(provider);
      expect(state.group, ShipperCodGroup.reconciled);
      expect(state.items.single.status, CodStatus.received);
      expect(state.heldTotalVnd, 550000);
      expect(repo.requests.map((query) => query.statuses), [
        [CodStatus.collected],
        [CodStatus.received],
      ]);
    },
  );

  test('honors the optional order filter without local filtering', () async {
    final repo = _Repo()
      ..responses.add((query) {
        expect(query.orderId, _orderB);
        return _page([_row(orderId: _orderB)]);
      });
    final container = _container(
      repository: repo,
      sessions: Stream.value(_session(_shipperA, 1)),
    );
    final provider = shipperCodViewModelProvider(_orderB);
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() {
      subscription.close();
      container.dispose();
    });

    await _settle(container, provider);
    expect(container.read(provider).items.single.orderId, _orderB);
  });

  test('rejects a response row outside the optional order filter', () async {
    final repo = _Repo()
      ..responses.add((query) {
        expect(query.orderId, _orderB);
        return _page([_row(orderId: _orderA)]);
      });
    final container = _container(
      repository: repo,
      sessions: Stream.value(_session(_shipperA, 1)),
    );
    final provider = shipperCodViewModelProvider(_orderB);
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() {
      subscription.close();
      container.dispose();
    });

    await _settle(container, provider);
    final state = container.read(provider);
    expect(state.items, isEmpty);
    expect(state.error?.code, OperationalFailureCode.invalidData);
  });

  test('wrong-shipper response is denied and clears records', () async {
    final repo = _Repo()
      ..responses.add((_) => _page([_row(shipperId: _shipperB)]));
    final container = _container(
      repository: repo,
      sessions: Stream.value(_session(_shipperA, 1)),
    );
    final provider = shipperCodViewModelProvider(null);
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() {
      subscription.close();
      container.dispose();
    });

    await _settle(container, provider);
    final state = container.read(provider);
    expect(state.items, isEmpty);
    expect(state.error?.code, OperationalFailureCode.permissionDenied);
  });

  test(
    'load-more keeps server totals and preserves rows on network error',
    () async {
      final firstItems = _sortedCollectedRows();
      final repo = _Repo()
        ..responses.add(
          (_) => _page(
            firstItems,
            filteredTotal: 101,
            all: 101,
            collected: 101,
            nextCursor: 'next',
            outstanding: 55550000,
          ),
        )
        ..responses.add((query) {
          expect(query.cursor, 'next');
          throw const OperationalFailure(OperationalFailureCode.network);
        });
      final container = _container(
        repository: repo,
        sessions: Stream.value(_session(_shipperA, 1)),
      );
      final provider = shipperCodViewModelProvider(null);
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(() {
        subscription.close();
        container.dispose();
      });

      await _settle(container, provider);
      await container.read(provider.notifier).loadMore();
      final state = container.read(provider);
      expect(state.items, hasLength(100));
      expect(state.heldTotalVnd, 55550000);
      expect(state.loadMoreError?.code, OperationalFailureCode.network);
      expect(state.error, isNull);
    },
  );

  test('rejects a page that breaks the global created-at/order sort', () async {
    final firstItems = _sortedCollectedRows();
    final repo = _Repo()
      ..responses.add(
        (_) => _page(
          firstItems,
          filteredTotal: 101,
          all: 101,
          collected: 101,
          nextCursor: 'next',
          outstanding: 55550000,
        ),
      )
      ..responses.add((query) {
        expect(query.cursor, 'next');
        return _page(
          [_row(orderId: firstItems.first.orderId)],
          filteredTotal: 101,
          all: 101,
          collected: 101,
          outstanding: 55550000,
        );
      });
    final container = _container(
      repository: repo,
      sessions: Stream.value(_session(_shipperA, 1)),
    );
    final provider = shipperCodViewModelProvider(null);
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() {
      subscription.close();
      container.dispose();
    });

    await _settle(container, provider);
    await container.read(provider.notifier).loadMore();
    final state = container.read(provider);
    expect(state.items, hasLength(100));
    expect(state.loadMoreError?.code, OperationalFailureCode.invalidData);
    expect(state.error, isNull);
  });

  test('bounds one consistency reset for terminal total drift', () async {
    final firstItems = _sortedCollectedRows();
    CodCollectionPage firstPage() => _page(
      firstItems,
      filteredTotal: 101,
      all: 101,
      collected: 101,
      nextCursor: 'next',
      outstanding: 55550000,
    );
    CodCollectionPage driftPage() => _page(
      const [],
      filteredTotal: 101,
      all: 101,
      collected: 101,
      outstanding: 55550000,
    );
    final repo = _Repo()
      ..responses.add((_) => firstPage())
      ..responses.add((query) {
        expect(query.cursor, 'next');
        return driftPage();
      })
      ..responses.add((query) {
        expect(query.cursor, isNull);
        return firstPage();
      })
      ..responses.add((query) {
        expect(query.cursor, 'next');
        return driftPage();
      });
    final container = _container(
      repository: repo,
      sessions: Stream.value(_session(_shipperA, 1)),
    );
    final provider = shipperCodViewModelProvider(null);
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() {
      subscription.close();
      container.dispose();
    });

    await _settle(container, provider);
    await container.read(provider.notifier).loadMore();
    expect(container.read(provider).items, hasLength(100));
    expect(container.read(provider).error, isNull);
    expect(repo.requests, hasLength(3));

    await container.read(provider.notifier).loadMore();
    final state = container.read(provider);
    expect(state.items, isEmpty);
    expect(state.error?.code, OperationalFailureCode.invalidData);
    expect(state.nextCursor, isNull);
  });

  test('late response after account switch cannot publish old data', () async {
    final first = Completer<CodCollectionPage>();
    final repo = _Repo()
      ..responses.add((_) => first.future)
      ..responses.add(
        (_) => _page([_row(orderId: _orderB, shipperId: _shipperB)]),
      );
    final sessions = StreamController<OperationalSession>.broadcast();
    final container = _container(repository: repo, sessions: sessions.stream);
    final provider = shipperCodViewModelProvider(null);
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await sessions.close();
    });
    sessions.add(_session(_shipperA, 1));
    await Future<void>.delayed(Duration.zero);
    sessions.add(_session(_shipperB, 2));
    await Future<void>.delayed(Duration.zero);
    first.complete(_page([_row()]));
    for (var index = 0; index < 100; index++) {
      await Future<void>.delayed(Duration.zero);
      final state = container.read(provider);
      if (!state.isLoading && state.items.isNotEmpty) break;
    }
    final state = container.read(provider);
    expect(state.items, hasLength(1));
    expect(state.items.single.orderId, _orderB);
    expect(state.items.single.shipperId, _shipperB);
    expect(state.error, isNull);
  });

  test(
    'late response after a rapid group switch cannot publish old rows',
    () async {
      final first = Completer<CodCollectionPage>();
      final second = Completer<CodCollectionPage>();
      final repo = _Repo()
        ..responses.add((_) => first.future)
        ..responses.add((_) => second.future);
      final container = _container(
        repository: repo,
        sessions: Stream.value(_session(_shipperA, 1)),
      );
      final provider = shipperCodViewModelProvider(null);
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(() {
        subscription.close();
        container.dispose();
      });

      for (var index = 0; index < 100 && repo.requests.isEmpty; index++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(repo.requests, hasLength(1));

      final groupChange = container
          .read(provider.notifier)
          .setGroup(ShipperCodGroup.reconciled);
      for (var index = 0; index < 100 && repo.requests.length < 2; index++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(repo.requests, hasLength(2));
      expect(repo.requests.last.statuses, [CodStatus.received]);
      second.complete(
        _page([_row(status: CodStatus.received, receivedAmount: 550000)]),
      );
      await groupChange;
      first.complete(_page([_row()]));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(provider);
      expect(state.group, ShipperCodGroup.reconciled);
      expect(state.items.single.status, CodStatus.received);
      expect(state.error, isNull);
    },
  );
}
