import '../models/cart_item.dart';

abstract interface class CartRepository {
  Future<List<CartItem>> getItems();

  /// An absolute target, never an increment. Retrying keeps the same target.
  /// Does not reserve inventory. Placement must recheck stock on the server.
  Future<void> setQuantity({required String variantId, required int quantity});

  Future<void> removeItem(String variantId);
}
