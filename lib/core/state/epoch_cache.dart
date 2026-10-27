import 'session_scope.dart';

/// A token is local response ordering evidence, not a backend version.
class ReadToken {
  const ReadToken._(
    this.scope,
    this.resource,
    this.epoch,
    this.queryGeneration,
    this.requestGeneration,
  );
  final SessionScope scope;
  final String resource;
  final int epoch;
  final int queryGeneration;
  final int requestGeneration;
}

class CachedSnapshot<T> {
  const CachedSnapshot(this.data, {required this.stale});
  final T data;
  final bool stale;
}

/// One owner for accepted aggregate reads in a single Auth session namespace.
/// Lists, details and notification counts use distinct resource keys.
/// There is intentionally no method accepting a mutation receipt.
class EpochCache {
  EpochCache(this.scope);
  final SessionScope scope;
  final _epochs = <String, int>{};
  final _requests = <String, int>{};
  final _queries = <String, int>{};
  final _data = <String, Object>{};
  final _stale = <String>{};
  final _listeners = <void Function(String)>[];
  bool _disposed = false;
  bool _blocked = false;
  bool get canRead => !_disposed && !_blocked && scope.canReadPrivateData;

  ReadToken begin(String resource, {int queryGeneration = 0}) {
    _queries[resource] = queryGeneration;
    final request = (_requests[resource] ?? 0) + 1;
    _requests[resource] = request;
    return ReadToken._(
      scope,
      resource,
      _epochs[resource] ?? 0,
      queryGeneration,
      request,
    );
  }

  bool isCurrent(ReadToken token) =>
      canRead &&
      token.scope == scope &&
      token.epoch == (_epochs[token.resource] ?? 0) &&
      token.queryGeneration == _queries[token.resource] &&
      token.requestGeneration == _requests[token.resource];

  bool accept<T extends Object>(ReadToken token, T aggregate) {
    if (!isCurrent(token)) return false;
    _data[token.resource] = aggregate;
    _stale.remove(token.resource);
    return true;
  }

  CachedSnapshot<T>? read<T>(String resource) {
    if (!canRead) return null;
    final value = _data[resource];
    if (value is! T) return null;
    return CachedSnapshot<T>(value, stale: _stale.contains(resource));
  }

  void invalidate(String resource) {
    if (_disposed) return;
    _epochs[resource] = (_epochs[resource] ?? 0) + 1;
    _stale.add(resource);
    for (final listener in List.of(_listeners)) {
      listener(resource);
    }
  }

  void invalidatePrefix(String prefix) {
    final keys = {..._epochs.keys, ..._requests.keys, ..._data.keys};
    for (final key in keys.where((key) => key.startsWith(prefix))) {
      invalidate(key);
    }
  }

  void forget(String resource) {
    _data.remove(resource);
    invalidate(resource);
  }

  /// Hide every resource on expiry until Auth supplies a fresh generation.
  void blockSession() {
    _blocked = true;
    final keys = {..._requests.keys, ..._data.keys};
    _data.clear();
    for (final key in keys) {
      invalidate(key);
    }
  }

  void Function() listen(void Function(String) callback) {
    _listeners.add(callback);
    return () => _listeners.remove(callback);
  }

  void dispose() {
    _disposed = true;
    _data.clear();
    _epochs.clear();
    _requests.clear();
    _queries.clear();
    _stale.clear();
    _listeners.clear();
  }
}
