import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../data/repositories/supabase_catalog_repository.dart';
import '../../domain/models/managed_product.dart';
import '../../domain/repositories/catalog_repository.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => SupabaseCatalogRepository(ref.watch(supabaseClientProvider)),
);

final _catalogIdentityProvider = StreamProvider<String?>((ref) async* {
  final client = ref.watch(supabaseClientProvider);
  yield client.auth.currentSession?.accessToken;
  await for (final change in client.auth.onAuthStateChange) {
    yield change.session?.accessToken;
  }
});

final productManagementViewModelProvider =
    AsyncNotifierProvider.autoDispose<
      ProductManagementViewModel,
      CatalogSnapshot
    >(ProductManagementViewModel.new, retry: (_, _) => null);

class ProductManagementViewModel extends AsyncNotifier<CatalogSnapshot> {
  int _generation = 0;
  @override
  Future<CatalogSnapshot> build() async {
    _generation++;
    ref.watch(_catalogIdentityProvider);
    return ref.watch(catalogRepositoryProvider).loadManagement();
  }

  Future<void> reload() async {
    final generation = ++_generation;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => ref.read(catalogRepositoryProvider).loadManagement(),
    );
    if (ref.mounted && generation == _generation) state = result;
  }

  Future<void> save(ManagedProduct product, {required String requestId}) async {
    final generation = _generation;
    await ref
        .read(catalogRepositoryProvider)
        .saveProduct(product, requestId: requestId);
    if (ref.mounted && generation == _generation) await reload();
  }
}

String newCatalogRequestId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
