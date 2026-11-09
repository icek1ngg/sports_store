import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/orders/data/models/order_dto.dart';
import 'package:sports_store/features/orders/presentation/widgets/order_item_image.dart';

import '../../../fixtures/order_list_page_fixtures.dart';

void main() {
  test('legacy items without an image retain their old map shape', () {
    final legacy = listFixtureItem().toMap();
    final decoded = OrderItemDto.fromJson(legacy).domain;
    expect(decoded.productImageUrl, isNull);
    expect(decoded.toMap(), legacy);
    expect(decoded.toMap().containsKey('product_image_url'), isFalse);
    expect(orderItemImagePath(decoded), isNull);
  });

  for (final path in [
    'https://encrypted-tbn0.gstatic.com/images?q=snapshot-test',
    'product-snapshots/orders/navy-shirt.webp',
  ]) {
    test('optional product image snapshot round trips: $path', () {
      final json = listFixtureItem().toMap()
        ..['product_image_url'] = '  $path  ';
      final item = OrderItemDto.fromJson(json).domain;
      expect(item.productImageUrl, path);
      expect(orderItemImagePath(item), path);
      expect(item.toMap()['product_image_url'], path);
      final roundTrip = OrderItemDto.fromJson(item.toMap()).domain;
      expect(roundTrip, item);
      expect(roundTrip.hashCode, item.hashCode);
    });
  }

  for (final raw in <Object?>[
    null,
    42,
    true,
    const [],
    const {'url': 'https://example.test/image.jpg'},
    '',
    '   ',
    'http://example.test/image.jpg',
    'javascript:alert(1)',
    'https://user:password@example.test/image.jpg',
    'asset:assets/images/product-generic.png',
    '//example.test/image.jpg',
    '../other-image.jpg',
    'snapshots/%2e%2e/other.jpg',
    '%2fsecret.jpg',
    'snapshots/%00bad.jpg',
    r'snapshots\bad.jpg',
  ]) {
    test(
      'bad optional image is ignored without discarding the order: $raw',
      () {
        final json = listFixtureItem().toMap()..['product_image_url'] = raw;
        final item = OrderItemDto.fromJson(json).domain;
        expect(item.id, listFixtureItemId);
        expect(item.quantity, 1);
        expect(item.productImageUrl, isNull);
        expect(item.toMap().containsKey('product_image_url'), isFalse);
      },
    );
  }

  test('exact variant metadata wins over the generic product snapshot', () {
    const navy = 'asset:assets/images/stride_color_20261109_A01_C2.png';
    final json = listFixtureItem().toMap()
      ..['attributes'] = {'color': 'Xanh navy', 'image_path': navy}
      ..['product_image_url'] = 'https://example.test/generic-blue.jpg';
    final item = OrderItemDto.fromJson(json).domain;
    expect(item.productImageUrl, 'https://example.test/generic-blue.jpg');
    expect(orderItemImagePath(item), navy);
  });

  test(
    'invalid variant image falls back only to its captured product image',
    () {
      final json = listFixtureItem().toMap()
        ..['attributes'] = {'color': 'Tím', 'image_path': 'asset:../bad.png'}
        ..['product_image_url'] = 'https://example.test/captured-product.jpg';
      expect(
        orderItemImagePath(OrderItemDto.fromJson(json).domain),
        'https://example.test/captured-product.jpg',
      );
    },
  );

  test('image snapshot participates in immutable item equality', () {
    final base = listFixtureItem().toMap();
    final first = OrderItemDto.fromJson({
      ...base,
      'product_image_url': 'https://example.test/first.jpg',
    }).domain;
    final second = OrderItemDto.fromJson({
      ...base,
      'product_image_url': 'https://example.test/second.jpg',
    }).domain;
    expect(first, isNot(second));
    expect(first, isNot(listFixtureItem()));
    expect(first.productName, second.productName);
    expect(first.unitPriceVnd, second.unitPriceVnd);
  });
}
