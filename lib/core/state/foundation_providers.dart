import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'epoch_cache.dart';
import 'session_scope.dart';

/// Production main binds this to AuthSessionViewModel. Tests/Preview may
/// override it without creating a Supabase client or a second auth authority.
/// The unbound baseline is unresolved and cannot expose private data.
final featureSessionScopeProvider = Provider<SessionScope>(
  (ref) => const SessionScope.unresolved(),
);

final epochCacheProvider = Provider<EpochCache>((ref) {
  final cache = EpochCache(ref.watch(featureSessionScopeProvider));
  ref.onDispose(cache.dispose);
  return cache;
});
