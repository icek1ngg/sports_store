import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sports_store/features/cart/domain/models/cart_item.dart';
import 'package:sports_store/features/catalog/domain/models/product.dart';
import 'package:sports_store/features/catalog/domain/models/product_variant.dart';
import 'package:sports_store/features/checkout/domain/models/checkout_failure.dart';
import 'package:sports_store/features/checkout/domain/models/placement_request.dart';
import 'package:sports_store/features/checkout/domain/models/placement_result.dart';
import 'package:sports_store/features/checkout/presentation/pages/checkout_page.dart';
import 'package:sports_store/features/checkout/presentation/view_models/checkout_providers.dart';
import 'package:sports_store/features/checkout/presentation/view_models/checkout_state.dart';
import 'package:sports_store/features/orders/domain/models/order.dart';
import 'package:sports_store/features/orders/domain/models/order_item.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';

const _variantId = '50000000-0000-4000-8000-000000000001';
const _productId = '40000000-0000-4000-8000-000000000001';
const _orderId = '60000000-0000-4000-8000-000000000001';
const _requestId = '90000000-0000-4000-8000-000000000001';
final _placed = DateTime.utc(2026, 11, 8, 10, 30);

CartItem _item() {
  const variant = ProductVariant(
    id: _variantId,
    productId: _productId,
    sku: 'RUN40',
    label: 'Đen / 40',
    attributes: {'color': 'Đen', 'size': '40'},
    priceVnd: 690000,
    availableQuantity: 4,
  );
  return CartItem(
    variantId: _variantId,
    quantity: 2,
    variant: variant,
    product: Product(
      id: _productId,
      categoryId: 'category',
      categoryName: 'Giày',
      name: 'Tên trong giỏ hiện tại',
      description: null,
      imagePath: null,
      variants: [variant],
    ),
  );
}

PlacementResult _receipt() => PlacementResult(
  order: Order(
    id: _orderId,
    customerId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    requestId: _requestId,
    status: OrderStatus.preparing,
    recipientName: 'Người nhận từ máy chủ',
    recipientPhone: '0901234567',
    addressDetail: 'Số 1 Tràng Tiền, Hoàn Kiếm, Hà Nội',
    latitude: 21.0285,
    longitude: 105.8542,
    subtotalVnd: 1400000,
    deliveryFeeVnd: 30000,
    totalCodVnd: 1430000,
    deliveryAttemptCount: 0,
    placedAt: _placed,
    confirmedAt: _placed,
    source: null,
    confirmedBy: null,
    deliveredAt: null,
    cancelReason: null,
    createdAt: _placed,
    updatedAt: _placed,
  ),
  items: [
    OrderItem(
      id: '70000000-0000-4000-8000-000000000001',
      orderId: _orderId,
      productId: _productId,
      variantId: _variantId,
      productName: 'Tên sản phẩm chốt trên đơn',
      variantLabel: 'Trắng / 42',
      attributes: const {},
      unitPriceVnd: 700000,
      quantity: 2,
      lineTotalVnd: 1400000,
      createdAt: _placed,
    ),
  ],
  eventId: '80000000-0000-4000-8000-000000000001',
  replayed: false,
);

class _Vm extends CheckoutViewModel {
  _Vm(this.initial);
  final CheckoutState initial;
  int placements = 0;
  @override
  Future<CheckoutState> build() async => initial;
  @override
  Future<bool> placeOrder({
    required String recipientName,
    required String recipientPhone,
    required String addressDetail,
    required double latitude,
    required double longitude,
  }) async {
    placements++;
    return false;
  }
}

Future<_Vm> _mount(
  WidgetTester tester,
  CheckoutState state, {
  GoRouter? router,
}) async {
  final vm = _Vm(state);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        checkoutProvider.overrideWith(() => vm),
        checkoutMapTilesEnabledProvider.overrideWithValue(false),
      ],
      child: router == null
          ? const MaterialApp(home: CheckoutPage())
          : MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return vm;
}

Finder _formScroll() => find
    .descendant(
      of: find.byKey(const ValueKey('checkout-form')),
      matching: find.byType(Scrollable),
    )
    .first;

void main() {
  testWidgets(
    'submit stays visible while scrolling checkout and needs actual location',
    (tester) async {
      final vm = await _mount(tester, CheckoutState(items: [_item()]));
      final submit = find.byKey(const ValueKey('checkout-submit'));
      final initial = tester.getRect(submit);
      await tester.drag(_formScroll(), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.getRect(submit), initial);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(vm.placements, 0);
      expect(
        find.text(
          'Vui lòng nhập đủ thông tin người nhận và xác nhận địa chỉ giao hàng.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('checkout-success')), findsNothing);
    },
  );

  testWidgets(
    'pending payload stays locked and retries instead of a new placement',
    (tester) async {
      final pending = PlacementRequest(
        requestId: _requestId,
        items: [PlacementItem(variantId: _variantId, quantity: 2)],
        recipientName: 'Tên đang chờ',
        recipientPhone: '0901234567',
        addressDetail: 'Hà Nội',
        latitude: 21.0285,
        longitude: 105.8542,
      );
      await _mount(
        tester,
        CheckoutState(
          items: [_item()],
          pendingRequest: pending,
          failure: const CheckoutFailure(CheckoutFailureCode.network),
        ),
      );
      expect(find.byKey(const ValueKey('checkout-retry')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('checkout-name')))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('checkout-name')))
            .controller!
            .text,
        'Tên đang chờ',
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('checkout-submit')))
            .onPressed,
        isNull,
      );
      expect(find.byKey(const ValueKey('checkout-success')), findsNothing);
    },
  );

  testWidgets(
    'success renders server snapshots, status, Hanoi time and copies full UUID',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _mount(tester, CheckoutState(items: [_item()], result: _receipt()));
      expect(find.byKey(const ValueKey('checkout-success')), findsOneWidget);
      expect(find.text(_orderId), findsOneWidget);
      expect(find.text('Đang chuẩn bị hàng'), findsOneWidget);
      expect(find.text('Đặt lúc 08/11/2026 17:30 (Hà Nội)'), findsOneWidget);
      expect(find.text('Tên sản phẩm chốt trên đơn'), findsOneWidget);
      expect(find.text('Tên trong giỏ hiện tại'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('checkout-receipt-total')),
      );
      expect(find.text('1.430.000 đ'), findsOneWidget);
      expect(find.text('1.410.000 đ'), findsNothing);
      expect(find.text('Người nhận từ máy chủ'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('checkout-copy-order-id')),
      );
      await tester.tap(find.byKey(const ValueKey('checkout-copy-order-id')));
      await tester.pumpAndSettle();
      expect(copied, _orderId);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('view orders opens the existing customer order route', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/customer/checkout',
      routes: [
        GoRoute(
          path: '/customer/checkout',
          builder: (_, _) => const CheckoutPage(),
        ),
        GoRoute(
          path: '/customer/orders',
          builder: (_, _) => const Scaffold(body: Text('Đơn hàng của tôi')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await _mount(
      tester,
      CheckoutState(items: const [], result: _receipt()),
      router: router,
    );
    final button = find.byKey(const ValueKey('checkout-view-orders'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/customer/orders');
  });

  for (final success in [false, true]) {
    testWidgets('checkout state success=$success fits 320px at text scale 2', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await _mount(
        tester,
        CheckoutState(items: [_item()], result: success ? _receipt() : null),
      );
      expect(tester.takeException(), isNull);
      if (success) {
        await tester.ensureVisible(
          find.byKey(const ValueKey('checkout-view-orders')),
        );
      } else {
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('checkout-total')),
          200,
          scrollable: _formScroll(),
        );
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
