import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'epoch_cache.dart';
import 'session_scope.dart';

/// Auth integration input. Override with the trusted CIN-01 scope provider.
/// The baseline is unresolved and cannot expose private data.
final featureSessionScopeProvider = Provider<SessionScope>(
  (ref) => const SessionScope.unresolved(),
);

final epochCacheProvider = Provider<EpochCache>((ref) {
  final cache = EpochCache(ref.watch(featureSessionScopeProvider));
  ref.onDispose(cache.dispose);
  return cache;
});
