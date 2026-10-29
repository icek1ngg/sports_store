import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_providers.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_state.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/catalog/domain/models/catalog_page.dart';
import 'package:sports_store/features/catalog/domain/models/category.dart';
import 'package:sports_store/features/catalog/domain/models/product.dart';
import 'package:sports_store/features/catalog/domain/models/product_variant.dart';
import 'package:sports_store/features/catalog/presentation/pages/product_details_page.dart';
import 'package:sports_store/features/catalog/presentation/pages/product_list_page.dart';
import 'package:sports_store/features/catalog/presentation/view_models/catalog_providers.dart';

const _categoryId = '11111111-1111-4111-8111-111111111111';
const _productId = '22222222-2222-4222-8222-222222222222';
const _secondVariantId = '33333333-3333-4333-8333-333333333333';

final _category = Category(id: _categoryId, code: 'football', name: 'Bóng đá');

Product _product({List<ProductVariant>? variants}) {
  return Product(
    id: _productId,
    categoryId: _categoryId,
    categoryName: _category.name,
    name: 'Giày chạy bộ đường dài',
    description: 'Thiết kế nhẹ cho những buổi chạy hằng ngày.',
    imagePath: null,
    variants:
        variants ??
        const [
          ProductVariant(
            id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            productId: _productId,
            sku: 'RUN-40',
            label: 'Đen / 40',
            attributes: {'Màu': 'Đen', 'Cỡ': '40'},
            priceVnd: 850000,
            availableQuantity: 4,
          ),
        ],
  );
}

class _TestCatalogListNotifier extends CatalogListViewModel {
  _TestCatalogListNotifier(this.loader);

  final Future<CatalogPage> Function() loader;

  @override
  Future<CatalogPage> build() => loader();
}

class _EmptyCart extends CartViewModel {
  @override
  Future<CartState> build() async => CartState(items: []);
}

List<Override> _overrides({
  CatalogPage? page,
  Future<CatalogPage> Function()? loader,
  Future<List<Category>> Function()? categoryLoader,
  Product? detail,
}) {
  return [
    cartProvider.overrideWith(_EmptyCart.new),
    operationalSessionProvider.overrideWith(
      (ref) => Stream.value(
        const OperationalSession(userId: 'test-customer', generation: 0),
      ),
    ),
    catalogCategoriesProvider.overrideWith(
      (ref) => categoryLoader?.call() ?? Future.value([_category]),
    ),
    catalogPageProvider.overrideWith(
      () => _TestCatalogListNotifier(
        loader ??
            (() async =>
                page ?? CatalogPage(products: [_product()], hasMore: false)),
      ),
    ),
    if (detail != null)
      productDetailsProvider(detail.id).overrideWith((ref) async => detail),
  ];
}

Widget _host({required Widget child, List<Override> overrides = const []}) {
  return ProviderScope(
    key: UniqueKey(),
    overrides: overrides,
    child: MaterialApp(home: child),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('MH04 submits search and changes category without fake data', (
    tester,
  ) async {
    final container = ProviderContainer(overrides: _overrides());
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProductListPage()),
      ),
    );
    await _settle(tester);

    await tester.enterText(
      find.byKey(const ValueKey('catalog-search-field')),
      'giày',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(container.read(catalogQueryProvider).search, 'giày');

    await tester.tap(find.byKey(ValueKey('catalog-category-$_categoryId')));
    await tester.pump();
    expect(container.read(catalogQueryProvider).categoryId, _categoryId);
    expect(find.text('Giày chạy bộ đường dài'), findsOneWidget);
  });

  testWidgets('MH04 navigates to MH05 using the product ID route', (
    tester,
  ) async {
    final product = _product();
    final router = GoRouter(
      initialLocation: '/customer/products',
      routes: [
        GoRoute(
          path: '/customer/products',
          builder: (context, state) => const ProductListPage(),
        ),
        GoRoute(
          path: '/customer/products/:productId',
          builder: (context, state) =>
              ProductDetailsPage(productId: state.pathParameters['productId']!),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(detail: product),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    addTearDown(router.dispose);
    await _settle(tester);

    await tester.tap(find.byKey(ValueKey('catalog-product-$_productId')));
    await _settle(tester);
    expect(router.state.uri.path, '/customer/products/$_productId');
    expect(
      find.byKey(const ValueKey('catalog-product-details')),
      findsOneWidget,
    );
    expect(find.text(product.name), findsOneWidget);
  });

  testWidgets('MH05 bounds quantity per selected variant', (tester) async {
    final product = _product(
      variants: [
        const ProductVariant(
          id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          productId: _productId,
          sku: 'RUN-40',
          label: 'Đen / 40',
          attributes: {'Màu': 'Đen', 'Cỡ': '40'},
          priceVnd: 850000,
          availableQuantity: 2,
        ),
        const ProductVariant(
          id: _secondVariantId,
          productId: _productId,
          sku: 'RUN-41',
          label: 'Đen / 41',
          attributes: {'Màu': 'Đen', 'Cỡ': '41'},
          priceVnd: 870000,
          availableQuantity: 0,
        ),
      ],
    );
    await tester.pumpWidget(
      _host(
        child: ProductDetailsPage(productId: product.id),
        overrides: _overrides(detail: product),
      ),
    );
    await _settle(tester);

    expect(find.text('850.000 đ'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('catalog-quantity-increase')),
    );
    await tester.tap(find.byKey(const ValueKey('catalog-quantity-increase')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('catalog-quantity-value')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(ValueKey('catalog-variant-$_secondVariantId')),
    );
    await tester.tap(find.byKey(ValueKey('catalog-variant-$_secondVariantId')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('catalog-quantity-value')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );
    expect(find.text('870.000 đ'), findsOneWidget);
  });

  testWidgets('MH04 renders loading, error and empty states', (tester) async {
    final pending = Completer<CatalogPage>();
    await tester.pumpWidget(
      _host(
        child: const ProductListPage(),
        overrides: _overrides(loader: () => pending.future),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('catalog-products-loading')),
      findsOneWidget,
    );
    pending.complete(CatalogPage(products: const [], hasMore: false));
    await _settle(tester);
    expect(
      find.byKey(const ValueKey('catalog-products-empty')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      _host(
        child: const ProductListPage(),
        overrides: _overrides(
          loader: () async => throw StateError('private backend detail'),
        ),
      ),
    );
    await _settle(tester);
    expect(
      find.byKey(const ValueKey('catalog-products-error')),
      findsOneWidget,
    );
    expect(find.text('private backend detail'), findsNothing);
    expect(
      find.text('Không tải được sản phẩm. Vui lòng thử lại.'),
      findsOneWidget,
    );
  });

  testWidgets('MH04 and MH05 remain usable at 320px with text scale 2', (
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

    await tester.pumpWidget(
      _host(child: const ProductListPage(), overrides: _overrides()),
    );
    await _settle(tester);
    expect(find.text('Giày chạy bộ đường dài'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final product = _product();
    await tester.pumpWidget(
      _host(
        child: ProductDetailsPage(productId: product.id),
        overrides: _overrides(detail: product),
      ),
    );
    await _settle(tester);
    expect(find.text(product.name), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
