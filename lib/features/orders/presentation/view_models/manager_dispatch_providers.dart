import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/state/foundation_providers.dart';
import '../../data/repositories/supabase_manager_dispatch_repository.dart';
import '../../domain/repositories/manager_dispatch_repository.dart';

final managerDispatchRepositoryProvider = Provider<ManagerDispatchRepository>(
  (ref) => SupabaseManagerDispatchRepository(ref.watch(supabaseClientProvider)),
);

class PendingDispatch {
  const PendingDispatch(this.requestId, this.shipperId);
  final String requestId;
  final String shipperId;
}

class PendingDispatchStore {
  final Map<String, PendingDispatch> _pending = {};
  PendingDispatch? forOrder(String orderId) => _pending[orderId];
  void remember(String orderId, PendingDispatch pending) =>
      _pending[orderId] = pending;
  void clear(String orderId) => _pending.remove(orderId);
}

// Keep per-account pending identities through temporary unresolved Auth states.
// The dialog still gates every read/send against its exact submitted scope.
final _pendingDispatchAccountsProvider =
    Provider<Map<String, PendingDispatchStore>>((ref) => {});
final pendingDispatchStoreProvider = Provider<PendingDispatchStore>((ref) {
  final identity = ref.watch(
    featureSessionScopeProvider.select((s) => (s.userId, s.role)),
  );
  if (identity.$1 == null || identity.$2 != 'manager') {
    return PendingDispatchStore();
  }
  return ref
      .read(_pendingDispatchAccountsProvider)
      .putIfAbsent(identity.$1!, PendingDispatchStore.new);
});
