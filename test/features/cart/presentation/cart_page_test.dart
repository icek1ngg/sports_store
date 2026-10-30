import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/cart/domain/models/cart_failure.dart';
import 'package:sports_store/features/cart/domain/models/cart_item.dart';
import 'package:sports_store/features/cart/presentation/pages/cart_page.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_providers.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_state.dart';
import 'package:sports_store/features/cart/presentation/widgets/cart_item_tile.dart';
import 'package:sports_store/features/catalog/domain/models/product.dart';
import 'package:sports_store/features/catalog/domain/models/product_variant.dart';
import 'package:sports_store/features/catalog/presentation/view_models/catalog_providers.dart';

const _productId = '22222222-2222-4222-8222-222222222222';
const _variantId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _missingVariantId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

final _product = Product(
  id: _productId,
  categoryId: '11111111-1111-4111-8111-111111111111',
  categoryName: 'Chạy bộ',
  name: 'Giày chạy bộ đường dài',
  description: 'Thiết kế nhẹ cho những buổi chạy hằng ngày.',
  imagePath: null,
  variants: const [
    ProductVariant(
      id: _variantId,
      productId: _productId,
      sku: 'RUN-40',
      label: 'Đen / 40',
      attributes: {'Màu': 'Đen', 'Cỡ': '40'},
      priceVnd: 850000,
      availableQuantity: 4,
    ),
  ],
);

final _zeroStockVariant = ProductVariant(
  id: _variantId,
  productId: _productId,
  sku: 'RUN-40',
  label: 'Đen / 40',
  attributes: const {'Màu': 'Đen', 'Cỡ': '40'},
  priceVnd: 850000,
  availableQuantity: 0,
);

final _zeroStockProduct = Product(
  id: _productId,
  categoryId: '11111111-1111-4111-8111-111111111111',
  categoryName: 'Chạy bộ',
  name: 'Giày chạy bộ đường dài',
  description: 'Thiết kế nhẹ cho những buổi chạy hằng ngày.',
  imagePath: null,
  variants: [_zeroStockVariant],
);

CartItem _availableItem({int quantity = 1}) => CartItem(
  variantId: _variantId,
  quantity: quantity,
  product: _product,
  variant: _product.variants.first,
);

CartItem _zeroStockItem({int quantity = 2}) => CartItem(
  variantId: _variantId,
  quantity: quantity,
  product: _zeroStockProduct,
  variant: _zeroStockVariant,
);

const _unavailableItem = CartItem(variantId: _missingVariantId, quantity: 1);

class _FakeCartViewModel extends CartViewModel {
  _FakeCartViewModel(this.loader);

  final Future<CartState> Function() loader;
  int refreshCalls = 0;
  int retryCalls = 0;
  final setQuantityCalls = <({String variantId, int quantity})>[];
  final removeCalls = <String>[];

  @override
  Future<CartState> build() => loader();

  @override
  Future<void> refresh() async {
    refreshCalls++;
    state = AsyncData(await loader());
  }

  @override
  Future<bool> setQuantity({
    required String variantId,
    required int quantity,
  }) async {
    setQuantityCalls.add((variantId: variantId, quantity: quantity));
    return true;
  }

  @override
  Future<bool> removeItem(String variantId) async {
    removeCalls.add(variantId);
    return true;
  }

  @override
  Future<bool> retryPendingMutation() async {
    retryCalls++;
    return true;
  }
}

Widget _host(_FakeCartViewModel fake) {
  return ProviderScope(
    overrides: [cartProvider.overrideWith(() => fake)],
    child: const MaterialApp(home: CartPage()),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('MH06 renders loading then an empty cart with browse action', (
    tester,
  ) async {
    final completer = Completer<CartState>();
    final fake = _FakeCartViewModel(() => completer.future);
    await tester.pumpWidget(_host(fake));
    await tester.pump();
    expect(find.byKey(const ValueKey('cart-loading')), findsOneWidget);

    completer.complete(CartState(items: const []));
    await _settle(tester);
    expect(find.byKey(const ValueKey('cart-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('cart-browse')), findsOneWidget);
  });

  testWidgets('MH06 renders a safe load error and keeps refresh explicit', (
    tester,
  ) async {
    final fake = _FakeCartViewModel(
      () async => throw const CartFailure(CartFailureCode.permissionDenied),
    );
    await tester.pumpWidget(_host(fake));
    await _settle(tester);

    expect(find.byKey(const ValueKey('cart-error')), findsOneWidget);
    expect(find.text('Bạn không có quyền truy cập giỏ hàng.'), findsOneWidget);
    expect(find.text('permissionDenied'), findsNothing);
  });

  testWidgets('MH06 preserves unavailable rows and forwards mutations', (
    tester,
  ) async {
    final fake = _FakeCartViewModel(
      () async =>
          CartState(items: [_availableItem(quantity: 2), _unavailableItem]),
    );
    await tester.pumpWidget(_host(fake));
    await _settle(tester);

    expect(
      find.byKey(const ValueKey('cart-row-$_missingVariantId')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Sản phẩm hoặc biến thể này không còn được bán. Bạn có thể xóa dòng hàng.',
      ),
      findsOneWidget,
    );
    expect(find.text('850.000 đ'), findsOneWidget);
    expect(find.text('Tạm tính'), findsOneWidget);
    expect(find.text('850.000 đ'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cart-decrease-$_variantId')));
    await tester.pump();
    expect(fake.setQuantityCalls, hasLength(1));
    expect(fake.setQuantityCalls.single.quantity, 1);

    await tester.tap(
      find.byKey(const ValueKey('cart-remove-$_missingVariantId')),
    );
    await tester.pump();
    expect(fake.removeCalls, [_missingVariantId]);
  });

  testWidgets('MH06 shows pending mutation error and offers explicit retry', (
    tester,
  ) async {
    final fake = _FakeCartViewModel(
      () async => CartState(
        items: [_availableItem()],
        hasPendingMutation: true,
        mutationError: const CartFailure(CartFailureCode.network),
      ),
    );
    await tester.pumpWidget(_host(fake));
    await _settle(tester);

    expect(
      find.text(
        'Chưa xác nhận được kết quả. Vui lòng thử lại thao tác đang chờ.',
      ),
      findsOneWidget,
    );
    final increase = tester.widget<IconButton>(
      find.byKey(const ValueKey('cart-increase-$_variantId')),
    );
    expect(increase.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('cart-retry')));
    await tester.pump();
    expect(fake.retryCalls, 1);
  });

  testWidgets('MH06 keeps pending notice when the cart is empty', (
    tester,
  ) async {
    final fake = _FakeCartViewModel(
      () async => CartState(
        items: const [],
        hasPendingMutation: true,
        mutationError: const CartFailure(CartFailureCode.network),
      ),
    );
    await tester.pumpWidget(_host(fake));
    await _settle(tester);

    expect(find.byKey(const ValueKey('cart-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('cart-retry')), findsOneWidget);
    expect(
      find.text(
        'Chưa xác nhận được kết quả. Vui lòng thử lại thao tác đang chờ.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('MH06 refreshes after a definite mutation rejection', (
    tester,
  ) async {
    final fake = _FakeCartViewModel(
      () async => CartState(
        items: const [],
        mutationError: const CartFailure(CartFailureCode.insufficientStock),
      ),
    );
    await tester.pumpWidget(_host(fake));
    await _settle(tester);

    expect(find.text('Làm mới giỏ hàng'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cart-retry')));
    await tester.pump();
    expect(fake.refreshCalls, 1);
    expect(fake.retryCalls, 0);
  });

  testWidgets('MH06 disables retry while a mutation is running', (
    tester,
  ) async {
    final fake = _FakeCartViewModel(
      () async => CartState(
        items: const [],
        isMutating: true,
        hasPendingMutation: true,
      ),
    );
    await tester.pumpWidget(_host(fake));
    await _settle(tester);

    final retry = tester.widget<FilledButton>(
      find.byKey(const ValueKey('cart-retry')),
    );
    expect(retry.onPressed, isNull);
  });

  testWidgets('MH06 reduces directly to available stock when over limit', (
    tester,
  ) async {
    final fake = _FakeCartViewModel(
      () async => CartState(items: [_availableItem(quantity: 5)]),
    );
    await tester.pumpWidget(_host(fake));
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('cart-decrease-$_variantId')));
    await tester.pump();
    expect(fake.setQuantityCalls.single.quantity, 4);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('cart-decrease-$_variantId')),
          )
          .tooltip,
      'Giảm còn 4',
    );
  });

  testWidgets('MH06 disables decrement when stock is zero', (tester) async {
    final fake = _FakeCartViewModel(
      () async => CartState(items: [_zeroStockItem(quantity: 2)]),
    );
    await tester.pumpWidget(_host(fake));
    await _settle(tester);

    final decrease = tester.widget<IconButton>(
      find.byKey(const ValueKey('cart-decrease-$_variantId')),
    );
    expect(decrease.onPressed, isNull);
    expect(fake.setQuantityCalls, isEmpty);
  });

  testWidgets('MH06 remains usable at 320px with text scale 2', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final fake = _FakeCartViewModel(
      () async => CartState(items: [_availableItem(quantity: 2)]),
    );
    await tester.pumpWidget(_host(fake));
    await _settle(tester);

    expect(find.byKey(const ValueKey('cart-page')), findsOneWidget);
    expect(find.text('Giày chạy bộ đường dài'), findsOneWidget);
    expect(find.byKey(const ValueKey('cart-subtotal')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MH06 keeps a failed product thumbnail compact at text scale 2', (
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

    const imagePath = 'products/failed-thumbnail.jpg';
    final product = Product(
      id: _product.id,
      categoryId: _product.categoryId,
      categoryName: _product.categoryName,
      name: _product.name,
      description: _product.description,
      imagePath: imagePath,
      variants: _product.variants,
    );
    final item = CartItem(
      variantId: _variantId,
      quantity: 1,
      product: product,
      variant: _product.variants.first,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productImageProvider(imagePath)
              .overrideWith((ref) async => throw StateError('image failed')),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CartItemTile(
              item: item,
              mutationsEnabled: true,
              onIncrease: () {},
              onDecrease: () {},
              onRemove: () {},
            ),
          ),
        ),
      ),
    );
    await _settle(tester);

    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
