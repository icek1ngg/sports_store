import 'package:flutter_test/flutter_test.dart';

import 'package:sports_store/features/cod/data/models/cod_collection_dto.dart';
import 'package:sports_store/features/cod/domain/models/cod_collection.dart';

void main() {
  test('maps a valid row and preserves nullable schema fields', () {
    final domain = CodCollectionDto.fromJson(_row()).toDomain();

    expect(domain.orderId, '11111111-1111-4111-8111-111111111111');
    expect(domain.shipperId, '22222222-2222-4222-8222-222222222222');
    expect(domain.status, CodStatus.collected);
    expect(domain.expectedAmountVnd, 550000);
    expect(domain.collectedAmountVnd, 550000);
    expect(domain.receivedAmountVnd, 0);
    expect(domain.collectedBy, '33333333-3333-4333-8333-333333333333');
    expect(domain.receivedBy, isNull);
    expect(domain.collectedAt, DateTime.parse('2026-10-23T01:00:00Z'));
    expect(domain.handedOverAt, isNull);
    expect(domain.receivedAt, isNull);
    expect(domain.createdAt.isUtc, isTrue);
    expect(domain.updatedAt.isUtc, isTrue);
    expect(domain.outstandingAmountVnd, 550000);
  });

  test('accepts lossless safe integer strings', () {
    final domain = CodCollectionDto.fromJson(
      _row(
        expectedAmountVnd: '9007199254740991',
        collectedAmountVnd: '9007199254740991',
      ),
    ).toDomain();

    expect(domain.expectedAmountVnd, 9007199254740991);
  });

  test('rejects doubles, overflow and negative money values', () {
    expect(
      () => CodCollectionDto.fromJson(_row(expectedAmountVnd: 550000.0)),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CodCollectionDto.fromJson(
        _row(
          expectedAmountVnd: '9007199254740992',
          collectedAmountVnd: '9007199254740992',
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CodCollectionDto.fromJson(
        _row(expectedAmountVnd: -1, collectedAmountVnd: 0),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('enforces database amount and status constraints', () {
    expect(
      () => CodCollectionDto.fromJson(
        _row(status: 'uncollected', collectedAmountVnd: 1),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CodCollectionDto.fromJson(
        _row(status: 'collected', receivedAmountVnd: 1),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CodCollectionDto.fromJson(
        _row(
          status: 'received',
          collectedAmountVnd: 550000,
          receivedAmountVnd: 549999,
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CodCollectionDto.fromJson(_row(collectedAmountVnd: 550001)),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects rollover and timezone-less timestamps', () {
    expect(
      () => CodCollectionDto.fromJson(_row(createdAt: '2026-02-29T08:00:00Z')),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CodCollectionDto.fromJson(_row(updatedAt: '2026-10-23T08:00:00')),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CodCollectionDto.fromJson(
        _row(collectedAt: '2026-10-23T08:00:00+25:00'),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('only collected records expose an outstanding amount', () {
    final uncollected = CodCollectionDto.fromJson(
      _row(status: 'uncollected', collectedAmountVnd: 0),
    ).toDomain();
    final received = CodCollectionDto.fromJson(
      _row(status: 'received', receivedAmountVnd: 550000),
    ).toDomain();

    expect(uncollected.outstandingAmountVnd, 0);
    expect(received.outstandingAmountVnd, 0);
  });
}

Map<String, dynamic> _row({
  Object expectedAmountVnd = 550000,
  Object collectedAmountVnd = 550000,
  Object receivedAmountVnd = 0,
  String status = 'collected',
  Object? shipperId = '22222222-2222-4222-8222-222222222222',
  Object? collectedBy = '33333333-3333-4333-8333-333333333333',
  Object? receivedBy,
  Object? collectedAt = '2026-10-23T08:00:00+07:00',
  Object? handedOverAt,
  Object? receivedAt,
  Object createdAt = '2026-10-23T07:00:00Z',
  Object updatedAt = '2026-10-23T08:00:00Z',
}) {
  return {
    'order_id': '11111111-1111-4111-8111-111111111111',
    'shipper_id': shipperId,
    'status': status,
    'expected_amount_vnd': expectedAmountVnd,
    'collected_amount_vnd': collectedAmountVnd,
    'received_amount_vnd': receivedAmountVnd,
    'collected_by': collectedBy,
    'received_by': receivedBy,
    'collected_at': collectedAt,
    'handed_over_at': handedOverAt,
    'received_at': receivedAt,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}
