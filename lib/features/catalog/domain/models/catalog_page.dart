import 'product.dart';

/// One page of products and whether a following page exists.
class CatalogPage {
  CatalogPage({required List<Product> products, required this.hasMore})
    : products = List<Product>.unmodifiable(products);

  final List<Product> products;
  final bool hasMore;

  @override
  bool operator ==(Object other) {
    if (other is! CatalogPage ||
        hasMore != other.hasMore ||
        products.length != other.products.length) {
      return false;
    }
    for (var index = 0; index < products.length; index++) {
      if (products[index] != other.products[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(hasMore, Object.hashAll(products));
}
