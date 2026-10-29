import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sports_store/features/catalog/data/repositories/supabase_catalog_repository.dart';
import 'package:sports_store/features/catalog/domain/models/managed_product.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const userId = '10000000-0000-4000-8000-000000000001';
const productId = '20000000-0000-4000-8000-000000000001';
const categoryId = '30000000-0000-4000-8000-000000000001';
const variantId = '40000000-0000-4000-8000-000000000001';
const requestId = '50000000-0000-4000-8000-000000000001';

void main() {
  late SupabaseClient client;
  late SupabaseCatalogRepository repository;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) handler;
  http.Response json(Object? value, [int status = 200]) => http.Response(
    jsonEncode(value),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  setUp(() async {
    requests = [];
    handler = (request) async {
      if (request.url.path.endsWith('/profiles')) {
        return json({'role': 'manager'});
      }
      if (request.url.path.endsWith('/categories')) {
        return json([
          {'id': categoryId, 'name': 'Giày', 'is_active': true},
        ]);
      }
      if (request.url.path.endsWith('/product_variants')) {
        return json([
          {
            'id': variantId,
            'product_id': productId,
            'sku': 'SHOE-M',
            'label': 'Size M',
            'attributes': {'size': 'M'},
            'price_vnd': 350000,
            'on_hand': 10,
            'reserved': 3,
            'is_active': true,
          },
        ]);
      }
      return json([
        {
          'id': productId,
          'name': 'Giày chạy bộ',
          'category_id': categoryId,
          'description': 'Mô tả',
          'image_path': null,
          'is_active': true,
          'updated_at': '2026-10-29T01:00:00Z',
          'categories': {'name': 'Giày'},
          'product_variants': [
            {
              'id': variantId,
              'sku': 'SHOE-M',
              'label': 'Size M',
              'attributes': {'size': 'M'},
              'price_vnd': 350000,
              'on_hand': 10,
              'reserved': 3,
              'is_active': true,
            },
          ],
        },
      ]);
    };
    client = SupabaseClient(
      'https://catalog-test.invalid',
      'sb_publishable_test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        final response = await handler(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          request: request,
          headers: response.headers,
        );
      }),
    );
    String part(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token =
        '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': userId, 'role': 'authenticated', 'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000})}.${part('signature')}';
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': token,
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'user': {
          'id': userId,
          'aud': 'authenticated',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
    repository = SupabaseCatalogRepository(client);
  });
  tearDown(() => client.dispose());

  test('loads canonical variants, integer VND and available stock', () async {
    final snapshot = await repository.loadManagement();
    expect(snapshot.categories.single.name, 'Giày');
    final product = snapshot.products.single;
    expect(product.description, 'Mô tả');
    expect(product.minimumPrice, 350000);
    expect(product.available, 7);
    expect(product.variants.single.expectedOnHand, 10);
    expect(requests.map((r) => r.url.path), contains('/rest/v1/profiles'));
  });

  test('rejects customer before reading manager catalog', () async {
    handler = (_) async => json({'role': 'customer'});
    await expectLater(
      repository.loadManagement(),
      throwsA(isA<CatalogFailure>()),
    );
    expect(requests.length, 1);
  });

  test(
    'saves one transaction RPC preserving stock concurrency and retry key',
    () async {
      final product = (await repository.loadManagement()).products.single;
      requests.clear();
      handler = (_) async => json(productId);
      expect(
        await repository.saveProduct(product, requestId: requestId),
        productId,
      );
      expect(
        await repository.saveProduct(product, requestId: requestId),
        productId,
      );
      expect(requests.length, 2);
      expect(requests[0].url.path, '/rest/v1/rpc/save_managed_product');
      final payload = jsonDecode(requests[0].body) as Map;
      expect(payload['p_request_id'], requestId);
      expect(payload['p_expected_updated_at'], '2026-10-29T01:00:00Z');
      expect((payload['p_variants'] as List).single['expected_on_hand'], 10);
      expect(
        (payload['p_variants'] as List).single.containsKey('reserved'),
        false,
      );
      expect(requests[0].body, requests[1].body);
    },
  );

  test('zero or malformed ACK never reports successful save', () async {
    final product = (await repository.loadManagement()).products.single;
    handler = (_) async => json(null);
    await expectLater(
      repository.saveProduct(product, requestId: requestId),
      throwsA(isA<CatalogFailure>()),
    );
  });

  test('stock conflict has actionable message and no fake success', () async {
    final product = (await repository.loadManagement()).products.single;
    handler = (_) async =>
        json({'code': '40001', 'message': 'stock_changed'}, 409);
    await expectLater(
      repository.saveProduct(product, requestId: requestId),
      throwsA(
        isA<CatalogFailure>().having(
          (e) => e.message,
          'message',
          contains('tồn kho đã thay đổi'),
        ),
      ),
    );
  });

  test('definitive SKU rejection permits correction while transport failure preserves retry', () async {
    final product = (await repository.loadManagement()).products.single;
    handler = (_) async =>
        json({'code': '23505', 'message': 'duplicate SKU'}, 409);
    await expectLater(
      repository.saveProduct(product, requestId: requestId),
      throwsA(
        isA<CatalogFailure>().having(
          (e) => e.outcomeUnknown,
          'uncertain',
          false,
        ),
      ),
    );
    handler = (_) async => throw http.ClientException('connection lost');
    await expectLater(
      repository.saveProduct(product, requestId: requestId),
      throwsA(
        isA<CatalogFailure>().having(
          (e) => e.outcomeUnknown,
          'uncertain',
          true,
        ),
      ),
    );
  });

  test('reads more than one Data API page without truncation', () async {
    final baseHandler = handler;
    handler = (request) async {
      if (!request.url.path.endsWith('/categories')) {
        return baseHandler(request);
      }
      final offset =
          int.tryParse(request.url.queryParameters['offset'] ?? '0') ?? 0;
      return json(
        List.generate(
          offset == 0 ? 500 : 1,
          (index) => {
            'id': 'category-${offset + index}',
            'name': 'Danh mục ${offset + index}',
            'is_active': true,
          },
        ),
      );
    };
    final snapshot = await repository.loadManagement();
    expect(snapshot.categories.length, 501);
    expect(requests.where((r) => r.url.path.endsWith('/categories')).length, 2);
  });
}
