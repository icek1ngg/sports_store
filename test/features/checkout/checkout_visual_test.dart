// Opt-in render fixture; no real customer or order is created.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/features/cart/domain/models/cart_item.dart';
import 'package:sports_store/features/catalog/domain/models/product.dart';
import 'package:sports_store/features/catalog/domain/models/product_variant.dart';
import 'package:sports_store/features/catalog/presentation/view_models/catalog_providers.dart';
import 'package:sports_store/features/checkout/domain/models/placement_result.dart';
import 'package:sports_store/features/checkout/presentation/pages/checkout_page.dart';
import 'package:sports_store/features/checkout/presentation/view_models/checkout_providers.dart';
import 'package:sports_store/features/checkout/presentation/view_models/checkout_state.dart';
import 'package:sports_store/features/checkout/presentation/view_models/checkout_address_providers.dart';
import 'package:sports_store/features/orders/domain/models/order.dart';
import 'package:sports_store/features/orders/domain/models/order_item.dart';
import 'package:sports_store/features/orders/domain/models/order_status.dart';

class _Addresses implements AddressSearchRepository {
  @override
  Future<List<AddressSuggestion>> search(String query) async => const [
    AddressSuggestion(
      id: 'trang-tien',
      label: 'Tràng Tiền, Hoàn Kiếm, Hà Nội',
      latitude: 21.0285,
      longitude: 105.8542,
    ),
  ];
}

class _Vm extends CheckoutViewModel {
  _Vm(this.initial);
  final CheckoutState initial;
  @override
  Future<CheckoutState> build() async => initial;
}

class _Images implements HttpClient {
  _Images(this.bytes);
  final Map<String, List<int>> bytes;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _Request(bytes[url.toString()]!);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.bytes);
  final List<int> bytes;
  @override
  Future<HttpClientResponse> close() async => _Response(bytes);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.bytes);
  final List<int> bytes;
  @override
  int get statusCode => 200;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
  }
  await tester.pumpAndSettle();
}

void main() {
  const enabled = bool.fromEnvironment('STRIDE_CAPTURE');
  testWidgets('MH16 checkout and confirmed receipt captures', (tester) async {
    await tester.runAsync(() async {
      for (final entry in {
        'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
        'Inter': 'assets/fonts/Inter-Variable.ttf',
        'BarlowCondensed': 'assets/fonts/BarlowCondensed-Bold.ttf',
      }.entries) {
        await (FontLoader(
          entry.key,
        )..addFont(rootBundle.load(entry.value))).load();
      }
    });
    final row = (jsonDecode(
      File('supabase/seeds/stride_apparel_shoes_20261108.json')
          .readAsStringSync(),
    ) as List).cast<Map<String, dynamic>>().first;
    final path = row['image'] as String;
    debugNetworkImageHttpClientProvider = () => _Images({
      path: File('build/stride_catalog_images/S01.bin').readAsBytesSync(),
    });
    addTearDown(() {
      debugNetworkImageHttpClientProvider = null;
    });
    const productId = '40000000-0000-4000-8000-000000000001';
    const variantId = '50000000-0000-4000-8000-000000000001';
    const orderId = '60000000-0000-4000-8000-000000000001';
    const owner = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    final variant = ProductVariant(
      id: variantId,
      productId: productId,
      sku: 'DEMO-S01-C1-42',
      label: 'Đỏ đen / 42',
      attributes: {'color': 'Đỏ đen', 'size': '42', 'image_path': path},
      priceVnd: 1890000,
      availableQuantity: 12,
    );
    final product = Product(
      id: productId,
      categoryId: 'shoes',
      categoryName: 'Giày',
      name: row['name'] as String,
      description: 'Dữ liệu render demo',
      imagePath: path,
      variants: [variant],
    );
    final item = CartItem(
      variantId: variantId,
      quantity: 1,
      variant: variant,
      product: product,
    );
    final stamp = DateTime.utc(2026, 11, 8, 17, 15);
    final receipt = PlacementResult(
      order: Order(
        id: orderId,
        customerId: owner,
        requestId: '90000000-0000-4000-8000-000000000001',
        status: OrderStatus.pendingConfirmation,
        recipientName: 'Văn Đức (demo)',
        recipientPhone: '0901234567',
        addressDetail: 'Số 1 Tràng Tiền, Hoàn Kiếm, Hà Nội',
        latitude: 21.0285,
        longitude: 105.8542,
        subtotalVnd: 1890000,
        deliveryFeeVnd: 30000,
        totalCodVnd: 1920000,
        deliveryAttemptCount: 0,
        placedAt: stamp,
        confirmedAt: null,
        source: null,
        confirmedBy: null,
        deliveredAt: null,
        cancelReason: null,
        createdAt: stamp,
        updatedAt: stamp,
      ),
      items: [
        OrderItem(
          id: '70000000-0000-4000-8000-000000000001',
          orderId: orderId,
          productId: productId,
          variantId: variantId,
          productName: product.name,
          variantLabel: variant.label,
          attributes: Map<String, Object?>.from(variant.attributes),
          unitPriceVnd: 1890000,
          quantity: 1,
          lineTotalVnd: 1890000,
          createdAt: stamp,
        ),
      ],
      eventId: '80000000-0000-4000-8000-000000000001',
      replayed: false,
    );
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final success in [false, true]) {
      for (final size in [
        Size(390, success ? 1400 : 1900),
        const Size(390, 844),
        const Size(320, 800),
      ]) {
        tester.view.physicalSize = size;
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              checkoutProvider.overrideWith(
                () => _Vm(
                  CheckoutState(
                    items: [item],
                    userId: owner,
                    result: success ? receipt : null,
                  ),
                ),
              ),
              checkoutMapTilesEnabledProvider.overrideWithValue(false),
              addressSearchRepositoryProvider.overrideWithValue(_Addresses()),
              productImageProvider.overrideWith((ref, path) async => path),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: RepaintBoundary(
                key: captureKey,
                child: const CheckoutPage(),
              ),
            ),
          ),
        );
        await _settle(tester);
        if (!success) {
          await tester.enterText(
            find.byKey(const ValueKey('checkout-name')),
            'Văn Đức (demo)',
          );
          await tester.enterText(
            find.byKey(const ValueKey('checkout-phone')),
            '0901234567',
          );
          Future<void> tapKey(String key) async {
            final target = find.byKey(ValueKey(key));
            await tester.ensureVisible(target);
            await _settle(tester);
            await tester.tap(target);
            await _settle(tester);
          }

          final search = find.byKey(const ValueKey('checkout-address-search'));
          await tester.ensureVisible(search);
          await tester.enterText(search, 'Tràng Tiền');
          await _settle(tester);
          await tapKey('checkout-address-search-button');
          await tapKey('checkout-address-suggestion-trang-tien');
          final detail = find.byKey(const ValueKey('checkout-address'));
          await tester.ensureVisible(detail);
          await tester.enterText(detail, 'Số 1');
          FocusManager.instance.primaryFocus?.unfocus();
          await _settle(tester);
          await tapKey('checkout-address-confirm');
          final scroll = tester.state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('checkout-form')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          scroll.position.jumpTo(0);
        }
        for (var frame = 0; frame < 10; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          });
        }
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              captureKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final bitmap = await boundary.toImage(pixelRatio: 1);
          final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'build/checkout_${success ? 'success' : 'form'}_${size.width.toInt()}x${size.height.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          bitmap.dispose();
        });
        await tester.pumpWidget(const SizedBox());
      }
    }
    debugNetworkImageHttpClientProvider = null;
  }, skip: !enabled);
}
