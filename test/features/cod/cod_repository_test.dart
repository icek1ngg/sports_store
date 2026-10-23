import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:sports_store/features/cod/data/repositories/supabase_cod_repository.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';

import '../support/operational_supabase_fixture.dart';

const _managerId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _shipperId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _otherShipperId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _orderId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

void main() {
  test(
    'lists manager rows with fixed projection, filters and ordering',
    () async {
      final requests = <http.Request>[];
      final access = await _authenticatedAccess(
        role: 'manager',
        handler: (request) async {
          requests.add(request);
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'role': 'manager'},
            ]);
          }
          return jsonResponse(request, [_row()]);
        },
      );
      try {
        final result = await SupabaseCodRepository(access: access)
            .listCollections(shipperId: _shipperId, orderId: _orderId);

        expect(result, hasLength(1));
        expect(result.single.orderId, _orderId);
        expect(() => result.clear(), throwsUnsupportedError);
        final codRequest = requests.singleWhere(
          (request) => request.url.path.endsWith('/cod_collections'),
        );
        expect(
          codRequest.url.queryParameters['select'],
          'order_id,shipper_id,status,expected_amount_vnd,collected_amount_vnd,received_amount_vnd,collected_by,received_by,collected_at,handed_over_at,received_at,created_at,updated_at',
        );
        expect(codRequest.url.queryParameters['shipper_id'], 'eq.$_shipperId');
        expect(codRequest.url.queryParameters['order_id'], 'eq.$_orderId');
        expect(
          codRequest.url.queryParameters['order'],
          'created_at.desc.nullslast,order_id.desc.nullslast',
        );
        expect(codRequest.url.queryParameters['offset'], isNull);
        expect(codRequest.url.queryParameters['limit'], '200');
      } finally {
        await access.dispose();
        await access.client.dispose();
      }
    },
  );

  test(
    'rejects a shipper filter for another shipper before COD query',
    () async {
      final requests = <http.Request>[];
      final access = await _authenticatedAccess(
        role: 'shipper',
        handler: (request) async {
          requests.add(request);
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'role': 'shipper'},
            ]);
          }
          return jsonResponse(request, [_row()]);
        },
      );
      try {
        await expectLater(
          SupabaseCodRepository(access: access)
              .listCollections(shipperId: _otherShipperId),
          throwsA(
            isA<OperationalFailure>().having(
              (failure) => failure.code,
              'code',
              OperationalFailureCode.permissionDenied,
            ),
          ),
        );
        expect(
          requests.where(
            (request) => request.url.path.endsWith('/cod_collections'),
          ),
          isEmpty,
        );
      } finally {
        await access.dispose();
        await access.client.dispose();
      }
    },
  );

  test('rejects malformed filters before opening a session read', () async {
    final requests = <http.Request>[];
    final access = await _authenticatedAccess(
      role: 'manager',
      handler: (request) async {
        requests.add(request);
        return jsonResponse(request, [
          {'role': 'manager'},
        ]);
      },
    );

    try {
      await expectLater(
        SupabaseCodRepository(access: access)
            .listCollections(orderId: 'bad-id'),
        throwsA(
          isA<OperationalFailure>().having(
            (failure) => failure.code,
            'code',
            OperationalFailureCode.invalidData,
          ),
        ),
      );
      expect(requests, isEmpty);
    } finally {
      await access.dispose();
      await access.client.dispose();
    }
  });

  test('uses a keyset cursor across page mutations and timestamp ties', () async {
    final requests = <http.Request>[];
    final firstPage = List<Map<String, dynamic>>.generate(
      200,
      (index) => _row(
        orderId: _uuidFor(201 - index),
        createdAt: '2026-10-23T07:00:00Z',
        updatedAt: '2026-10-23T08:00:00Z',
      ),
    );
    final secondPage = [
      _row(
        orderId: _uuidFor(1),
        createdAt: '2026-10-23T07:00:00Z',
        updatedAt: '2026-10-23T08:00:00Z',
      ),
    ];
    var rowsMutated = false;
    final access = await _authenticatedAccess(
      role: 'manager',
      handler: (request) async {
        requests.add(request);
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'manager'},
          ]);
        }
        if (request.url.queryParameters['or'] == null) {
          // A newer row is inserted and an already-read row is deleted between
          // pages. The next request must seek from the tuple cursor instead of
          // applying an offset to this changed collection.
          rowsMutated = true;
          firstPage.removeLast();
          firstPage.insert(
            0,
            _row(
              orderId: _uuidFor(202),
              createdAt: '2026-10-23T07:00:00Z',
              updatedAt: '2026-10-23T08:00:00Z',
            ),
          );
          return jsonResponse(request, firstPage.take(200).toList());
        }
        expect(rowsMutated, isTrue);
        expect(
          request.url.queryParameters['or'],
          '(created_at.lt.2026-10-23T07:00:00.000Z,'
          'and(created_at.eq.2026-10-23T07:00:00.000Z,'
          'order_id.lt.${_uuidFor(3)}))',
        );
        return jsonResponse(request, secondPage);
      },
    );
    try {
      final result = await SupabaseCodRepository(access: access)
          .listCollections();

      expect(result, hasLength(201));
      expect(result.last.orderId, _uuidFor(1));
      final codRequests = requests
          .where((request) => request.url.path.endsWith('/cod_collections'))
          .toList();
      expect(codRequests, hasLength(2));
      expect(
        codRequests.every(
          (request) => request.url.queryParameters['offset'] == null,
        ),
        isTrue,
      );
      expect(
        codRequests.every(
          (request) => request.url.queryParameters['limit'] == '200',
        ),
        isTrue,
      );
    } finally {
      await access.dispose();
      await access.client.dispose();
    }
  });

  test('maps malformed rows to invalidData', () async {
    final access = await _authenticatedAccess(
      role: 'manager',
      handler: (request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'manager'},
          ]);
        }
        return jsonResponse(request, [_row(status: 'unknown')]);
      },
    );
    try {
      await expectLater(
        SupabaseCodRepository(access: access).listCollections(),
        throwsA(
          isA<OperationalFailure>().having(
            (failure) => failure.code,
            'code',
            OperationalFailureCode.invalidData,
          ),
        ),
      );
    } finally {
      await access.dispose();
      await access.client.dispose();
    }
  });
}

Future<OperationalReadAccess> _authenticatedAccess({
  required String role,
  required Future<http.Response> Function(http.Request) handler,
}) async {
  final client = await fixtureClient(handler, userId: _managerId);
  final access = OperationalReadAccess(client);
  // Let the auth client's recovery event settle before issuing the read.
  await Future<void>.delayed(Duration.zero);
  // Keep the helper parameter explicit so each test documents the server role
  // selected by its response rather than putting a role in the JWT metadata.
  expect(role, anyOf('manager', 'shipper'));
  return access;
}

Map<String, dynamic> _row({
  String orderId = _orderId,
  String shipperId = _shipperId,
  String status = 'collected',
  int expectedAmountVnd = 550000,
  int collectedAmountVnd = 550000,
  int receivedAmountVnd = 0,
  String createdAt = '2026-10-23T07:00:00Z',
  String updatedAt = '2026-10-23T08:00:00Z',
}) {
  return {
    'order_id': orderId,
    'shipper_id': shipperId,
    'status': status,
    'expected_amount_vnd': expectedAmountVnd,
    'collected_amount_vnd': collectedAmountVnd,
    'received_amount_vnd': receivedAmountVnd,
    'collected_by': null,
    'received_by': null,
    'collected_at': null,
    'handed_over_at': null,
    'received_at': null,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}

String _uuidFor(int index) {
  final suffix = index.toRadixString(16).padLeft(12, '0');
  return 'eeeeeeee-eeee-4eee-8eee-$suffix';
}
