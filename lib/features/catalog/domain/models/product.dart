import 'product_variant.dart';

/// A catalogue product with the currently visible variants.
class Product {
  Product({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.name,
    required this.description,
    required this.imagePath,
    required List<ProductVariant> variants,
  }) : variants = List<ProductVariant>.unmodifiable(variants);

  final String id;
  final String categoryId;
  final String categoryName;
  final String name;
  final String? description;
  final String? imagePath;
  final List<ProductVariant> variants;

  /// The lowest price among visible variants, or null when there are none.
  int? get minPriceVnd {
    if (variants.isEmpty) return null;
    var minimum = variants.first.priceVnd;
    for (final variant in variants.skip(1)) {
      if (variant.priceVnd < minimum) minimum = variant.priceVnd;
    }
    return minimum;
  }

  int get availableQuantity => variants.fold<int>(
    0,
    (total, variant) => total + variant.availableQuantity,
  );

  @override
  bool operator ==(Object other) {
    if (other is! Product ||
        id != other.id ||
        categoryId != other.categoryId ||
        categoryName != other.categoryName ||
        name != other.name ||
        description != other.description ||
        imagePath != other.imagePath ||
        variants.length != other.variants.length) {
      return false;
    }
    for (var index = 0; index < variants.length; index++) {
      if (variants[index] != other.variants[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    id,
    categoryId,
    categoryName,
    name,
    description,
    imagePath,
    Object.hashAll(variants),
  );
}
