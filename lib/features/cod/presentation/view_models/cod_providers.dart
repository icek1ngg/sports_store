import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../deliveries/data/repositories/operational_read_access.dart';
import '../../../deliveries/data/repositories/operational_providers.dart';
import '../../data/repositories/supabase_cod_repository.dart';
import '../../domain/models/cod_collection.dart';
import '../../domain/repositories/cod_repository.dart';

typedef CodCollectionFilter = ({String? shipperId, String? orderId});

final codRepositoryProvider = Provider.autoDispose<CodRepository>((ref) {
  return SupabaseCodRepository(
    access: ref.watch(operationalReadAccessProvider),
  );
});

final _codForSessionProvider = FutureProvider.autoDispose
    .family<List<CodCollection>, (OperationalSession, CodCollectionFilter)>(
      (ref, key) => ref
          .watch(codRepositoryProvider)
          .listCollections(
            shipperId: key.$2.shipperId,
            orderId: key.$2.orderId,
          ),
      retry: (count, error) => null,
    );

final filteredCodCollectionsProvider = Provider.autoDispose
    .family<AsyncValue<List<CodCollection>>, CodCollectionFilter>((
      ref,
      filter,
    ) {
      final session = ref.watch(operationalSessionProvider);
      final failure = operationalSessionFailure(session);
      if (failure != null) return AsyncError(failure, StackTrace.empty);
      if (session.isLoading) return const AsyncLoading();
      return withoutPreviousOperationalData(
        ref.watch(_codForSessionProvider((session.requireValue, filter))),
      );
    });

final codCollectionsProvider =
    Provider.autoDispose<AsyncValue<List<CodCollection>>>((ref) {
      return ref.watch(
        filteredCodCollectionsProvider((shipperId: null, orderId: null)),
      );
    });
