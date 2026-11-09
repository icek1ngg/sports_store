import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/cart_item.dart';
import 'cart_providers.dart';

/// Local UI intent; selecting a row neither changes the cart nor reserves stock.
class CartSelectionState {
  CartSelectionState({Iterable<String> excludedVariantIds = const []})
    : excludedVariantIds = Set.unmodifiable(
        excludedVariantIds.map((id) => id.toLowerCase()),
      );

  final Set<String> excludedVariantIds;

  bool isSelected(String variantId) =>
      !excludedVariantIds.contains(variantId.toLowerCase());

  List<CartItem> selectedItems(List<CartItem> items) =>
      List.unmodifiable(items.where((item) => isSelected(item.variantId)));
}

final cartSelectionProvider =
    NotifierProvider.autoDispose<CartSelectionViewModel, CartSelectionState>(
      CartSelectionViewModel.new,
    );

class CartSelectionViewModel extends Notifier<CartSelectionState> {
  String? _owner;
  CartSelectionState _selection = CartSelectionState();

  @override
  CartSelectionState build() {
    final cart = ref.watch(cartProvider);
    final snapshot = cart.asData?.value;
    if (!cart.isLoading && !cart.hasError && snapshot != null) {
      if (snapshot.userId != _owner) {
        _owner = snapshot.userId;
        _selection = CartSelectionState();
      }
      final present = snapshot.items
          .map((item) => item.variantId.toLowerCase())
          .toSet();
      _selection = CartSelectionState(
        excludedVariantIds: _selection.excludedVariantIds.intersection(present),
      );
    }
    return _selection;
  }

  void setSelected(String variantId, bool selected) {
    final cart = ref.read(cartProvider);
    final snapshot = cart.asData?.value;
    if (cart.isLoading ||
        cart.hasError ||
        snapshot == null ||
        snapshot.isMutating ||
        snapshot.hasPendingMutation ||
        !snapshot.items.any(
          (item) => item.variantId.toLowerCase() == variantId.toLowerCase(),
        )) {
      return;
    }
    final excluded = {...state.excludedVariantIds};
    if (selected) {
      excluded.remove(variantId.toLowerCase());
    } else {
      excluded.add(variantId.toLowerCase());
    }
    state = _selection = CartSelectionState(excludedVariantIds: excluded);
  }

  void setAllSelected(bool selected) {
    final cart = ref.read(cartProvider);
    final snapshot = cart.asData?.value;
    if (cart.isLoading ||
        cart.hasError ||
        snapshot == null ||
        snapshot.isMutating ||
        snapshot.hasPendingMutation) {
      return;
    }
    state = _selection = CartSelectionState(
      excludedVariantIds: selected
          ? const []
          : snapshot.items.map((item) => item.variantId),
    );
  }
}
