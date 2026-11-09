// Opt-in visual evidence with real catalog seed images cached under build/.
// This is an isolated rendering fixture, not a signed-in cloud acceptance run.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/shells/customer_navigation_bar.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_providers.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_state.dart';
import 'package:sports_store/features/catalog/domain/models/catalog_page.dart';
import 'package:sports_store/features/catalog/domain/models/category.dart';
import 'package:sports_store/features/catalog/domain/models/product.dart';
import 'package:sports_store/features/catalog/domain/models/product_variant.dart';
import 'package:sports_store/features/catalog/presentation/pages/product_list_page.dart';
import 'package:sports_store/features/catalog/presentation/view_models/catalog_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';

class _Page extends CatalogListViewModel {
  _Page(this.products);
  final List<Product> products;
  @override
  Future<CatalogPage> build() async =>
      CatalogPage(products: products, hasMore: false);
}

class _Cart extends CartViewModel {
  @override
  Future<CartState> build() async => CartState(items: []);
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
  testWidgets('catalog storefront reference capture with cached seed images', (
    tester,
  ) async {
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
    final wanted = ['S01', 'A02', 'S03', 'S04', 'A01', 'A05'];
    final products = <Product>[];
    final images = <String, List<int>>{};
    for (var i = 0; i < wanted.length; i++) {
      final row = rows.firstWhere((row) => row['key'] == wanted[i]);
      final path = row['image'] as String;
      images[path] = File('build/stride_catalog_images/${row['key']}.bin')
          .readAsBytesSync();
      final id =
          '40000000-0000-4000-8000-${(i + 1).toString().padLeft(12, '0')}';
      products.add(
        Product(
          id: id,
          categoryId: row['category'] as String,
          categoryName: row['category'] == 'shoes'
              ? 'Giày thể thao'
              : 'Quần áo',
          name: row['name'] as String,
          description: row['description'] as String,
          imagePath: path,
          variants: [
            for (var j = 0; j < 2; j++)
              ProductVariant(
                id: '50000000-0000-4000-8000-${(i * 2 + j + 1).toString().padLeft(12, '0')}',
                productId: id,
                sku: 'DEMO-VISUAL-$i-$j',
                label: 'Cỡ ${j + 1}',
                attributes: {},
                priceVnd: row['price_vnd'] as int,
                availableQuantity: 10,
              ),
          ],
        ),
      );
    }
    debugNetworkImageHttpClientProvider = () => _Images(images);
    addTearDown(() {
      debugNetworkImageHttpClientProvider = null;
    });
    final captureKey = GlobalKey();
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [
      const Size(390, 1440),
      const Size(390, 844),
      const Size(320, 800),
      const Size(1024, 900),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            operationalSessionProvider.overrideWith(
              (ref) => Stream.value(
                const OperationalSession(
                  userId: 'visual-customer',
                  generation: 0,
                ),
              ),
            ),
            cartProvider.overrideWith(_Cart.new),
            catalogPageProvider.overrideWith(() => _Page(products)),
            catalogCategoriesProvider.overrideWith(
              (ref) async => const [
                Category(id: 'shoes', code: 'shoes', name: 'Giày'),
                Category(id: 'apparel', code: 'apparel', name: 'Quần áo'),
                Category(id: 'equipment', code: 'equipment', name: 'Dụng cụ'),
              ],
            ),
            productImageProvider.overrideWith((ref, path) async => path),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: RepaintBoundary(
              key: captureKey,
              child: const Scaffold(
                body: ProductListPage(),
                bottomNavigationBar: CustomerNavigationBar(
                  location: '/customer/products',
                ),
              ),
            ),
          ),
        ),
      );
      for (var frame = 0; frame < 10; frame++) {
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
          'build/catalog_storefront_${size.width.toInt()}x${size.height.toInt()}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        bitmap.dispose();
      });
      await tester.pumpWidget(const SizedBox());
    }
    debugNetworkImageHttpClientProvider = null;
  }, skip: !enabled);
}
