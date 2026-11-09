// Opt-in screenshot fixture; does not claim a signed-in cloud acceptance run.
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
import 'package:sports_store/features/cart/presentation/view_models/cart_providers.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_state.dart';
import 'package:sports_store/features/catalog/domain/models/product.dart';
import 'package:sports_store/features/catalog/domain/models/product_variant.dart';
import 'package:sports_store/features/catalog/presentation/pages/product_details_page.dart';
import 'package:sports_store/features/catalog/presentation/view_models/catalog_providers.dart';

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
  testWidgets('MH05 color and size reference captures', (tester) async {
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
    final base = (jsonDecode(
      File('supabase/seeds/stride_apparel_shoes_20261108.json')
          .readAsStringSync(),
    ) as List).cast<Map<String, dynamic>>();
    final palettes = (jsonDecode(
      File('supabase/seeds/stride_color_expansion_20261108.json')
          .readAsStringSync(),
    ) as List).cast<Map<String, dynamic>>();
    final images = <String, List<int>>{};
    for (final row in base) {
      images[row['image'] as String] = File(
        'build/stride_catalog_images/${row['key']}.bin',
      ).readAsBytesSync();
    }
    debugNetworkImageHttpClientProvider = () => _Images(images);
    addTearDown(() {
      debugNetworkImageHttpClientProvider = null;
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final key in ['S01', 'A02']) {
      final row = base.firstWhere((row) => row['key'] == key);
      final palette = palettes.firstWhere((row) => row['key'] == key);
      final variants = <ProductVariant>[];
      final colors = (palette['colors'] as List).cast<Map<String, dynamic>>();
      final sizes = (palette['sizes'] as List).cast<String>();
      for (var c = 0; c < colors.length; c++) {
        for (var s = 0; s < sizes.length; s++) {
          variants.add(
            ProductVariant(
              id: '$key-$c-$s',
              productId: key,
              sku: 'demo-$key-$c-$s',
              label: '${colors[c]['name']} / ${sizes[s]}',
              attributes: {
                'color': colors[c]['name'],
                'color_hex': colors[c]['hex'],
                'size': sizes[s],
              },
              priceVnd: row['price_vnd'] as int,
              availableQuantity: c == 0 && s == sizes.length - 1 ? 0 : 12,
            ),
          );
        }
      }
      final product = Product(
        id: key,
        categoryId: row['category'] as String,
        categoryName: row['category'] == 'shoes' ? 'Giày thể thao' : 'Quần áo',
        name: row['name'] as String,
        description: '[DEMO] Giá, tồn và lựa chọn màu dùng để minh họa.',
        imagePath: row['image'] as String,
        variants: variants,
      );
      for (final size in [
        const Size(390, 1400),
        const Size(390, 844),
        const Size(320, 800),
      ]) {
        tester.view.physicalSize = size;
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              productDetailsProvider.overrideWith((ref, id) async => product),
              productImageProvider.overrideWith((ref, path) async => path),
              cartProvider.overrideWith(_Cart.new),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: RepaintBoundary(
                key: captureKey,
                child: ProductDetailsPage(productId: key),
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
            'build/product_details_${key}_${size.width.toInt()}x${size.height.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          bitmap.dispose();
        });
        await tester.pumpWidget(const SizedBox());
      }
    }
    debugNetworkImageHttpClientProvider = null;
  }, skip: !enabled);
}
