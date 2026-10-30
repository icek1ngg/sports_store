import '../models/catalog_page.dart';
import '../models/catalog_query.dart';
import '../models/category.dart';
import '../models/managed_product.dart';
import '../models/product.dart';

/// Customer reads and manager writes share one catalog contract.
/// Implementations enforce the role required by each operation.
abstract interface class CatalogRepository {
  Future<List<Category>> getCategories();

  Future<CatalogPage> getProducts(CatalogQuery query);

  Future<Product?> getProduct(String id);

  Future<String?> getImageUrl(String path);

  Future<CatalogSnapshot> loadManagement();

  Future<String> saveProduct(
    ManagedProduct product, {
    required String requestId,
  });
}
