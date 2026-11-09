// Storage manifest validation plus opt-in checks of local admin upload sources.
// flutter test --dart-define=STRIDE_COLOR_ASSETS_READY=true \
//   test/features/catalog/color_assets_manifest_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  const enabled = bool.fromEnvironment('STRIDE_COLOR_ASSETS_READY');
  test('52 private Storage paths cover all 340 existing demo variants', () {
    final rows = (jsonDecode(
      File('supabase/seeds/stride_color_images_20261109.json')
          .readAsStringSync(),
    ) as List).cast<Map<String, dynamic>>();
    expect(rows.length, 52);
    final byProduct = <String, Set<int>>{};
    final objectPaths = <String>{};
    var variants = 0;
    for (final row in rows) {
      final key = row['key'] as String;
      final index = row['color_index'] as int;
      final path = row['image_path'] as String;
      final fileName = path.split('/').last;
      expect(row['bucket'], 'product-images');
      expect(path, 'demo/stride-colors-20261109/$fileName');
      expect(
        fileName,
        matches(
          RegExp(
            r'^stride_color_20261109_(S0[1-5]|A0[1-8])_C[1-4]\.(png|jpg|webp)$',
          ),
        ),
      );
      expect(row['local_source'], 'assets/images/$fileName');
      expect(row['image_paths'], [path]);
      expect(row['image_color'], row['color']);
      expect(objectPaths.add(path), isTrue);
      (byProduct[key] ??= <int>{}).add(index);
      variants += (row['sizes'] as List).length;
    }
    expect(variants, 340);
    expect(byProduct.length, 13);
    for (final indices in byProduct.values) {
      expect(indices, {1, 2, 3, 4});
    }
    expect(
      rows.where((row) => row['image_source'] == 'ai_color_preview').length,
      40,
    );
  });
  testWidgets(
    'all 52 local upload sources decode with four distinct color previews per product',
    (tester) async {
      await tester.runAsync(() async {
        final rows = (jsonDecode(
          await File('supabase/seeds/stride_color_images_20261109.json')
              .readAsString(),
        ) as List).cast<Map<String, dynamic>>();
        expect(rows.length, 52);
        expect(
          rows.where((row) => row['image_source'] == 'ai_color_preview').length,
          40,
        );
        expect(
          rows
              .where((row) => row['image_source'] == 'catalog_reference')
              .length,
          12,
        );
        final paths = <String>{};
        final colorsByProduct = <String, Set<int>>{};
        final pixelsByProduct = <String, Set<String>>{};
        for (final row in rows) {
          final product = row['key'] as String;
          final color = row['color_index'] as int;
          final path = row['image_path'] as String;
          final reason = '$product / C$color';
          expect(
            paths.add(path),
            isTrue,
            reason: 'Duplicate storage object: $reason',
          );
          expect(row['image_paths'], [path], reason: reason);
          final isAi = color != 1 || product == 'S02';
          expect(
            row['image_source'],
            isAi ? 'ai_color_preview' : 'catalog_reference',
            reason: reason,
          );
          if (product == 'S02' && color == 1) {
            expect(
              path,
              'demo/stride-colors-20261109/stride_color_20261109_S02_C1.png',
            );
          }
          final source = row['local_source'] as String;
          final bytes = await File(source).readAsBytes();
          expect(bytes.lengthInBytes, greaterThan(0), reason: reason);
          final codec = await ui.instantiateImageCodec(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
            targetWidth: 32,
            targetHeight: 32,
          );
          try {
            final frame = await codec.getNextFrame();
            try {
              expect(frame.image.width, 32, reason: reason);
              expect(frame.image.height, 32, reason: reason);
              final rgba = await frame.image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              expect(rgba, isNotNull, reason: 'No decoded pixels: $reason');
              expect(rgba!.lengthInBytes, 32 * 32 * 4, reason: reason);
              final fingerprint = base64Encode(
                rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
              );
              (pixelsByProduct[product] ??= <String>{}).add(fingerprint);
              (colorsByProduct[product] ??= <int>{}).add(color);
            } finally {
              frame.image.dispose();
            }
          } finally {
            codec.dispose();
          }
        }
        expect(colorsByProduct.keys.toSet(), {
          'S01',
          'S02',
          'S03',
          'S04',
          'S05',
          'A01',
          'A02',
          'A03',
          'A04',
          'A05',
          'A06',
          'A07',
          'A08',
        });
        for (final product in colorsByProduct.keys) {
          expect(colorsByProduct[product], {1, 2, 3, 4}, reason: product);
          expect(
            pixelsByProduct[product]?.length,
            4,
            reason: '$product reuses decoded pixels across color choices',
          );
        }
      });
    },
    skip: !enabled,
  );
}
