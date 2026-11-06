import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/checkout/domain/models/placement_request.dart';

const _requestId = '90000000-0000-4000-8000-000000000001';
const _variantA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _variantB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

void main() {
  test('normalizes text and sorts variants into a stable fingerprint', () {
    final request = PlacementRequest(
      requestId: _requestId.toUpperCase(),
      items: [
        PlacementItem(variantId: _variantB.toUpperCase(), quantity: 2),
        PlacementItem(variantId: _variantA, quantity: 1),
      ],
      recipientName: '  Nguyễn Văn A  ',
      recipientPhone: '\u00a00901234567\u00a0',
      addressDetail: ' Số 1 phố Hà Nội ',
      latitude: 21.0285,
      longitude: 105.8542,
    );

    expect(request.requestId, _requestId);
    expect(request.items.map((item) => item.variantId), [_variantA, _variantB]);
    expect(request.recipientName, 'Nguyễn Văn A');
    expect(request.recipientPhone, '0901234567');
    expect(
      request.toRpcParams().keys,
      containsAll(<String>[
        'p_request_id',
        'p_items',
        'p_recipient_name',
        'p_recipient_phone',
        'p_address_detail',
        'p_latitude',
        'p_longitude',
      ]),
    );
    expect(request.fingerprint, contains('"request_id":"$_requestId"'));
    expect(
      PlacementRequest.fromJson(request.toJson()).fingerprint,
      request.fingerprint,
    );
  });

  test('rejects duplicate variants, empty cart and invalid coordinates', () {
    expect(
      () => PlacementRequest(
        requestId: _requestId,
        items: [
          PlacementItem(variantId: _variantA, quantity: 1),
          PlacementItem(variantId: _variantA, quantity: 2),
        ],
        recipientName: 'A',
        recipientPhone: '0900000000',
        addressDetail: 'Hà Nội',
        latitude: 21,
        longitude: 105,
      ),
      throwsFormatException,
    );
    expect(
      () => PlacementRequest(
        requestId: _requestId,
        items: const [],
        recipientName: 'A',
        recipientPhone: '0900000000',
        addressDetail: 'Hà Nội',
        latitude: 21,
        longitude: 105,
      ),
      throwsFormatException,
    );
    expect(
      () => PlacementItem(variantId: _variantA, quantity: 0),
      throwsFormatException,
    );
    expect(
      () => PlacementRequest(
        requestId: _requestId,
        items: [PlacementItem(variantId: _variantA, quantity: 1)],
        recipientName: 'A',
        recipientPhone: '0900000000',
        addressDetail: 'Hà Nội',
        latitude: double.nan,
        longitude: 105,
      ),
      throwsFormatException,
    );
  });
}
