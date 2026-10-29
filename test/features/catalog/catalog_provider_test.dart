import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/catalog/domain/models/catalog_page.dart';
import 'package:sports_store/features/catalog/domain/models/catalog_query.dart';
import 'package:sports_store/features/catalog/domain/models/category.dart';
import 'package:sports_store/features/catalog/domain/models/product.dart';
import 'package:sports_store/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:sports_store/features/catalog/presentation/view_models/catalog_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';

class _Catalog implements CatalogRepository {
  final queries = <CatalogQuery>[];
  @override
  Future<CatalogPage> getProducts(CatalogQuery query) async {
    queries.add(query);
    return CatalogPage(products: [], hasMore: false);
  }

  @override
  Future<List<Category>> getCategories() async => [];
  @override
  Future<Product?> getProduct(String id) async => null;
  @override
  Future<String?> getImageUrl(String path) async => null;
}

void main() {
  test('real view model preserves search on refresh and resets for another account', () async {
    final sessions = StreamController<OperationalSession>();
    final repository = _Catalog();
    final container = ProviderContainer(
      overrides: [
        operationalSessionProvider.overrideWith((ref) => sessions.stream),
        catalogRepositoryProvider.overrideWithValue(repository),
      ],
    );
    final subscription = container.listen(catalogPageProvider, (_, _) {});
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await sessions.close();
    });
    sessions.add(const OperationalSession(userId: 'customer-A', generation: 1));
    await container.read(catalogPageProvider.future);
    container.read(catalogQueryProvider.notifier).setSearch('giày');
    await container.read(catalogPageProvider.future);
    expect(repository.queries.last.search, 'giày');
    await container.read(catalogPageProvider.notifier).refresh();
    expect(repository.queries.last.search, 'giày');
    sessions.add(const OperationalSession(userId: 'customer-B', generation: 2));
    await Future<void>.delayed(Duration.zero);
    await container.read(catalogPageProvider.future);
    expect(container.read(catalogQueryProvider).search, isEmpty);
    expect(repository.queries.last.page, 0);
  });
}
