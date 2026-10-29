import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sports_store/features/checkout/data/repositories/supabase_checkout_repository.dart';
import 'package:sports_store/features/checkout/domain/models/checkout_failure.dart';
import 'package:sports_store/features/checkout/domain/models/placement_request.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';

import '../support/operational_supabase_fixture.dart';

const _requestId = '90000000-0000-4000-8000-000000000001';
const _variantId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _orderId = '60000000-0000-4000-8000-000000000001';
const _eventId = '80000000-0000-4000-8000-000000000001';

final _request = PlacementRequest(
  requestId: _requestId,
  items: [PlacementItem(variantId: _variantId, quantity: 2)],
  recipientName: 'Nguyễn Văn A',
  recipientPhone: '0901234567',
  addressDetail: 'Số 1 Hà Nội',
  latitude: 21.0285,
  longitude: 105.8542,
);

Map<String, Object?> _order() => {
  'id': _orderId,
  'customer_id': shipperA,
  'request_id': _requestId,
  'status': 'pending_confirmation',
  'recipient_name': _request.recipientName,
  'recipient_phone': _request.recipientPhone,
  'address_detail': _request.addressDetail,
  'latitude': _request.latitude,
  'longitude': _request.longitude,
  'subtotal_vnd': 1380000,
  'delivery_fee_vnd': 30000,
  'total_cod_vnd': 1410000,
  'delivery_attempt_count': 0,
  'placed_at': '2026-10-26T10:00:00Z',
  'confirmed_at': null,
  'source': null,
  'confirmed_by': null,
  'delivered_at': null,
  'cancel_reason': null,
  'created_at': '2026-10-26T10:00:00Z',
  'updated_at': '2026-10-26T10:00:00Z',
};

Map<String, Object?> _item() => {
  'id': '70000000-0000-4000-8000-000000000001',
  'order_id': _orderId,
  'product_id': '50000000-0000-4000-8000-000000000001',
  'variant_id': _variantId,
  'product_name': 'Giày chạy bộ',
  'variant_label': 'Đen / 40',
  'attributes': {'size': '40'},
  'unit_price_vnd': 690000,
  'quantity': 2,
  'line_total_vnd': 1380000,
  'created_at': '2026-10-26T10:00:00Z',
};

Map<String, Object?> _success() => {
  'ok': true,
  'data': {
    'order': _order(),
    'items': [_item()],
    'event_id': _eventId,
    'replayed': false,
  },
  'error': null,
};

Future<SupabaseCheckoutRepository> _repository(
  Future<http.Response> Function(http.Request request) handler,
) async {
  final client = await fixtureClient((request) async {
    if (request.url.path.endsWith('/profiles')) {
      return jsonResponse(request, [
        {'role': 'customer'},
      ]);
    }
    return handler(request);
  });
  final access = OperationalReadAccess(client);
  addTearDown(() async {
    await access.dispose();
    await client.dispose();
  });
  return SupabaseCheckoutRepository(access: access);
}

void main() {
  test(
    'place_order sends only canonical request params and maps receipt',
    () async {
      final repository = await _repository((request) async {
        expect(request.url.path, endsWith('/rpc/place_order'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['p_request_id'], _requestId);
        expect(body['p_items'], [
          {'variant_id': _variantId, 'quantity': 2},
        ]);
        expect(body.containsKey('p_customer_id'), isFalse);
        expect(body.containsKey('p_total_vnd'), isFalse);
        return jsonResponse(request, _success());
      });

      final receipt = await repository.placeOrder(_request);
      expect(receipt.order.id, _orderId);
      expect(receipt.totalCodVnd, 1410000);
      expect(receipt.items.single.quantity, 2);
    },
  );

  test('server business error remains typed', () async {
    final repository = await _repository((request) async {
      return jsonResponse(request, {
        'ok': false,
        'data': null,
        'error': {'code': 'insufficient_stock'},
      });
    });
    await expectLater(
      repository.placeOrder(_request),
      throwsA(
        isA<CheckoutFailure>().having(
          (failure) => failure.code,
          'code',
          CheckoutFailureCode.insufficientStock,
        ),
      ),
    );
  });

  final invalidReceipts =
      <String, void Function(Map<String, dynamic>, List<dynamic>)>{
        'another customer': (order, items) => order['customer_id'] = shipperB,
        'another request': (order, items) => order['request_id'] = _eventId,
        'another recipient': (order, items) =>
            order['recipient_phone'] = '0900000000',
        'missing item': (order, items) => items.clear(),
        'duplicate variant': (order, items) =>
            items.add(Map<String, dynamic>.from(items.single as Map)),
        'different variant': (order, items) =>
            (items.single as Map)['variant_id'] = _eventId,
        'different quantity': (order, items) {
          (items.single as Map)['quantity'] = 1;
          (items.single as Map)['line_total_vnd'] = 690000;
          order['subtotal_vnd'] = 690000;
          order['total_cod_vnd'] = 720000;
        },
      };
  for (final entry in invalidReceipts.entries) {
    test('rejects receipt with ${entry.key}', () async {
      final repository = await _repository((request) async {
        final envelope =
            jsonDecode(jsonEncode(_success())) as Map<String, dynamic>;
        final data = envelope['data'] as Map<String, dynamic>;
        entry.value(
          data['order'] as Map<String, dynamic>,
          data['items'] as List<dynamic>,
        );
        return jsonResponse(request, envelope);
      });
      await expectLater(
        repository.placeOrder(_request),
        throwsA(
          isA<CheckoutFailure>().having(
            (failure) => failure.code,
            'code',
            CheckoutFailureCode.invalidData,
          ),
        ),
      );
    });
  }

  test('lookup rejects a receipt for another principal', () async {
    final repository = await _repository((request) async {
      final data = _success()['data']! as Map<String, Object?>;
      data['state'] = 'committed';
      (data['order']! as Map<String, Object?>)['customer_id'] = shipperB;
      return jsonResponse(request, {'ok': true, 'data': data, 'error': null});
    });
    await expectLater(
      repository.lookupPlacementResult(_requestId),
      throwsA(isA<CheckoutFailure>()),
    );
  });

  test(
    'lookup not_found preserves explicit null event and replay flags',
    () async {
      final repository = await _repository((request) async {
        expect(request.url.path, endsWith('/rpc/get_placement_result'));
        return jsonResponse(request, {
          'ok': true,
          'data': {
            'state': 'not_found',
            'order': null,
            'items': [],
            'event_id': null,
            'replayed': false,
          },
          'error': null,
        });
      });
      final result = await repository.lookupPlacementResult(_requestId);
      expect(result.isNotFound, isTrue);
      expect(result.eventId, isNull);
      expect(result.replayed, isFalse);
    },
  );
}
