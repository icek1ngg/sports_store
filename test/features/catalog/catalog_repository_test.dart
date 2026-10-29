import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sports_store/features/catalog/data/models/catalog_dto.dart';
import 'package:sports_store/features/catalog/data/repositories/supabase_catalog_repository.dart';
import 'package:sports_store/features/catalog/domain/models/catalog_query.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';

import '../support/operational_supabase_fixture.dart';

const productId = '40000000-0000-4000-8000-000000000001';
const variantId = '50000000-0000-4000-8000-000000000001';
const categoryId = '30000000-0000-4000-8000-000000000001';
Map<String, dynamic> variantRow() => {
  'id': variantId,
  'product_id': productId,
  'sku': 'RUN-40',
  'label': 'Đen / 40',
  'attributes': {'size': '40'},
  'price_vnd': '690000',
  'available_quantity': 8,
  'is_active': true,
};
Map<String, dynamic> productRow() => {
  'id': productId,
  'category_id': categoryId,
  'name': 'Giày chạy bộ',
  'description': '',
  'image_path': '',
  'is_active': true,
  'categories': {
    'id': categoryId,
    'code': 'shoes',
    'name': 'Giày',
    'is_active': true,
  },
};

void main() {
  test(
    'strict mapping rejects rounded money, missing flags and mismatched FK',
    () {
      for (final value in [690000.5, '9007199254740992', -1]) {
        expect(
          () => ProductVariantDto.fromJson(variantRow()..['price_vnd'] = value),
          throwsFormatException,
        );
      }
      expect(
        () => ProductDto.fromJson(productRow()..remove('is_active')),
        throwsFormatException,
      );
      expect(
        () => ProductDto.fromJson(
          productRow(),
          variants: [
            ProductVariantDto.fromJson(
              variantRow()..['product_id'] = categoryId,
            ),
          ],
        ).toDomain(),
        throwsFormatException,
      );
      final product = ProductDto.fromJson(
        productRow(),
        variants: [ProductVariantDto.fromJson(variantRow())],
      ).toDomain();
      expect(product.minPriceVnd, 690000);
      expect(product.imagePath, isNull);
      expect(product.availableQuantity, 8);
    },
  );

  test(
    'customer queries active catalog, escapes search, reads variants to end',
    () async {
      final seen = <http.Request>[];
      final client = await fixtureClient((request) async {
        seen.add(request);
        final path = request.url.path;
        if (path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'customer'},
          ]);
        }
        if (path.endsWith('/products')) {
          return jsonResponse(request, [productRow()]);
        }
        if (path.endsWith('/product_variants') &&
            request.url.queryParameters['id'] == null) {
          return jsonResponse(request, [variantRow()]);
        }
        return jsonResponse(request, []);
      });
      final access = OperationalReadAccess(client);
      addTearDown(() async {
        access.dispose();
        await client.dispose();
      });
      final page = await SupabaseCatalogRepository(
        access: access,
      ).getProducts(const CatalogQuery(search: '50%_', categoryId: categoryId));
      expect(page.products.single.variants.single.priceVnd, 690000);
      final query = seen
          .firstWhere((r) => r.url.path.endsWith('/products'))
          .url
          .queryParameters;
      expect(query['is_active'], 'eq.true');
      expect(query['categories.is_active'], 'eq.true');
      expect(query['category_id'], 'eq.$categoryId');
      expect(query['name'], r'ilike.%50\%\_%');
      expect(
        seen.where((r) => r.url.path.endsWith('/product_variants')).length,
        2,
      );
      expect(seen.every((r) => r.method == 'GET'), isTrue);
    },
  );

  for (final role in ['shipper', 'unknown']) {
    test('$role is denied despite manager user metadata', () async {
      var dataReads = 0;
      final client = await fixtureClient((request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': role},
          ]);
        }
        dataReads++;
        return jsonResponse(request, []);
      });
      final access = OperationalReadAccess(client);
      addTearDown(() async {
        access.dispose();
        await client.dispose();
      });
      await expectLater(
        SupabaseCatalogRepository(access: access)
            .getProducts(const CatalogQuery()),
        throwsA(isA<OperationalFailure>()),
      );
      expect(dataReads, 0);
    });
  }

  test(
    'late result from previous account is rejected before variant reads',
    () async {
      final started = Completer<void>();
      final response = Completer<void>();
      var variantReads = 0;
      final client = await fixtureClient((request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'customer'},
          ]);
        }
        if (request.url.path.endsWith('/products')) {
          started.complete();
          await response.future;
          return jsonResponse(request, [productRow()]);
        }
        variantReads++;
        return jsonResponse(request, []);
      });
      final access = OperationalReadAccess(client);
      addTearDown(() async {
        access.dispose();
        await client.dispose();
      });
      final pending = SupabaseCatalogRepository(access: access)
          .getProducts(const CatalogQuery());
      final expectation = expectLater(
        pending,
        throwsA(isA<OperationalFailure>()),
      );
      await started.future;
      await recoverFixtureSession(client, shipperB);
      response.complete();
      await expectation;
      expect(variantReads, 0);
    },
  );
}
