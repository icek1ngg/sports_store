import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/catalog/presentation/view_models/catalog_providers.dart';
import 'package:sports_store/features/catalog/presentation/widgets/catalog_image.dart';
import 'package:sports_store/features/checkout/domain/models/placement_result.dart';
import 'package:sports_store/features/checkout/presentation/pages/checkout_page.dart';
import 'package:sports_store/features/checkout/presentation/view_models/checkout_providers.dart';
import 'package:sports_store/features/checkout/presentation/view_models/checkout_state.dart';
import 'package:sports_store/features/orders/data/models/order_dto.dart';

import '../../fixtures/order_list_page_fixtures.dart';

class _Receipt extends CheckoutViewModel {
  _Receipt(this.result);
  final PlacementResult result;
  @override
  Future<CheckoutState> build() async =>
      CheckoutState(items: const [], result: result);
}

Future<Uint8List> _pixel() async {
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(const Rect.fromLTWH(0, 0, 1, 1), Paint()..color = Colors.purple);
  final picture = recorder.endRecording();
  final image = await picture.toImage(1, 1);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  for (final useExactVariant in [false, true]) {
    testWidgets(
      'receipt uses ${useExactVariant ? 'exact variant' : 'captured product'} snapshot without catalog lookup',
      (tester) async {
        const productPhoto =
            'https://encrypted-tbn0.gstatic.com/images?q=receipt-snapshot-test';
        const exactPhoto = 'asset:assets/images/order-navy.png';
        final json = listFixtureItem().toMap()
          ..['product_name'] = 'Áo Hà Nội FC 2023-24'
          ..['variant_label'] = 'Tím / L'
          ..['product_image_url'] = productPhoto
          ..['attributes'] = {
            'size': 'L',
            'color': 'Tím',
            if (useExactVariant) 'image_path': exactPhoto,
          };
        final item = OrderItemDto.fromJson(json).domain;
        final result = PlacementResult(
          order: listFixtureSummary().order,
          items: [item],
          eventId: listFixtureTimelineId,
          replayed: false,
        );
        final bytes = (await tester.runAsync(_pixel))!;
        final requested = <String>[];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              checkoutProvider.overrideWith(() => _Receipt(result)),
              catalogRepositoryProvider.overrideWith(
                (ref) => throw StateError(
                  'A historical receipt cannot fetch the current catalog',
                ),
              ),
              productImageProvider.overrideWith((ref, path) async {
                requested.add(path);
                return Uri.dataFromBytes(
                  bytes,
                  mimeType: 'image/png',
                ).toString();
              }),
            ],
            child: const MaterialApp(home: CheckoutPage()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('checkout-success')), findsOneWidget);
        final image = find.byType(CatalogProductImage);
        await tester.ensureVisible(image);
        await tester.runAsync(
          () => precacheImage(MemoryImage(bytes), tester.element(image)),
        );
        await tester.pumpAndSettle();
        final expected = useExactVariant ? exactPhoto : productPhoto;
        expect(requested, [expected]);
        expect(tester.widget<CatalogProductImage>(image).imagePath, expected);
        expect(find.text(item.productName), findsOneWidget);
        expect(find.text('${item.variantLabel} • SL: 1'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
