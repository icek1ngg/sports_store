import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../deliveries/data/repositories/operational_read_access.dart';
import '../../../deliveries/data/repositories/operational_providers.dart';
import '../../data/repositories/supabase_cod_repository.dart';
import '../../data/repositories/supabase_cod_receipt_repository.dart';
import '../../domain/models/cod_collection.dart';
import '../../domain/repositories/cod_repository.dart';
import '../../domain/repositories/cod_receipt_repository.dart';

typedef CodCollectionFilter = ({String? shipperId, String? orderId});

final codReceiptRepositoryProvider = Provider.autoDispose<CodReceiptRepository>(
  (ref) {
    return SupabaseCodReceiptRepository(
      access: ref.watch(operationalReadAccessProvider),
    );
  },
);

/// CSPRNG UUIDv4 generated once per confirmed operation, never per retry.
final codReceiptRequestIdProvider = Provider<String Function()>((ref) {
  final random = Random.secure();
  return () {
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  };
});

final _codRoleForSessionProvider = FutureProvider.autoDispose
    .family<String, OperationalSession>((ref, session) {
      return ref
          .watch(operationalReadAccessProvider)
          .run<String>(
            roles: const {'shipper', 'manager'},
            action: (identity) async => identity.role,
          );
    }, retry: (count, error) => null);

/// Uses the same server-managed role as the existing shared route guard.
final codScreenRoleProvider = Provider.autoDispose<AsyncValue<String>>((ref) {
  final session = ref.watch(operationalSessionProvider);
  final failure = operationalSessionFailure(session);
  if (failure != null) return AsyncError(failure, StackTrace.empty);
  if (session.isLoading) return const AsyncLoading();
  return withoutPreviousOperationalData(
    ref.watch(_codRoleForSessionProvider(session.requireValue)),
  );
});

final retryCodScreenRoleProvider = Provider.autoDispose<VoidCallbackForCod>((
  ref,
) {
  return () {
    refreshOperationalReads(ref);
    ref.invalidate(_codRoleForSessionProvider);
  };
});

typedef VoidCallbackForCod = void Function();

/// Clear the backing cache rather than only its public AsyncValue projection.
void invalidateLegacyCodReads(Ref ref) =>
    ref.invalidate(_codForSessionProvider);

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
