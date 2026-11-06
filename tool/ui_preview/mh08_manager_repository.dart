import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/features/orders/domain/models/order_details.dart';
import 'package:sports_store/features/orders/domain/models/order_page.dart';
import 'package:sports_store/features/orders/domain/models/order_query.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';
import 'package:sports_store/features/orders/domain/models/order_summary.dart';

import 'mh07_preview_data.dart';
import 'mh08_manager_cursor.dart';
import 'mh08_manager_data.dart';
import 'mh08_manager_record.dart';

enum Mh08PreviewScenario {
  data,
  loading,
  empty,
  error,
  stale,
  expired,
  unauthorized,
  sessionUnavailable,
}

class Mh08ManagerRepository extends PreviewOrderRepository {
  Mh08ManagerRepository({int pageSize = 3}) : super(pageSize: pageSize) {
    if (pageSize < 1 || pageSize > 100) {
      throw ArgumentError.value(
        pageSize,
        'pageSize',
        'must be between 1 and 100',
      );
    }
  }

  final _cursor = Mh08ManagerCursor();
  final List<Mh08ManagerRecord> _managerRecords = buildMh08ManagerRecords();
  final _managerReads = <OrderQuery>[];
  final _managerDetailReads = <String>[];
  Mh08PreviewScenario _managerScenario = Mh08PreviewScenario.data;
  int _revision = 0;
  int _scopeGeneration = 0;
  int _readNumber = 0;
  bool failNextPageOnce = false;

  Mh08PreviewScenario get managerScenario => _managerScenario;
  List<OrderQuery> get managerReads => List.unmodifiable(_managerReads);
  List<String> get managerDetailReads => List.unmodifiable(_managerDetailReads);
  List<OrderSummary> get summaries =>
      List.unmodifiable(_managerRecords.map((record) => record.summary));
  void failNextPageForDemo() => failNextPageOnce = true;

  void setManagerScenario(Mh08PreviewScenario value) {
    _managerScenario = value;
    _revision++;
    _scopeGeneration++;
    _readNumber = 0;
    failNextPageOnce = false;
  }

  @override
  Future<OrderPage> getManagerOrders(OrderQuery query) async {
    _managerReads.add(query);
    final read = await _beginRead();
    final source = read.scenario == Mh08PreviewScenario.empty
        ? const <Mh08ManagerRecord>[]
        : _managerRecords;
    final matching = _search(source, query.search);
    final counts = _statusCounts(matching);
    final filtered = query.statuses.isEmpty
        ? matching
        : matching
              .where((record) => query.statuses.contains(record.order.status))
              .toList(growable: false);
    final offset = _cursor.decode(query, read.scopeGeneration);
    if (offset > filtered.length) {
      throw const AppFailure(code: AppFailure.invalidCursor);
    }
    if (query.cursor != null && failNextPageOnce) {
      failNextPageOnce = false;
      throw const AppFailure(code: AppFailure.network, retryable: true);
    }
    final take = pageSize < query.limit ? pageSize : query.limit;
    final items = filtered
        .skip(offset)
        .take(take)
        .map((record) => record.summary)
        .toList(growable: false);
    final nextOffset = offset + items.length;
    return OrderPage(
      items: items,
      nextCursor: nextOffset < filtered.length
          ? _cursor.encode(query, nextOffset, read.scopeGeneration)
          : null,
      totalCount: filtered.length,
      statusCounts: counts,
      asOf: mh08PreviewAsOf,
    );
  }

  @override
  Future<OrderDetails> getOrderDetails(String orderId) async {
    _managerDetailReads.add(orderId);
    final read = await _beginRead();
    if (read.scenario == Mh08PreviewScenario.empty) _notAvailable();
    return canonicalDetails(orderId);
  }

  /// Immutable debug seed lookup; transport/session behavior remains above.
  OrderDetails canonicalDetails(String orderId) {
    final record = _managerRecords.cast<Mh08ManagerRecord?>().firstWhere(
      (candidate) => candidate!.order.id == orderId,
      orElse: () => null,
    );
    if (record == null) _notAvailable();
    return record.details;
  }

  Future<_ReadContext> _beginRead() async {
    final scenario = _managerScenario;
    final revision = _revision;
    final scopeGeneration = _scopeGeneration;
    final readNumber = ++_readNumber;
    await Future<void>.delayed(
      scenario == Mh08PreviewScenario.loading
          ? const Duration(milliseconds: 800)
          : Duration.zero,
    );
    if (revision != _revision || scenario != _managerScenario) {
      throw const AppFailure(code: AppFailure.network, retryable: true);
    }
    switch (scenario) {
      case Mh08PreviewScenario.error:
        throw const AppFailure(code: AppFailure.network, retryable: true);
      case Mh08PreviewScenario.stale:
        if (readNumber > 1) {
          throw const AppFailure(code: AppFailure.network, retryable: true);
        }
      case Mh08PreviewScenario.expired:
        throw const AppFailure(code: AppFailure.unauthenticated);
      case Mh08PreviewScenario.unauthorized:
        throw const AppFailure(code: AppFailure.forbiddenOrUnavailable);
      case Mh08PreviewScenario.sessionUnavailable:
        throw const AppFailure(code: AppFailure.externalDependencyUnavailable);
      case Mh08PreviewScenario.data:
      case Mh08PreviewScenario.loading:
      case Mh08PreviewScenario.empty:
        break;
    }
    return _ReadContext(scenario, scopeGeneration);
  }

  List<Mh08ManagerRecord> _search(
    Iterable<Mh08ManagerRecord> source,
    String? rawSearch,
  ) {
    final search = Mh08ManagerCursor.normalizeSearch(rawSearch);
    if (search == null) return source.toList(growable: false);
    return source
        .where((record) {
          final id = record.order.id.toLowerCase();
          final account =
              Mh08ManagerCursor.normalizeSearch(record.accountName) ?? '';
          return id == search || account.contains(search);
        })
        .toList(growable: false);
  }

  Map<OrderStatus, int> _statusCounts(Iterable<Mh08ManagerRecord> source) {
    final counts = <OrderStatus, int>{
      for (final status in OrderStatus.values) status: 0,
    };
    for (final record in source) {
      counts[record.order.status] = counts[record.order.status]! + 1;
    }
    return counts;
  }

  Never _notAvailable() =>
      throw const AppFailure(code: AppFailure.forbiddenOrUnavailable);
}

class _ReadContext {
  const _ReadContext(this.scenario, this.scopeGeneration);
  final Mh08PreviewScenario scenario;
  final int scopeGeneration;
}
