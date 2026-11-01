import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_item_dto.dart';

import 'fixtures/delivery_dtos.dart';

void main() {
  test('authorized HTTPS image maps to delivery domain', () {
    final json = outboundItemDto()
      ..['image_url'] = 'https://example.com/ball.webp';
    final item = DeliveryTaskItemDto.fromJson(json).toDomain();
    expect(item.imageUrl, 'https://example.com/ball.webp');
  });
  test('missing or unsafe images leave task readable', () {
    for (final value in [null, '', 'http://example.com/a', 'file:///a', 42]) {
      final json = outboundItemDto()..['image_url'] = value;
      expect(DeliveryTaskItemDto.fromJson(json).toDomain().imageUrl, isNull);
    }
  });
}
