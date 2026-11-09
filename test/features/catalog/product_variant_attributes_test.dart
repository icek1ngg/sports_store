import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/catalog/domain/models/product_variant.dart';

ProductVariant variant(Map<String, dynamic> attributes) => ProductVariant(
  id: 'v1',
  productId: 'p1',
  sku: 'demo',
  label: 'Legacy',
  attributes: attributes,
  priceVnd: 1000,
  availableQuantity: 2,
);

void main() {
  test('legacy and malformed optional attributes remain readable', () {
    final value = variant({'color': 3, 'size': '  ', 'color_hex': '#xyz'});
    expect(value.color, isNull);
    expect(value.size, isNull);
    expect(value.colorHex, isNull);
    expect(value.imagePaths, isEmpty);
  });

  test('exact-color gallery accepts HTTPS and private paths, deduplicates', () {
    final value = variant({
      'color': ' Xanh ',
      'size': ' 42 ',
      'color_hex': '#12aBcD',
      'image_path': 'https://images.example.com/blue.webp',
      'image_paths': [
        'https://images.example.com/blue.webp',
        'products/blue-side.webp',
        'http://unsafe.example.com/a',
        'javascript:alert(1)',
        '//unsafe.example.com/a',
        '../secret',
        'products/%2e%2e/a',
        'https://user:password@example.com/a',
        'bad\u0000path',
        5,
      ],
    });
    expect(value.color, 'Xanh');
    expect(value.size, '42');
    expect(value.colorHex, '#12aBcD');
    expect(value.imagePaths, [
      'https://images.example.com/blue.webp',
      'products/blue-side.webp',
    ]);
    expect(() => value.imagePaths.add('other'), throwsUnsupportedError);
  });

  test('optional gallery works without a primary photograph', () {
    final value = variant({
      'image_paths': ['products/front.png'],
    });
    expect(value.imagePath, isNull);
    expect(value.imagePaths, ['products/front.png']);
  });
  test(
    'bundled image paths are explicit and reject unsafe asset URI forms',
    () {
      const accepted = [
        'asset:assets/images/stride_color_20261109_A01_C2.png',
        'asset:assets/images/catalog/blue.front.webp',
        'asset:assets/images/white.jpg',
        'asset:assets/images/red.jpeg',
      ];
      const rejected = [
        'asset://assets/images/blue.png',
        'asset:/assets/images/blue.png',
        'asset:assets/icons/blue.png',
        'asset:assets/images/../blue.png',
        'asset:assets/images/blue.png?variant=red',
        'asset:assets/images/blue.png#red',
        r'asset:assets\images\blue.png',
        'asset:assets/images/%2e%2e/secret.png',
        'asset:assets/images/%252e%252e/secret.png',
        'asset:assets/images/red%2f..%2fsecret.png',
        'asset:assets/images/red%5csecret.png',
        'asset:assets/images/red%00.png',
        'asset:assets/images/red%2500.png',
        'asset:assets/images/red.svg',
        'asset:assets/images/red.png/extra',
        'ASSET:assets/images/red.png',
        'asset:assets/images/re\u0000d.png',
        'asset:assets/images/re\nd.png',
      ];
      for (final path in accepted) {
        expect(catalogAssetPath(path), path.substring('asset:'.length));
        expect(variant({'image_path': path}).imagePath, path);
      }
      for (final path in rejected) {
        expect(catalogAssetPath(path), isNull, reason: path);
        expect(variant({'image_path': path}).imagePath, isNull, reason: path);
      }
      expect(
        variant({
          'image_paths': [...accepted, ...rejected],
        }).imagePaths,
        accepted,
      );
    },
  );
}
