import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_providers.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_state.dart';
import 'package:sports_store/features/catalog/domain/models/product.dart';
import 'package:sports_store/features/catalog/domain/models/product_variant.dart';
import 'package:sports_store/features/catalog/presentation/pages/product_details_page.dart';
import 'package:sports_store/features/catalog/presentation/view_models/catalog_providers.dart';

class _Cart extends CartViewModel {
  final writes = <(String, int)>[];
  @override
  Future<CartState> build() async => CartState(items: []);
  @override
  Future<bool> addItem({
    required String variantId,
    required int quantity,
  }) async {
    writes.add((variantId, quantity));
    return true;
  }
}

ProductVariant _variant(
  String id,
  String color,
  String size,
  int stock, {
  String? image,
  String? imageSource,
}) => ProductVariant(
  id: id,
  productId: 'product',
  sku: id,
  label: '$color / $size',
  attributes: {
    'color': color,
    'size': size,
    'image_path': ?image,
    'image_source': ?imageSource,
  },
  priceVnd: id == 'blue-41' ? 950000 : 850000,
  availableQuantity: stock,
);

Product _product() => Product(
  id: 'product',
  categoryId: 'shoes',
  categoryName: 'Giày',
  name: 'Giày chạy bộ',
  description: 'Bộ màu minh họa',
  imagePath: 'products/base.webp',
  variants: [
    _variant('black-40', 'Đen', '40', 5, image: 'products/black.webp'),
    _variant('black-41', 'Đen', '41', 2, image: 'products/black.webp'),
    _variant('blue-40', 'Xanh', '40', 0, image: 'products/blue.webp'),
    _variant('blue-41', 'Xanh', '41', 3, image: 'products/blue.webp'),
    _variant('white-42', 'Trắng', '42', 4),
  ],
);

Future<_Cart> _mount(WidgetTester tester, {Product? product}) async {
  final cart = _Cart();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cartProvider.overrideWith(() => cart),
        productDetailsProvider('product')
            .overrideWith((ref) async => product ?? _product()),
        productImageProvider.overrideWith((ref, path) async => null),
      ],
      child: const MaterialApp(home: ProductDetailsPage(productId: 'product')),
    ),
  );
  await tester.pumpAndSettle();
  return cart;
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('color selection changes asset and AI disclosure together', (
    tester,
  ) async {
    final source = _product();
    const original = 'asset:assets/images/stride_color_20261109_A01_C1.png';
    const generated = 'asset:assets/images/stride_color_20261109_A01_C2.png';
    final product = Product(
      id: source.id,
      categoryId: source.categoryId,
      categoryName: source.categoryName,
      name: source.name,
      description: source.description,
      imagePath: source.imagePath,
      variants: [
        _variant(
          'original',
          'Xanh',
          '40',
          4,
          image: original,
          imageSource: 'catalog_reference',
        ),
        _variant(
          'generated',
          'Đen',
          '40',
          4,
          image: generated,
          imageSource: 'ai_color_preview',
        ),
      ],
    );
    await _mount(tester, product: product);
    expect(
      find.byKey(const ValueKey('catalog-detail-image-$original')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('catalog-color-image-note')),
      findsNothing,
    );
    await _tap(tester, 'catalog-color-Đen');
    expect(
      find.byKey(const ValueKey('catalog-detail-image-$generated')),
      findsOneWidget,
    );
    expect(find.text('Ảnh phối màu minh họa bằng AI.'), findsOneWidget);
    expect(find.textContaining('chưa có ảnh riêng'), findsNothing);
    await _tap(tester, 'catalog-color-Xanh');
    expect(
      find.byKey(const ValueKey('catalog-detail-image-$original')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('catalog-color-image-note')),
      findsNothing,
    );
    expect(find.textContaining('chưa có ảnh riêng'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('color preserves size and sends exact chosen variant to cart', (
    tester,
  ) async {
    final cart = await _mount(tester);
    await _tap(tester, 'catalog-variant-black-41');
    await _tap(tester, 'catalog-color-Xanh');
    expect(
      find.byKey(const ValueKey('catalog-variant-black-41')),
      findsNothing,
    );
    final size = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('catalog-variant-blue-41')),
    );
    expect(size.selected, isTrue);
    expect(
      find.byKey(const ValueKey('catalog-detail-image-products/blue.webp')),
      findsOneWidget,
    );
    await _tap(tester, 'catalog-quantity-increase');
    await _tap(tester, 'catalog-cart-action');
    expect(cart.writes, [('blue-41', 2)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unavailable color size exposes price but cannot add or increase',
    (tester) async {
      final cart = await _mount(tester);
      await _tap(tester, 'catalog-color-Xanh');
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('catalog-variant-blue-40')),
            )
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('catalog-cart-action')),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('catalog-quantity-increase')),
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('catalog-quantity-increase')),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('catalog-quantity-value')),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
      expect(cart.writes, isEmpty);
    },
  );

  testWidgets(
    'color without same size picks available size and marks sample photo',
    (tester) async {
      await _mount(tester);
      await _tap(tester, 'catalog-color-Trắng');
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('catalog-variant-white-42')),
            )
            .selected,
        isTrue,
      );
      expect(
        find.text('Ảnh mẫu sản phẩm; màu Trắng chưa có ảnh riêng.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('catalog-detail-image-products/base.webp')),
        findsOneWidget,
      );
    },
  );
  testWidgets('legacy variant remains reachable beside named colors', (
    tester,
  ) async {
    final source = _product();
    final product = Product(
      id: source.id,
      categoryId: source.categoryId,
      categoryName: source.categoryName,
      name: source.name,
      description: source.description,
      imagePath: source.imagePath,
      variants: [
        ...source.variants,
        const ProductVariant(
          id: 'legacy',
          productId: 'product',
          sku: 'legacy',
          label: 'Bản tiêu chuẩn',
          attributes: {},
          priceVnd: 700000,
          availableQuantity: 2,
        ),
      ],
    );
    final cart = await _mount(tester, product: product);
    await _tap(tester, 'catalog-color-Xanh');
    await _tap(tester, 'catalog-color-Phiên bản khác');
    expect(
      find.byKey(const ValueKey('catalog-variant-legacy')),
      findsOneWidget,
    );
    await _tap(tester, 'catalog-cart-action');
    expect(cart.writes.single, ('legacy', 1));
  });

  testWidgets('large color gallery and controls fit 320px at text scale 2', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final source = _product();
    final product = Product(
      id: source.id,
      categoryId: source.categoryId,
      categoryName: source.categoryName,
      name: source.name,
      description: source.description,
      imagePath: source.imagePath,
      variants: [
        ProductVariant(
          id: 'gallery',
          productId: 'product',
          sku: 'gallery',
          label: 'Đen / 40',
          attributes: {
            'color': 'Đen',
            'size': '40',
            'image_paths': List.generate(
              50,
              (index) => 'products/gallery-$index.webp',
            ),
          },
          priceVnd: 700000,
          availableQuantity: 2,
        ),
        ...source.variants,
      ],
    );
    await _mount(tester, product: product);
    expect(tester.takeException(), isNull);
    await _tap(tester, 'catalog-color-Xanh');
    await tester.ensureVisible(
      find.byKey(const ValueKey('catalog-quantity-increase')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('catalog-cart-action')), findsOneWidget);
  });
  testWidgets(
    'size choices are ordered numerically despite repository UUID order',
    (tester) async {
      final source = _product();
      final product = Product(
        id: source.id,
        categoryId: source.categoryId,
        categoryName: source.categoryName,
        name: source.name,
        description: source.description,
        imagePath: source.imagePath,
        variants: [
          _variant('last', 'Đen', '44', 2),
          _variant('first', 'Đen', '36', 2),
          _variant('middle', 'Đen', '40', 2),
        ],
      );
      await _mount(tester, product: product);
      final choices = tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .toList();
      expect(choices.map((choice) => (choice.label as Text).data), [
        '36',
        '40',
        '44',
      ]);
    },
  );
}
