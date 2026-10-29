import '../models/catalog_page.dart';
import '../models/catalog_query.dart';
import '../models/category.dart';
import '../models/product.dart';

/// Read operations for the catalogue.
abstract interface class CatalogRepository {
  Future<List<Category>> getCategories();

  Future<CatalogPage> getProducts(CatalogQuery query);

  Future<Product?> getProduct(String id);

  Future<String?> getImageUrl(String path);
}
