import '../errors/app_failure.dart';

/// Loading/error flags belong to local UI state, not the business entity.
class ReadSnapshot<T> {
  const ReadSnapshot({
    this.data,
    this.loading = false,
    this.stale = false,
    this.failure,
    this.empty = false,
  });
  final T? data;
  final bool loading;
  final bool stale;
  final AppFailure? failure;
  final bool empty;
  bool get isFresh => data != null && !loading && !stale && failure == null;
  bool get isInitialLoading => data == null && loading;
}
