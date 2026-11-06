import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sports_store/features/catalog/data/repositories/supabase_product_image_repository.dart';
import 'package:sports_store/features/catalog/domain/models/managed_product.dart';
import 'package:sports_store/features/catalog/domain/models/product_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/operational_supabase_fixture.dart';

const _requestId = '11111111-1111-4111-8111-111111111111';
final _pngBytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0]);

void main() {
  test('image validation uses bytes rather than a file extension', () {
    expect(SelectedProductImage.fromBytes(_pngBytes).contentType, 'image/png');
    expect(
      () => SelectedProductImage.fromBytes(
        Uint8List.fromList(utf8.encode('<svg/>')),
      ),
      throwsA(isA<CatalogFailure>()),
    );
    expect(
      () => SelectedProductImage.fromBytes(
        Uint8List(SelectedProductImage.maxBytes + 1),
      ),
      throwsA(isA<CatalogFailure>()),
    );
    expect(
      () => SelectedProductImage.fromBytes(Uint8List(0)),
      throwsA(isA<CatalogFailure>()),
    );
  });

  late SupabaseClient client;
  late SupabaseProductImageRepository repository;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) handler;
  setUp(() async {
    requests = [];
    handler = (request) async {
      if (request.url.path.endsWith('/profiles')) {
        return jsonResponse(request, {'role': 'manager'});
      }
      if (request.url.path.contains('/object/sign/')) {
        return jsonResponse(request, {
          'signedURL':
              '/object/sign/product-images/$shipperA/$_requestId.png?token=test',
        });
      }
      return jsonResponse(request, {
        'Key': 'product-images/$shipperA/$_requestId.png',
      });
    };
    client = await fixtureClient((request) async {
      requests.add(request);
      return handler(request);
    });
    repository = SupabaseProductImageRepository(client);
  });
  tearDown(() => client.dispose());

  test(
    'manager upload stores unique private path and signs the preview',
    () async {
      final image = await repository.uploadImage(
        SelectedProductImage.fromBytes(_pngBytes),
        requestId: _requestId,
      );
      expect(image.path, '$shipperA/$_requestId.png');
      expect(
        image.previewUrl,
        contains('/storage/v1/object/sign/product-images/'),
      );
      final upload = requests[1];
      expect(
        upload.url.path,
        '/storage/v1/object/product-images/$shipperA/$_requestId.png',
      );
      expect(upload.headers['x-upsert'], 'false');
      expect(
        upload.headers['Authorization'],
        'Bearer ${client.auth.currentSession!.accessToken}',
      );
      expect(latin1.decode(upload.bodyBytes), contains('image/png'));
      expect(jsonDecode(requests[2].body)['expiresIn'], 3600);
    },
  );

  test('customer role cannot upload even with manager user metadata', () async {
    handler = (request) async => jsonResponse(request, {'role': 'customer'});
    await expectLater(
      repository.uploadImage(
        SelectedProductImage.fromBytes(_pngBytes),
        requestId: _requestId,
      ),
      throwsA(
        isA<CatalogFailure>().having(
          (e) => e.message,
          'message',
          contains('Chỉ quản lý'),
        ),
      ),
    );
    expect(requests.length, 1);
  });

  test('storage failure is not reported as success or leaked to UI', () async {
    handler = (request) async => request.url.path.endsWith('/profiles')
        ? jsonResponse(request, {'role': 'manager'})
        : jsonResponse(request, {
            'statusCode': '403',
            'message': 'private server diagnostic',
            'error': 'Forbidden',
          }, status: 403);
    await expectLater(
      repository.uploadImage(
        SelectedProductImage.fromBytes(_pngBytes),
        requestId: _requestId,
      ),
      throwsA(
        isA<CatalogFailure>().having(
          (e) => e.message,
          'message',
          isNot(contains('private')),
        ),
      ),
    );
    expect(requests.length, 2);
  });

  test(
    'lost upload response has no automatic retry or signed success',
    () async {
      handler = (request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, {'role': 'manager'});
        }
        throw http.ClientException('connection lost');
      };
      await expectLater(
        repository.uploadImage(
          SelectedProductImage.fromBytes(_pngBytes),
          requestId: _requestId,
        ),
        throwsA(isA<CatalogFailure>()),
      );
      expect(requests.length, 2);
    },
  );

  test(
    'account switch during upload discards result without signing',
    () async {
      final started = Completer<void>();
      final response = Completer<http.Response>();
      handler = (request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, {'role': 'manager'});
        }
        started.complete();
        return response.future;
      };
      final pending = repository.uploadImage(
        SelectedProductImage.fromBytes(_pngBytes),
        requestId: _requestId,
      );
      final check = expectLater(pending, throwsA(isA<CatalogFailure>()));
      await started.future;
      await recoverFixtureSession(client, shipperB);
      response.complete(
        jsonResponse(requests.last, {
          'Key': 'product-images/$shipperA/$_requestId.png',
        }),
      );
      await check;
      expect(requests.length, 2);
    },
  );

  test('unexpected upload receipt never produces a preview', () async {
    handler = (request) async => jsonResponse(
      request,
      request.url.path.endsWith('/profiles')
          ? {'role': 'manager'}
          : {'Key': 'product-images/wrong-object.png'},
    );
    await expectLater(
      repository.uploadImage(
        SelectedProductImage.fromBytes(_pngBytes),
        requestId: _requestId,
      ),
      throwsA(isA<CatalogFailure>()),
    );
    expect(requests.length, 2);
  });
}
