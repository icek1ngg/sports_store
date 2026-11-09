import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/catalog/data/repositories/supabase_catalog_repository.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';

import '../support/operational_supabase_fixture.dart';

const _image = 'asset:assets/images/stride_color_20261109_A01_C2.png';

void main() {
  test('private image paths still use authenticated Storage signing', () async {
    final paths = <String>[];
    final client = await fixtureClient((request) async {
      paths.add(request.url.path);
      if (request.url.path.endsWith('/profiles')) {
        return jsonResponse(request, [
          {'role': 'customer'},
        ]);
      }
      expect(request.method, 'POST');
      expect(jsonDecode(request.body)['expiresIn'], 3600);
      return jsonResponse(request, {
        'signedURL':
            '/object/sign/product-images/products/blue.png?token=test-fixture',
      });
    });
    final access = OperationalReadAccess(client);
    addTearDown(() async {
      await access.dispose();
      await client.dispose();
    });
    final image = await SupabaseCatalogRepository(access: access)
        .getImageUrl('products/blue.png');
    expect(
      image,
      'https://test-fixture.invalid/storage/v1/object/sign/product-images/products/blue.png?token=test-fixture',
    );
    expect(paths, [
      '/rest/v1/profiles',
      '/storage/v1/object/sign/product-images/products/blue.png',
    ]);
  });

  for (final role in ['customer', 'manager']) {
    test(
      '$role resolves bundled image after profile check without signing',
      () async {
        final paths = <String>[];
        final client = await fixtureClient((request) async {
          paths.add(request.url.path);
          return jsonResponse(request, [
            {'role': role},
          ]);
        });
        final access = OperationalReadAccess(client);
        addTearDown(() async {
          await access.dispose();
          await client.dispose();
        });
        expect(
          await SupabaseCatalogRepository(access: access).getImageUrl(_image),
          _image,
        );
        expect(paths, ['/rest/v1/profiles']);
      },
    );
  }

  test('bundle resolution cannot bypass current server role', () async {
    final paths = <String>[];
    final client = await fixtureClient((request) async {
      paths.add(request.url.path);
      return jsonResponse(request, [
        {'role': 'shipper'},
      ]);
    });
    final access = OperationalReadAccess(client);
    addTearDown(() async {
      await access.dispose();
      await client.dispose();
    });
    await expectLater(
      SupabaseCatalogRepository(access: access).getImageUrl(_image),
      throwsA(
        isA<OperationalFailure>().having(
          (e) => e.code,
          'code',
          OperationalFailureCode.permissionDenied,
        ),
      ),
    );
    expect(paths, ['/rest/v1/profiles']);
  });

  test('unauthenticated bundle resolution performs no HTTP request', () async {
    final paths = <String>[];
    final client = await fixtureClient((request) async {
      paths.add(request.url.path);
      return jsonResponse(request, []);
    }, userId: null);
    final access = OperationalReadAccess(client);
    addTearDown(() async {
      await access.dispose();
      await client.dispose();
    });
    await expectLater(
      SupabaseCatalogRepository(access: access).getImageUrl(_image),
      throwsA(
        isA<OperationalFailure>().having(
          (e) => e.code,
          'code',
          OperationalFailureCode.sessionExpired,
        ),
      ),
    );
    expect(paths, isEmpty);
  });

  test(
    'account switch during authorization rejects the bundled result',
    () async {
      final started = Completer<void>();
      final response = Completer<void>();
      final paths = <String>[];
      final client = await fixtureClient((request) async {
        paths.add(request.url.path);
        started.complete();
        await response.future;
        return jsonResponse(request, [
          {'role': 'customer'},
        ]);
      });
      final access = OperationalReadAccess(client);
      addTearDown(() async {
        await access.dispose();
        await client.dispose();
      });
      final pending = SupabaseCatalogRepository(access: access)
          .getImageUrl(_image);
      final checked = expectLater(
        pending,
        throwsA(
          isA<OperationalFailure>().having(
            (e) => e.code,
            'code',
            OperationalFailureCode.sessionExpired,
          ),
        ),
      );
      await started.future;
      await recoverFixtureSession(client, shipperB);
      response.complete();
      await checked;
      expect(paths, ['/rest/v1/profiles']);
    },
  );

  test('unsafe asset URI never reaches Storage signing', () async {
    final paths = <String>[];
    final client = await fixtureClient((request) async {
      paths.add(request.url.path);
      return jsonResponse(request, [
        {'role': 'customer'},
      ]);
    });
    final access = OperationalReadAccess(client);
    addTearDown(() async {
      await access.dispose();
      await client.dispose();
    });
    final repository = SupabaseCatalogRepository(access: access);
    for (final value in [
      'asset://host/assets/images/a.png',
      'asset:assets/icons/a.png',
      'asset:assets/images/a.png?token=x',
      'asset:assets/images/a.png#x',
      'asset:assets/images/../secret.png',
      'asset:assets/images/%2e%2e/secret.png',
      'asset:assets/images/%252e%252e/secret.png',
      'asset:assets/images/a%00.png',
      r'asset:assets\\images\\a.png',
      'asset:assets/images/a.svg',
      'ASSET:assets/images/a.png',
    ]) {
      await expectLater(
        repository.getImageUrl(value),
        throwsA(
          isA<OperationalFailure>().having(
            (e) => e.code,
            'code',
            OperationalFailureCode.invalidData,
          ),
        ),
        reason: value,
      );
    }
    expect(paths, everyElement('/rest/v1/profiles'));
  });
}
