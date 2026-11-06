import '../../domain/models/cart_failure.dart';
import '../../domain/models/cart_item.dart';

class CartState {
  CartState({
    required List<CartItem> items,
    this.isMutating = false,
    this.mutationError,
    this.hasPendingMutation = false,
  }) : items = List.unmodifiable(items);

  final List<CartItem> items;
  final bool isMutating;
  final CartFailure? mutationError;
  final bool hasPendingMutation;

  int get totalQuantity =>
      items.fold(0, (total, item) => total + item.quantity);
  int get subtotalVnd =>
      items.fold(0, (total, item) => total + (item.lineTotalVnd ?? 0));
  bool get hasUnavailableItems => items.any((item) => !item.isAvailable);
  bool get canCheckout =>
      items.isNotEmpty &&
      !isMutating &&
      !hasPendingMutation &&
      items.every((item) => item.canCheckout);
}
