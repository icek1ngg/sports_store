import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/deliveries/data/repositories/operational_providers.dart';
import '../../../../features/deliveries/data/repositories/operational_read_access.dart';
import '../../../../features/deliveries/domain/models/operational_failure.dart';
import '../../data/repositories/supabase_catalog_repository.dart';
import '../../domain/models/catalog_page.dart';
import '../../domain/models/catalog_query.dart';
import '../../domain/models/category.dart';
import '../../domain/models/product.dart';
import '../../domain/repositories/catalog_repository.dart';

final catalogRepositoryProvider = Provider.autoDispose<CatalogRepository>((
  ref,
) {
  return SupabaseCatalogRepository(
    access: ref.watch(operationalReadAccessProvider),
  );
});

/// Categories are re-read for each operational account epoch.
final catalogCategoriesProvider = FutureProvider.autoDispose<List<Category>>((
  ref,
) async {
  final session = await _requireOperationalSession(ref);
  // Keep the captured epoch in the dependency graph and verify it again in
  // the repository before the result is published.
  if (session.userId == null) {
    throw const OperationalFailure(OperationalFailureCode.sessionExpired);
  }
  return ref.watch(catalogRepositoryProvider).getCategories();
});

final catalogQueryProvider =
    NotifierProvider.autoDispose<CatalogQueryViewModel, CatalogQuery>(
      CatalogQueryViewModel.new,
    );

class CatalogQueryViewModel extends Notifier<CatalogQuery> {
  @override
  CatalogQuery build() {
    ref.watch(
      operationalSessionProvider.select((state) => state.asData?.value.userId),
    );
    return const CatalogQuery();
  }

  void setSearch(String search) {
    state = state.copyWith(search: search, page: 0);
  }

  void setCategory(String? categoryId) {
    state = state.copyWith(categoryId: categoryId, page: 0);
  }

  void nextPage() {
    state = state.copyWith(page: state.page + 1);
  }

  void previousPage() {
    state = state.copyWith(page: state.page > 0 ? state.page - 1 : 0);
  }

  void reset() {
    state = const CatalogQuery();
  }
}

final catalogPageProvider =
    AsyncNotifierProvider.autoDispose<CatalogListViewModel, CatalogPage>(
      CatalogListViewModel.new,
      retry: (count, error) => null,
    );

class CatalogListViewModel extends AsyncNotifier<CatalogPage> {
  @override
  Future<CatalogPage> build() async {
    // Riverpod reuses this notifier instance when query/session dependencies
    // change. Explicitly clear state so an old account/page is never rendered
    // while the new read is in flight.
    state = const AsyncLoading();
    await _requireOperationalSession(ref);
    final query = ref.watch(catalogQueryProvider);
    return ref.watch(catalogRepositoryProvider).getProducts(query);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    ref.invalidateSelf();
    await future;
  }
}

final productDetailsProvider = FutureProvider.autoDispose
    .family<Product?, String>((ref, id) async {
      await _requireOperationalSession(ref);
      return ref.watch(catalogRepositoryProvider).getProduct(id);
    });

final productImageProvider = FutureProvider.autoDispose.family<String?, String>(
  (ref, path) async {
    await _requireOperationalSession(ref);
    return ref.watch(catalogRepositoryProvider).getImageUrl(path);
  },
);

Future<OperationalSession> _requireOperationalSession(Ref ref) async {
  final state = ref.watch(operationalSessionProvider);
  if (state.hasError) {
    throw mapOperationalFailure(state.error!);
  }
  final session = !state.isLoading && state.hasValue
      ? state.requireValue
      : await ref.watch(operationalSessionProvider.future);
  final failure = session.failure;
  if (failure != null) throw failure;
  if (session.userId == null) {
    throw const OperationalFailure(OperationalFailureCode.sessionExpired);
  }
  return session;
}
