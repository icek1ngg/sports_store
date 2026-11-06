import '../../../catalog/data/models/catalog_dto.dart';
import '../../domain/models/cart_item.dart';

class CartItemDto {
  static CartItem fromJson(
    Map<String, dynamic> json, {
    required String customerId,
  }) {
    final owner = CatalogDtoReaders.readRequiredUuid(json, 'customer_id');
    if (owner.toLowerCase() != customerId.toLowerCase()) {
      throw const FormatException('Unexpected cart owner');
    }
    final id = CatalogDtoReaders.readRequiredUuid(json, 'variant_id');
    final quantity = CatalogDtoReaders.readRequiredInteger(json, 'quantity');
    if (quantity < 1) throw const FormatException('Invalid cart quantity');
    if (!json.containsKey('product_variants')) {
      throw const FormatException('Missing cart variant relation');
    }
    final rawVariant = json['product_variants'];
    if (rawVariant == null) return CartItem(variantId: id, quantity: quantity);
    final variantJson = object(rawVariant);
    final variant = ProductVariantDto.fromJson(variantJson);
    if (variant.id.toLowerCase() != id.toLowerCase()) {
      throw const FormatException('Unexpected cart variant');
    }
    if (!variantJson.containsKey('products')) {
      throw const FormatException('Missing cart product relation');
    }
    final rawProduct = variantJson['products'];
    if (rawProduct == null || !variant.isActive) {
      return CartItem(variantId: id, quantity: quantity);
    }
    final productJson = object(rawProduct);
    if (!productJson.containsKey('categories')) {
      throw const FormatException('Missing cart category relation');
    }
    if (productJson['categories'] == null) {
      return CartItem(variantId: id, quantity: quantity);
    }
    final product = ProductDto.fromJson(productJson, variants: [variant]);
    if (!product.isActive || !product.categoryIsActive) {
      return CartItem(variantId: id, quantity: quantity);
    }
    return CartItem(
      variantId: id,
      quantity: quantity,
      product: product.toDomain(),
      variant: variant.toDomain(),
    );
  }

  static Map<String, dynamic> object(Object? value) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw const FormatException('Invalid cart object');
    }
    return Map<String, dynamic>.from(value);
  }
}
