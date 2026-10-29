import '../../../catalog/domain/models/product.dart';
import '../../../catalog/domain/models/product_variant.dart';

/// A cart row remains visible even when RLS hides its retired catalogue row.
class CartItem {
  const CartItem({
    required this.variantId,
    required this.quantity,
    this.product,
    this.variant,
  });

  final String variantId;
  final int quantity;
  final Product? product;
  final ProductVariant? variant;

  bool get isAvailable => product != null && variant != null;
  bool get hasEnoughStock =>
      isAvailable && quantity <= variant!.availableQuantity;
  bool get canCheckout => isAvailable && hasEnoughStock && quantity > 0;
  int? get lineTotalVnd => isAvailable ? variant!.priceVnd * quantity : null;
}
