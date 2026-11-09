import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/catalog/presentation/view_models/catalog_providers.dart';
import 'package:sports_store/features/catalog/presentation/widgets/catalog_image.dart';

class _Images extends CachingAssetBundle {
  _Images(this.images);
  final Map<String, Uint8List> images;
  final loads = <String>[];
  @override
  Future<ByteData> load(String key) async {
    loads.add(key);
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, dynamic>{})!;
    }
    final bytes = images[key];
    if (bytes == null) throw FlutterError('Test asset is absent');
    return ByteData.sublistView(bytes);
  }
}

Future<Uint8List> _pixel(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
      .drawRect(const Rect.fromLTWH(0, 0, 1, 1), Paint()..color = color);
  final picture = recorder.endRecording();
  final image = await picture.toImage(1, 1);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

Future<void> _mount(
  WidgetTester tester,
  _Images bundle,
  String uri, {
  String? resolved,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        productImageProvider.overrideWith(
          (ref, path) async => resolved ?? path,
        ),
      ],
      child: MaterialApp(
        home: DefaultAssetBundle(
          bundle: bundle,
          child: Scaffold(
            body: CatalogProductImage(
              imagePath: uri,
              width: 120,
              height: 100,
              fit: BoxFit.contain,
              borderRadius: 4,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _decode(WidgetTester tester, _Images bundle, String path) async {
  await tester.runAsync(
    () => precacheImage(
      AssetImage(path, bundle: bundle),
      tester.element(find.byType(CatalogProductImage)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'switching color URI loads distinct bundled pixels with same presentation',
    (tester) async {
      final red = (await tester.runAsync(() => _pixel(Colors.red)))!;
      final blue = (await tester.runAsync(() => _pixel(Colors.blue)))!;
      final bundle = _Images({
        'assets/images/test_red.png': red,
        'assets/images/test_blue.png': blue,
      });
      await _mount(tester, bundle, 'asset:assets/images/test_red.png');
      await _decode(tester, bundle, 'assets/images/test_red.png');
      final first = tester.widget<Image>(find.byType(Image));
      expect(first.image, isA<AssetImage>());
      expect(
        (first.image as AssetImage).assetName,
        'assets/images/test_red.png',
      );
      expect(first.width, 120);
      expect(first.height, 100);
      expect(first.fit, BoxFit.contain);
      expect(first.semanticLabel, 'Ảnh sản phẩm');
      final redData = await tester.runAsync(
        () => tester
            .widget<RawImage>(find.byType(RawImage))
            .image!
            .toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      expect(redData!.getUint8(0), greaterThan(redData.getUint8(2)));

      await _mount(tester, bundle, 'asset:assets/images/test_blue.png');
      await _decode(tester, bundle, 'assets/images/test_blue.png');
      final second = tester.widget<Image>(find.byType(Image));
      expect(
        (second.image as AssetImage).assetName,
        'assets/images/test_blue.png',
      );
      final blueData = await tester.runAsync(
        () => tester
            .widget<RawImage>(find.byType(RawImage))
            .image!
            .toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      expect(blueData!.getUint8(2), greaterThan(blueData.getUint8(0)));
      expect(
        bundle.loads,
        containsAll([
          'assets/images/test_red.png',
          'assets/images/test_blue.png',
        ]),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid resolved asset URI renders a safe error without loading files',
    (tester) async {
      final bundle = _Images({});
      await _mount(
        tester,
        bundle,
        'asset:assets/images/good.png',
        resolved: 'asset:assets/images/%2e%2e/secret.png',
      );
      expect(find.bySemanticsLabel('Không tải được ảnh'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(bundle.loads, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing bundle image stays an error rather than a network substitute',
    (tester) async {
      final bundle = _Images({});
      await _mount(tester, bundle, 'asset:assets/images/missing.png');
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Không tải được ảnh'), findsOneWidget);
      expect(bundle.loads, contains('assets/images/missing.png'));
      expect(tester.widget<Image>(find.byType(Image)).image, isA<AssetImage>());
      expect(find.byTooltip('Thử tải lại ảnh'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
