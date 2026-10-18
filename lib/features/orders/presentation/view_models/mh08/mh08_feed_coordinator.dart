import '../../../../../core/errors/app_failure.dart';
import '../../../../../core/state/read_snapshot.dart';
import '../../../domain/models/order_page.dart';
import '../../../domain/models/order_summary.dart';

/// Page-owned state and transitions for the MH08 paginated order feed.
///
/// The page remains responsible for lifecycle guards, provider subscriptions
/// and rebuilding. This object only preserves the feed's existing acceptance,
/// pagination and private-data isolation rules.
class Mh08FeedCoordinator {
  OrderPage? get canonicalPage => _canonicalPage;
  bool get canonicalFresh => _canonicalFresh;
  bool get hideCanonicalSnapshot => _hideCanonicalSnapshot;
  AppFailure? get privateDataFailure => _privateDataFailure;
  bool get privateRefreshRequested => _privateRefreshRequested;
  int get generation => _generation;
  String? get nextCursor => _nextCursor;
  AppFailure? get moreFailure => _moreFailure;
  bool get loadingMore => _loadingMore;

  bool get canLoadMore =>
      _canonicalFresh && _nextCursor != null && !_loadingMore;

  OrderPage? _canonicalPage;
  final _rows = <OrderSummary>[];
  final _cursorHistory = <String>[];
  final _processedNextPages = <String, OrderPage>{};
  String? _nextCursor;
  AppFailure? _moreFailure;
  bool _loadingMore = false;
  bool _canonicalFresh = false;
  bool _hideCanonicalSnapshot = false;
  AppFailure? _privateDataFailure;
  bool _privateRefreshRequested = false;
  var _generation = 0;

  /// Resets query-owned state. Session resets also clear an access failure.
  void reset({bool sessionChanged = false}) {
    _generation++;
    _canonicalPage = null;
    _canonicalFresh = false;
    _hideCanonicalSnapshot = true;
    if (sessionChanged) _privateDataFailure = null;
    _privateRefreshRequested = false;
    _rows.clear();
    _resetExtraCursors();
  }

  /// Marks the canonical read stale while allowing a response to clear a
  /// previously recorded private-data failure.
  void beginRefresh() {
    _canonicalFresh = false;
    _privateRefreshRequested = true;
    _resetExtraCursors();
  }

  /// Accepts a settled canonical snapshot for the current query generation.
  bool consumeCanonical(
    int responseGeneration,
    ReadSnapshot<OrderPage> snapshot,
  ) {
    if (responseGeneration != _generation) return false;
    final page = snapshot.data;
    final failure = snapshot.failure;
    if (_isPrivateDataFailure(failure)) {
      return _clearPrivateData(failure!);
    }
    if (_privateDataFailure != null && !_privateRefreshRequested) return false;
    if (snapshot.loading || snapshot.stale || failure != null) {
      if (!_canonicalFresh) return false;
      _canonicalFresh = false;
      return true;
    }
    if (page == null || (_canonicalFresh && identical(page, _canonicalPage))) {
      return false;
    }
    _canonicalPage = page;
    _canonicalFresh = true;
    _hideCanonicalSnapshot = false;
    _privateDataFailure = null;
    _privateRefreshRequested = false;
    _rows
      ..clear()
      ..addAll(page.items);
    _nextCursor = page.nextCursor;
    _cursorHistory.clear();
    _processedNextPages.clear();
    _moreFailure = null;
    _loadingMore = false;
    return true;
  }

  /// Accepts a settled next-page snapshot for the cursor currently requested.
  Mh08NextResult consumeNext(
    int responseGeneration,
    String cursor,
    ReadSnapshot<OrderPage> snapshot,
  ) {
    if (responseGeneration != _generation || cursor != _nextCursor) {
      return Mh08NextResult.ignored;
    }
    final failure = snapshot.failure;
    if (failure != null) {
      if (_isPrivateDataFailure(failure)) {
        return _clearPrivateData(failure)
            ? Mh08NextResult.changed
            : Mh08NextResult.ignored;
      }
      if (failure.code == AppFailure.invalidCursor) {
        _canonicalFresh = false;
        _resetExtraCursors();
        return Mh08NextResult.refreshHead;
      }
      if (!_loadingMore) return Mh08NextResult.ignored;
      _loadingMore = false;
      _moreFailure = failure;
      return Mh08NextResult.changed;
    }
    final page = snapshot.data;
    if (page == null ||
        snapshot.loading ||
        snapshot.stale ||
        identical(page, _processedNextPages[cursor])) {
      return Mh08NextResult.ignored;
    }
    _processedNextPages[cursor] = page;
    final byId = <String, OrderSummary>{
      for (final row in _rows) row.order.id: row,
    };
    for (final row in page.items) {
      byId[row.order.id] = row;
    }
    _rows
      ..clear()
      ..addAll(byId.values);
    _nextCursor = page.nextCursor == cursor ? null : page.nextCursor;
    _loadingMore = false;
    _moreFailure = null;
    return Mh08NextResult.changed;
  }

  /// Starts a load-more request when the current canonical page permits it.
  bool beginMore({required bool canRead, bool force = false}) {
    if (!canRead || !_canonicalFresh || _loadingMore) return false;
    final cursor = _nextCursor;
    if (cursor == null || (!force && _cursorHistory.contains(cursor))) {
      return false;
    }
    _cursorHistory.add(cursor);
    _moreFailure = null;
    _loadingMore = true;
    return true;
  }

  ReadSnapshot<OrderPage> effectiveSnapshot(ReadSnapshot<OrderPage> raw) {
    final privateFailure =
        _privateDataFailure ??
        (_isPrivateDataFailure(raw.failure) ? raw.failure : null);
    if (privateFailure != null) {
      return ReadSnapshot<OrderPage>(failure: privateFailure);
    }
    if (_hideCanonicalSnapshot) {
      return const ReadSnapshot<OrderPage>(loading: true);
    }
    return raw;
  }

  OrderPage? visiblePage(ReadSnapshot<OrderPage> raw) {
    final effective = effectiveSnapshot(raw);
    if (_isPrivateDataUnavailable(effective)) return null;
    return _canonicalPage ?? effective.data;
  }

  List<OrderSummary> visibleRows(ReadSnapshot<OrderPage> raw) {
    final effective = effectiveSnapshot(raw);
    if (_isPrivateDataUnavailable(effective)) return const <OrderSummary>[];
    if (_rows.isEmpty && effective.data != null) return effective.data!.items;
    return List<OrderSummary>.unmodifiable(_rows);
  }

  bool shouldSeed(ReadSnapshot<OrderPage> raw) =>
      _privateDataFailure == null &&
      !_hideCanonicalSnapshot &&
      _canonicalPage == null &&
      raw.isFresh;

  OrderSummary? findSummary(String orderId) {
    for (final item in _rows) {
      if (item.order.id == orderId) return item;
    }
    for (final item in _canonicalPage?.items ?? const <OrderSummary>[]) {
      if (item.order.id == orderId) return item;
    }
    return null;
  }

  void _resetExtraCursors() {
    _nextCursor = null;
    _cursorHistory.clear();
    _processedNextPages.clear();
    _moreFailure = null;
    _loadingMore = false;
  }

  bool _hasPrivateState() =>
      !_hideCanonicalSnapshot ||
      _privateDataFailure == null ||
      _canonicalPage != null ||
      _rows.isNotEmpty ||
      _canonicalFresh ||
      _nextCursor != null ||
      _cursorHistory.isNotEmpty ||
      _processedNextPages.isNotEmpty ||
      _moreFailure != null ||
      _loadingMore;

  bool _clearPrivateData(AppFailure failure) {
    if (!_hasPrivateState()) return false;
    _canonicalPage = null;
    _canonicalFresh = false;
    _hideCanonicalSnapshot = true;
    _privateDataFailure = failure;
    _privateRefreshRequested = false;
    _rows.clear();
    _resetExtraCursors();
    return true;
  }

  bool _isPrivateDataFailure(AppFailure? failure) =>
      failure?.code == AppFailure.unauthenticated ||
      failure?.code == AppFailure.forbiddenOrUnavailable;

  bool _isPrivateDataUnavailable(ReadSnapshot<OrderPage> snapshot) =>
      _hideCanonicalSnapshot || _isPrivateDataFailure(snapshot.failure);
}

enum Mh08NextResult { ignored, changed, refreshHead }
