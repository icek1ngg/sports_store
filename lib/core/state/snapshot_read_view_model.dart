import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/app_failure.dart';
import 'epoch_cache.dart';
import 'foundation_providers.dart';
import 'read_snapshot.dart';
import 'read_retry_policy.dart';

/// Reusable Phase 1 read lifecycle. A loader is injected by the feature.
/// Requests are serialized; superseded results cannot publish to cache or UI.
abstract class SnapshotReadViewModel<T extends Object>
    extends AsyncNotifier<ReadSnapshot<T>> {
  String get resourceKey;
  Future<T> Function() configureLoader();
  bool get scopeAllowed;
  bool isEmpty(T data);
  void onAccepted(T data) {}
  void onPrivateDataCleared() {}

  late EpochCache _cache;
  late Future<T> Function() _loader;
  late ReadRetryPolicy _retry;
  Future<void>? _running;
  bool _queued = false;
  int _lifecycle = 0;
  bool _selfInvalidation = false;

  @override
  ReadSnapshot<T> build() {
    final lifecycle = ++_lifecycle;
    // Old session drains retain their own tokens; they must not block a new
    // session or clear its running future when an obsolete response arrives.
    _running = null;
    _queued = false;
    _cache = ref.watch(epochCacheProvider);
    _retry = ref.watch(readRetryPolicyProvider);
    _loader = configureLoader();
    final allowed = _cache.canRead && scopeAllowed;
    final cancel = _cache.listen((key) {
      if (key != resourceKey || !ref.mounted || lifecycle != _lifecycle) return;
      if (!_cache.canRead) onPrivateDataCleared();
      final previous = state.value;
      if (previous != null) {
        final retained = _cache.read<T>(resourceKey)?.data;
        state = AsyncData(
          ReadSnapshot(
            data: retained,
            loading: _cache.canRead && previous.loading,
            stale: retained != null,
            failure: _cache.canRead
                ? previous.failure
                : const AppFailure(code: AppFailure.unauthenticated),
            empty: retained != null && isEmpty(retained),
          ),
        );
      }
      if (_cache.canRead && !_selfInvalidation) unawaited(_enqueue());
    });
    ref.onDispose(cancel);
    if (!allowed) {
      if (!_cache.scope.roleResolved) {
        return const ReadSnapshot(loading: true);
      }
      return ReadSnapshot(
        failure: AppFailure(
          code: !_cache.canRead
              ? AppFailure.unauthenticated
              : AppFailure.forbiddenOrUnavailable,
        ),
      );
    }
    final cached = _cache.read<T>(resourceKey);
    scheduleMicrotask(() {
      if (ref.mounted && lifecycle == _lifecycle) unawaited(refresh());
    });
    return ReadSnapshot(
      data: cached?.data,
      stale: cached?.stale ?? false,
      loading: true,
      empty: cached != null && isEmpty(cached.data),
    );
  }

  /// Refresh during a read invalidates its response and queues one latest read.
  Future<void> refresh() {
    if (!ref.mounted || !_cache.canRead || !scopeAllowed) {
      return Future.value();
    }
    _selfInvalidation = true;
    _cache.invalidate(resourceKey);
    _selfInvalidation = false;
    return _enqueue();
  }

  Future<void> _enqueue() {
    _queued = true;
    final lifecycle = _lifecycle;
    return _running ??= _drain(lifecycle).whenComplete(() {
      if (lifecycle == _lifecycle) _running = null;
    });
  }

  Future<void> _drain(int lifecycle) async {
    while (_queued &&
        lifecycle == _lifecycle &&
        ref.mounted &&
        _cache.canRead &&
        scopeAllowed) {
      _queued = false;
      final cache = _cache;
      final token = cache.begin(resourceKey);
      final loader = _loader;
      final previous = cache.read<T>(resourceKey)?.data;
      state = AsyncData(
        ReadSnapshot(data: previous, loading: true, stale: previous != null),
      );
      try {
        final data = await _readWithRetry(loader, cache, token);
        if (!ref.mounted ||
            lifecycle != _lifecycle ||
            !cache.accept(token, data)) {
          continue;
        }
        state = AsyncData(ReadSnapshot(data: data, empty: isEmpty(data)));
        onAccepted(data);
      } catch (error) {
        if (!ref.mounted ||
            lifecycle != _lifecycle ||
            !cache.isCurrent(token)) {
          continue;
        }
        final failure = error is AppFailure ? error : readFailure(error);
        if (shouldClearPrivateData(failure)) {
          onPrivateDataCleared();
          _selfInvalidation = true;
          if (failure.code == AppFailure.unauthenticated) {
            cache.blockSession();
          } else {
            cache.forget(resourceKey);
          }
          _selfInvalidation = false;
        }
        final retained = cache.read<T>(resourceKey)?.data;
        state = AsyncData(
          ReadSnapshot(
            data: retained,
            stale: retained != null,
            failure: failure,
            empty: retained != null && isEmpty(retained),
          ),
        );
      }
    }
  }

  Future<T> _readWithRetry(
    Future<T> Function() loader,
    EpochCache cache,
    ReadToken token,
  ) async {
    final retry = _retry;
    for (var attempt = 0; ; attempt++) {
      try {
        return await loader().timeout(const Duration(seconds: 10));
      } catch (error) {
        final failure = error is AppFailure ? error : readFailure(error);
        if (!cache.isCurrent(token) ||
            failure.code != AppFailure.network ||
            attempt >= retry.backoffs.length) {
          rethrow;
        }
        await retry.wait(retry.backoffs[attempt]);
        if (!cache.isCurrent(token)) rethrow;
      }
    }
  }

  /// Implemented against the shared safe failure contract by each feature.
  AppFailure readFailure(Object error);
  bool shouldClearPrivateData(AppFailure failure);
}
