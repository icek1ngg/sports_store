import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/cart/domain/models/cart_item.dart';
import 'package:sports_store/features/catalog/domain/models/product.dart';
import 'package:sports_store/features/catalog/domain/models/product_variant.dart';
import 'package:sports_store/features/checkout/presentation/pages/checkout_page.dart';
import 'package:sports_store/features/checkout/presentation/view_models/checkout_providers.dart';
import 'package:sports_store/features/checkout/presentation/view_models/checkout_state.dart';
import 'package:sports_store/features/checkout/presentation/view_models/checkout_address_providers.dart';
import 'package:sports_store/features/checkout/domain/models/placement_request.dart';

const _productId = '50000000-0000-4000-8000-000000000001';
const _variantId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

final _product = Product(
  id: _productId,
  categoryId: '40000000-0000-4000-8000-000000000001',
  categoryName: 'Chạy bộ',
  name: 'Giày chạy bộ',
  description: 'Giày nhẹ.',
  imagePath: null,
  variants: const [
    ProductVariant(
      id: _variantId,
      productId: _productId,
      sku: 'RUN-40',
      label: 'Đen / 40',
      attributes: {'size': '40'},
      priceVnd: 690000,
      availableQuantity: 4,
    ),
  ],
);

CartItem _item() => CartItem(
  variantId: _variantId,
  quantity: 2,
  product: _product,
  variant: _product.variants.single,
);

class _FakeCheckoutViewModel extends CheckoutViewModel {
  _FakeCheckoutViewModel(this.loader);

  final Future<CheckoutState> Function() loader;

  @override
  Future<CheckoutState> build() => loader();
}

class _Addresses implements AddressSearchRepository {
  @override
  Future<List<AddressSuggestion>> search(String query) async => const [
    AddressSuggestion(
      id: 'trang-tien',
      label: 'Tràng Tiền, Hoàn Kiếm, Hà Nội',
      latitude: 21.03,
      longitude: 105.85,
    ),
  ];
}

Widget _host(Future<CheckoutState> Function() loader) => ProviderScope(
  overrides: [
    checkoutProvider.overrideWith(() => _FakeCheckoutViewModel(loader)),
    checkoutMapTilesEnabledProvider.overrideWithValue(false),
    addressSearchRepositoryProvider.overrideWithValue(_Addresses()),
  ],
  child: const MaterialApp(home: CheckoutPage()),
);

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'MH16 uses address suggestions and confirms without a map preview',
    (tester) async {
      await tester.pumpWidget(
        _host(() async => CheckoutState(items: [_item()])),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('checkout-page')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('checkout-destination-preview-map')),
        findsNothing,
      );
      final search = find.byKey(const ValueKey('checkout-address-search'));
      await tester.ensureVisible(search);
      await tester.enterText(search, 'Tràng Tiền');
      await _tapKey(tester, 'checkout-address-search-button');
      await tester.pumpAndSettle();
      await _tapKey(tester, 'checkout-address-suggestion-trang-tien');
      await tester.pumpAndSettle();
      final detail = find.byKey(const ValueKey('checkout-address'));
      await tester.ensureVisible(detail);
      await tester.enterText(detail, 'Số 1');
      final confirm = find.byKey(const ValueKey('checkout-address-confirm'));
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text('Đã xác nhận địa chỉ nhận hàng.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('checkout-location-latitude')),
        findsNothing,
      );
      await tester.scrollUntilVisible(
        find.text('1.410.000 đ'),
        180,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('checkout-form')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('1.410.000 đ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editing the search invalidates a previously confirmed address', (
    tester,
  ) async {
    await tester.pumpWidget(_host(() async => CheckoutState(items: [_item()])));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('checkout-address-search'));
    await tester.ensureVisible(search);
    await tester.enterText(search, 'Tràng Tiền');
    await _tapKey(tester, 'checkout-address-search-button');
    await tester.pumpAndSettle();
    await _tapKey(tester, 'checkout-address-suggestion-trang-tien');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('checkout-address')),
      'Số 1',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('checkout-address-confirm')),
    );
    await _tapKey(tester, 'checkout-address-confirm');
    await tester.pumpAndSettle();
    await tester.ensureVisible(search);
    await tester.enterText(search, 'Đường khác');
    await tester.pumpAndSettle();
    expect(find.text('Đã xác nhận địa chỉ nhận hàng.'), findsNothing);
    expect(
      find.byKey(const ValueKey('checkout-selected-address')),
      findsNothing,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('checkout-address-confirm')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('MH16 handles empty cart and narrow text scale', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_host(() async => CheckoutState(items: const [])));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('checkout-empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'MH16 preserves recovery controls even when another device empties cart',
    (tester) async {
      final pending = PlacementRequest(
        requestId: '90000000-0000-4000-8000-000000000001',
        items: [PlacementItem(variantId: _variantId, quantity: 2)],
        recipientName: 'Nguyễn Văn A',
        recipientPhone: '0901234567',
        addressDetail: 'Số 1 Hà Nội',
        latitude: 21.0285,
        longitude: 105.8542,
      );
      await tester.pumpWidget(
        _host(
          () async => CheckoutState(
            items: const [],
            pendingRequest: pending,
            recoveryNotFound: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('checkout-empty')), findsNothing);
      expect(find.byKey(const ValueKey('checkout-retry')), findsOneWidget);
    },
  );

  testWidgets(
    'fallback map needs an explicit point and hides raw coordinates',
    (tester) async {
      await tester.pumpWidget(
        _host(() async => CheckoutState(items: [_item()])),
      );
      await tester.pumpAndSettle();
      final picker = find.byKey(const ValueKey('checkout-location'));
      await tester.ensureVisible(picker);
      await _tapKey(tester, 'checkout-location');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('checkout-location-latitude')),
        findsNothing,
      );
      final confirm = find.byKey(const ValueKey('checkout-location-confirm'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.drag(
        find.byKey(const ValueKey('checkout-location-map')),
        const Offset(50, -30),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await tester.pumpAndSettle();
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('checkout-location-map')), findsNothing);
    },
  );

  testWidgets('MH16 form and map remain usable at 320px and text scale 2', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(_host(() async => CheckoutState(items: [_item()])));
    await tester.pumpAndSettle();
    final picker = find.byKey(const ValueKey('checkout-location'));
    await tester.scrollUntilVisible(
      picker,
      180,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('checkout-form')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await _tapKey(tester, 'checkout-location');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('checkout-location-map')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byKey(const ValueKey('checkout-location-map')),
      const Offset(50, -30),
    );
    await tester.pumpAndSettle();
    await _tapKey(tester, 'checkout-location-confirm');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('checkout-submit')),
      180,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('checkout-form')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(tester.takeException(), isNull);
  });
}
