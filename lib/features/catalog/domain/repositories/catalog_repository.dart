import '../models/managed_product.dart';

abstract interface class CatalogRepository {
  Future<CatalogSnapshot> loadManagement();
  Future<String> saveProduct(
    ManagedProduct product, {
    required String requestId,
  });
}
