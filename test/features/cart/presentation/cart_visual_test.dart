// Opt-in render fixture using cached catalog photographs, not a live login.
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
import 'package:sports_store/app/shells/customer_navigation_bar.dart';
import 'package:sports_store/features/cart/domain/models/cart_item.dart';
import 'package:sports_store/features/cart/presentation/pages/cart_page.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_providers.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_selection_view_model.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_state.dart';
import 'package:sports_store/features/catalog/domain/models/product.dart';
import 'package:sports_store/features/catalog/domain/models/product_variant.dart';
import 'package:sports_store/features/catalog/presentation/view_models/catalog_providers.dart';

class _Cart extends CartViewModel {
  _Cart(this.items);
  final List<CartItem> items;
  @override
  Future<CartState> build() async =>
      CartState(items: items, userId: 'visual-customer');
}

class _Selection extends CartSelectionViewModel {
  @override
  CartSelectionState build() => CartSelectionState(excludedVariantIds: ['A05']);
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

void main() {
  const enabled = bool.fromEnvironment('STRIDE_CAPTURE');
  testWidgets('MH06 reference captures with selected rows', (tester) async {
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
    final rows = (jsonDecode(
      File('supabase/seeds/stride_apparel_shoes_20261108.json')
          .readAsStringSync(),
    ) as List).cast<Map<String, dynamic>>();
    final items = <CartItem>[];
    final images = <String, List<int>>{};
    for (final key in ['S01', 'A02', 'A05']) {
      final row = rows.firstWhere((r) => r['key'] == key);
      final path = row['image'] as String;
      images[path] = File('build/stride_catalog_images/$key.bin')
          .readAsBytesSync();
      final variant = ProductVariant(
        id: key,
        productId: key,
        sku: 'DEMO-$key',
        label:
            '${(row['colors'] as List).first} / ${key == 'S01' ? '42' : 'L'}',
        attributes: {
          'color': (row['colors'] as List).first,
          'size': key == 'S01' ? '42' : 'L',
        },
        priceVnd: row['price_vnd'] as int,
        availableQuantity: key == 'S01' ? 2 : 12,
      );
      final product = Product(
        id: key,
        categoryId: row['category'] as String,
        categoryName: row['category'] == 'shoes' ? 'Giày' : 'Quần áo',
        name: row['name'] as String,
        description: row['description'] as String,
        imagePath: path,
        variants: [variant],
      );
      items.add(
        CartItem(
          variantId: key,
          quantity: 1,
          product: product,
          variant: variant,
        ),
      );
    }
    debugNetworkImageHttpClientProvider = () => _Images(images);
    addTearDown(() {
      debugNetworkImageHttpClientProvider = null;
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [
      const Size(390, 1200),
      const Size(390, 844),
      const Size(320, 800),
      const Size(1024, 900),
    ]) {
      tester.view.physicalSize = size;
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            cartProvider.overrideWith(() => _Cart(items)),
            cartSelectionProvider.overrideWith(_Selection.new),
            productImageProvider.overrideWith((ref, path) async => path),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: RepaintBoundary(
              key: captureKey,
              child: const Scaffold(
                body: CartPage(),
                bottomNavigationBar: CustomerNavigationBar(
                  location: '/customer/cart',
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final bitmap = await boundary.toImage(pixelRatio: 1);
        final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'build/cart_storefront_${size.width.toInt()}x${size.height.toInt()}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        bitmap.dispose();
      });
      await tester.pumpWidget(const SizedBox());
    }
    debugNetworkImageHttpClientProvider = null;
  }, skip: !enabled);
}
