class CatalogCategory {
  const CatalogCategory({
    required this.id,
    required this.name,
    required this.active,
  });
  final String id;
  final String name;
  final bool active;
}

class ManagedVariant {
  const ManagedVariant({
    this.id,
    required this.sku,
    required this.label,
    required this.priceVnd,
    required this.onHand,
    this.reserved = 0,
    this.active = true,
    this.attributes = const {},
    this.expectedOnHand,
  });
  final String? id;
  final String sku;
  final String label;
  final int priceVnd;
  final int onHand;
  final int reserved;
  final bool active;
  final Map<String, dynamic> attributes;
  final int? expectedOnHand;
  int get available => onHand - reserved;
  Map<String, dynamic> toCommand() => {
    'id': id,
    'sku': sku.trim(),
    'label': label.trim(),
    'price_vnd': priceVnd,
    'on_hand': onHand,
    'expected_on_hand': expectedOnHand,
    'is_active': active,
    'attributes': attributes,
  };
}

class ManagedProduct {
  const ManagedProduct({
    this.id,
    required this.name,
    required this.categoryId,
    this.categoryName = '',
    this.description = '',
    this.imagePath = '',
    this.imageUrl,
    this.active = true,
    this.updatedAt,
    required this.variants,
  });
  final String? id;
  final String name;
  final String categoryId;
  final String categoryName;
  final String description;
  final String imagePath;
  final String? imageUrl;
  final bool active;
  final String? updatedAt;
  final List<ManagedVariant> variants;
  int get available =>
      variants.where((v) => v.active).fold(0, (sum, v) => sum + v.available);
  int get minimumPrice => variants.isEmpty
      ? 0
      : variants.map((v) => v.priceVnd).reduce((a, b) => a < b ? a : b);
  ManagedProduct withActive(bool value) => ManagedProduct(
    id: id,
    name: name,
    categoryId: categoryId,
    categoryName: categoryName,
    description: description,
    imagePath: imagePath,
    imageUrl: imageUrl,
    active: value,
    updatedAt: updatedAt,
    variants: variants,
  );
}

class CatalogSnapshot {
  const CatalogSnapshot({required this.categories, required this.products});
  final List<CatalogCategory> categories;
  final List<ManagedProduct> products;
}

class CatalogFailure implements Exception {
  const CatalogFailure(this.message, {this.outcomeUnknown = false});
  final String message;
  final bool outcomeUnknown;
  @override
  String toString() => message;
}
