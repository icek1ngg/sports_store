import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sports_store/features/cart/data/models/cart_item_dto.dart';
import 'package:sports_store/features/cart/data/repositories/supabase_cart_repository.dart';
import 'package:sports_store/features/cart/domain/models/cart_failure.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';

import '../catalog/catalog_repository_test.dart'
    show productRow, variantRow, variantId;
import '../support/operational_supabase_fixture.dart';

Map<String, dynamic> _variant() => variantRow()..['products'] = productRow();
Map<String, dynamic> _row({int quantity = 2, bool available = true}) => {
  'customer_id': shipperA,
  'variant_id': variantId,
  'quantity': quantity,
  'product_variants': available ? _variant() : null,
};
Map<String, dynamic> _receipt(int quantity) => {
  'customer_id': shipperA,
  'variant_id': variantId,
  'quantity': quantity,
};

Future<SupabaseCartRepository> _repository(
  Future<http.Response> Function(http.Request) handler, {
  String? userId = shipperA,
}) async {
  final client = await fixtureClient(handler, userId: userId);
  final access = OperationalReadAccess(client);
  addTearDown(() async {
    await access.dispose();
    await client.dispose();
  });
  return SupabaseCartRepository(access: access);
}

void main() {
  test('mapping retains hidden rows and rejects malformed ownership/money', () {
    final unavailable = CartItemDto.fromJson(
      _row(available: false),
      customerId: shipperA,
    );
    expect(unavailable.isAvailable, isFalse);
    expect(unavailable.quantity, 2);
    expect(unavailable.lineTotalVnd, isNull);
    expect(
      () => CartItemDto.fromJson(_row(), customerId: shipperB),
      throwsFormatException,
    );
    expect(
      () => CartItemDto.fromJson(_row(quantity: 0), customerId: shipperA),
      throwsFormatException,
    );
    final invalid = _row()
      ..['product_variants'] = (_variant()..['price_vnd'] = 1.5);
    expect(
      () => CartItemDto.fromJson(invalid, customerId: shipperA),
      throwsFormatException,
    );
    expect(
      CartItemDto.fromJson(_row(), customerId: shipperA).lineTotalVnd,
      1380000,
    );
  });

  test(
    'reads owner-scoped pages to exhaustion and keeps unavailable rows',
    () async {
      final requests = <http.Request>[];
      final repository = await _repository((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'customer'},
          ]);
        }
        return jsonResponse(
          request,
          request.url.queryParameters['variant_id'] == null
              ? [_row(available: false)]
              : [],
        );
      });
      final items = await repository.getItems();
      expect(items.single.isAvailable, isFalse);
      final queries = requests
          .where((r) => r.url.path.endsWith('/cart_items'))
          .toList();
      expect(queries.length, 2);
      expect(
        queries.every(
          (r) => r.url.queryParameters['customer_id'] == 'eq.$shipperA',
        ),
        isTrue,
      );
      expect(
        queries.first.url.queryParameters['select'],
        isNot(contains('!inner')),
      );
      expect(queries.last.url.queryParameters['variant_id'], 'gt.$variantId');
    },
  );

  test(
    'repeated set uses absolute quantity and only permitted update column',
    () async {
      final writes = <http.Request>[];
      final repository = await _repository((request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'customer'},
          ]);
        }
        if (request.url.path.endsWith('/product_variants')) {
          return jsonResponse(request, [_variant()]);
        }
        writes.add(request);
        return jsonResponse(request, [_receipt(3)]);
      });
      await repository.setQuantity(variantId: variantId, quantity: 3);
      await repository.setQuantity(variantId: variantId, quantity: 3);
      expect(writes.length, 2);
      for (final request in writes) {
        expect(request.method, 'PATCH');
        expect(jsonDecode(request.body), {'quantity': 3});
        expect(request.url.path, endsWith('/cart_items'));
        expect(request.url.queryParameters['customer_id'], 'eq.$shipperA');
        expect(request.url.queryParameters['variant_id'], 'eq.$variantId');
      }
    },
  );

  test(
    'insert collision retries same absolute target without key-column upsert',
    () async {
      var patches = 0;
      final repository = await _repository((request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'customer'},
          ]);
        }
        if (request.url.path.endsWith('/product_variants')) {
          return jsonResponse(request, [_variant()]);
        }
        if (request.method == 'PATCH') {
          patches++;
          return jsonResponse(request, patches == 1 ? [] : [_receipt(3)]);
        }
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {
          'customer_id': shipperA,
          'variant_id': variantId,
          'quantity': 3,
        });
        expect(request.url.queryParameters.containsKey('on_conflict'), isFalse);
        return jsonResponse(request, {
          'code': '23505',
          'message': 'fixture duplicate',
        }, status: 409);
      });
      await repository.setQuantity(variantId: variantId, quantity: 3);
      expect(patches, 2);
    },
  );

  test('insufficient stock is a definite failure before any write', () async {
    var writes = 0;
    final repository = await _repository((request) async {
      if (request.url.path.endsWith('/profiles')) {
        return jsonResponse(request, [
          {'role': 'customer'},
        ]);
      }
      if (request.method != 'GET') writes++;
      return jsonResponse(request, [_variant()]);
    });
    await expectLater(
      repository.setQuantity(variantId: variantId, quantity: 9),
      throwsA(
        isA<CartFailure>().having(
          (e) => e.code,
          'code',
          CartFailureCode.insufficientStock,
        ),
      ),
    );
    expect(writes, 0);
  });

  test(
    'write receipt must acknowledge exact customer, variant and target',
    () async {
      final repository = await _repository((request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'customer'},
          ]);
        }
        if (request.url.path.endsWith('/product_variants')) {
          return jsonResponse(request, [_variant()]);
        }
        return jsonResponse(request, [_receipt(4)]);
      });
      await expectLater(
        repository.setQuantity(variantId: variantId, quantity: 3),
        throwsA(isA<CartFailure>()),
      );
    },
  );

  for (final role in ['manager', 'shipper', 'unknown']) {
    test('$role cannot read or mutate cart despite user metadata', () async {
      var dataRequests = 0;
      final repository = await _repository((request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': role},
          ]);
        }
        dataRequests++;
        return jsonResponse(request, []);
      });
      await expectLater(repository.getItems(), throwsA(isA<CartFailure>()));
      await expectLater(
        repository.removeItem(variantId),
        throwsA(isA<CartFailure>()),
      );
      expect(dataRequests, 0);
    });
  }

  test('signed-out session makes no cart request', () async {
    var requests = 0;
    final repository = await _repository((request) async {
      requests++;
      return jsonResponse(request, []);
    }, userId: null);
    await expectLater(repository.getItems(), throwsA(isA<CartFailure>()));
    expect(requests, 0);
  });

  test(
    'switching account while authorizing prevents the old mutation',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var writes = 0;
      final client = await fixtureClient((request) async {
        if (request.url.path.endsWith('/profiles')) {
          started.complete();
          await release.future;
          return jsonResponse(request, [
            {'role': 'customer'},
          ]);
        }
        writes++;
        return jsonResponse(request, []);
      });
      final access = OperationalReadAccess(client);
      addTearDown(() async {
        await access.dispose();
        await client.dispose();
      });
      final repository = SupabaseCartRepository(access: access);
      final pending = repository.removeItem(variantId);
      final assertion = expectLater(
        pending,
        throwsA(
          isA<CartFailure>().having(
            (e) => e.code,
            'code',
            CartFailureCode.sessionExpired,
          ),
        ),
      );
      await started.future;
      await recoverFixtureSession(client, shipperB);
      release.complete();
      await assertion;
      expect(writes, 0);
    },
  );
}
