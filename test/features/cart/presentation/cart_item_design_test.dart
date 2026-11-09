import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/cart/domain/models/cart_item.dart';
import 'package:sports_store/features/cart/presentation/widgets/cart_item_tile.dart';
import 'package:sports_store/features/catalog/domain/models/product.dart';
import 'package:sports_store/features/catalog/domain/models/product_variant.dart';
import 'package:sports_store/features/catalog/presentation/view_models/catalog_providers.dart';
import 'package:sports_store/features/catalog/presentation/widgets/catalog_image.dart';

CartItem _item({int stock = 3, int quantity = 2, bool ownImage = true}) {
  final variant = ProductVariant(
    id: 'variant',
    productId: 'product',
    sku: 'shoe-40',
    label: 'Đen / 40',
    attributes: {
      'color': 'Đen',
      'size': '40',
      if (ownImage) 'image_path': 'products/black.webp',
    },
    priceVnd: 850000,
    availableQuantity: stock,
  );
  return CartItem(
    variantId: variant.id,
    quantity: quantity,
    variant: variant,
    product: Product(
      id: 'product',
      categoryId: 'shoes',
      categoryName: 'Giày',
      name: 'Giày chạy bộ thể thao',
      description: null,
      imagePath: 'products/base.webp',
      variants: [variant],
    ),
  );
}

Future<void> _mount(
  WidgetTester tester,
  CartItem item, {
  bool enabled = true,
  bool selected = true,
  ValueChanged<bool>? onSelect,
  VoidCallback? onIncrease,
  VoidCallback? onDecrease,
  VoidCallback? onRemove,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [productImageProvider.overrideWith((ref, path) async => null)],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: CartItemTile(
                item: item,
                mutationsEnabled: enabled,
                selected: selected,
                onSelectionChanged: onSelect,
                onIncrease: onIncrease ?? () {},
                onDecrease: onDecrease ?? () {},
                onRemove: onRemove ?? () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('selection, exact variant image and line total follow real row', (
    tester,
  ) async {
    bool? selection;
    var increased = 0;
    await _mount(
      tester,
      _item(),
      onSelect: (value) => selection = value,
      onIncrease: () => increased++,
    );
    expect(find.text('ĐEN • CỠ 40'), findsOneWidget);
    expect(find.text('850.000 đ'), findsOneWidget);
    expect(find.text('Thành tiền: 1.700.000 đ'), findsOneWidget);
    expect(
      tester
          .widget<CatalogProductImage>(find.byType(CatalogProductImage))
          .imagePath,
      'products/black.webp',
    );
    expect(find.text('Chỉ còn 3 sản phẩm trong kho'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cart-select-variant')));
    expect(selection, isFalse);
    await tester.tap(find.byKey(const ValueKey('cart-increase-variant')));
    expect(increased, 1);
  });

  testWidgets('pending mutation disables selection and all writes', (
    tester,
  ) async {
    await _mount(tester, _item(), enabled: false, onSelect: (_) {});
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
    for (final action in ['increase', 'decrease', 'remove']) {
      expect(
        tester
            .widget<IconButton>(find.byKey(ValueKey('cart-$action-variant')))
            .onPressed,
        isNull,
      );
    }
  });

  testWidgets(
    'unavailable item can be deselected and removed without editing quantity',
    (tester) async {
      var removed = 0;
      bool? selection;
      await _mount(
        tester,
        const CartItem(variantId: 'missing', quantity: 1),
        onSelect: (value) => selection = value,
        onRemove: () => removed++,
      );
      expect(
        tester.widget<Checkbox>(find.byType(Checkbox)).onChanged,
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey('cart-select-missing')));
      expect(selection, isFalse);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('cart-increase-missing')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('cart-remove-missing')));
      expect(removed, 1);
    },
  );

  testWidgets(
    'photo fallback and ample stock do not fabricate low-stock warnings',
    (tester) async {
      await _mount(tester, _item(stock: 12, ownImage: false));
      expect(
        tester
            .widget<CatalogProductImage>(find.byType(CatalogProductImage))
            .imagePath,
        'products/base.webp',
      );
      expect(
        find.byKey(const ValueKey('cart-low-stock-variant')),
        findsNothing,
      );
      expect(find.byType(Checkbox), findsNothing);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets('row fits 320px at text scale $scale', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await _mount(tester, _item(), onSelect: (_) {});
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('cart-increase-variant')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
    testWidgets('large overstock quantity fits 320px at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      var decreases = 0;
      final semantics = tester.ensureSemantics();

      await _mount(
        tester,
        _item(stock: 4, quantity: 1000000000),
        onSelect: (_) {},
        onDecrease: () => decreases++,
      );
      expect(tester.takeException(), isNull);
      final quantity = find.byKey(const ValueKey('cart-quantity-variant'));
      await tester.ensureVisible(quantity);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: quantity, matching: find.text('1000000000')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Số lượng 1000000000'), findsOneWidget);
      final decrease = find.byKey(const ValueKey('cart-decrease-variant'));
      expect(tester.widget<IconButton>(decrease).onPressed, isNotNull);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('cart-increase-variant')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(decrease);
      expect(decreases, 1);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}
