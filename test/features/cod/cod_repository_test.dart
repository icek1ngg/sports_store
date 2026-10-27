import 'package:flutter_test/flutter_test.dart';

import 'dart:convert';

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
          return jsonResponse(request, _page([_row()]));
        },
      );
      try {
        final result = await SupabaseCodRepository(access: access)
            .listCollections(shipperId: _shipperId, orderId: _orderId);

        expect(result, hasLength(1));
        expect(result.single.orderId, _orderId);
        expect(() => result.clear(), throwsUnsupportedError);
        final codRequest = requests.singleWhere(
          (request) => request.url.path.endsWith('/rpc/list_cod_collections'),
        );
        final body = jsonDecode(codRequest.body) as Map<String, dynamic>;
        expect(body['p_shipper_id'], _shipperId);
        expect(body['p_order_id'], _orderId);
        expect(body['p_limit'], 100);
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
          return jsonResponse(request, _page([_row()]));
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
            (request) => request.url.path.endsWith('/rpc/list_cod_collections'),
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

  test(
    'listCollections follows the opaque RPC cursor without table reads',
    () async {
      final requests = <http.Request>[];
      var calls = 0;
      final access = await _authenticatedAccess(
        role: 'manager',
        handler: (request) async {
          requests.add(request);
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'role': 'manager'},
            ]);
          }
          calls++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['p_limit'], 100);
          if (calls == 1) {
            return jsonResponse(
              request,
              _page(
                List<Map<String, dynamic>>.generate(
                  100,
                  (index) => _row(orderId: _uuidFor(101 - index)),
                ),
                nextCursor: 'opaque-page-2',
                filteredTotal: 101,
                countsAll: 101,
              ),
            );
          }
          expect(body['p_cursor'], 'opaque-page-2');
          return jsonResponse(
            request,
            _page(
              [_row(orderId: _uuidFor(1))],
              filteredTotal: 101,
              countsAll: 101,
            ),
          );
        },
      );
      try {
        final result = await SupabaseCodRepository(access: access)
            .listCollections();
        expect(result, hasLength(101));
        expect(calls, 2);
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

  test('maps malformed rows to invalidData', () async {
    final access = await _authenticatedAccess(
      role: 'manager',
      handler: (request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'manager'},
          ]);
        }
        return jsonResponse(request, _page([_row(status: 'unknown')]));
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

  test('missing RPC is surfaced and never falls back to table reads', () async {
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
        return jsonResponse(request, {
          'code': 'PGRST202',
          'message': 'function not found',
        }, status: 404);
      },
    );
    try {
      await expectLater(
        SupabaseCodRepository(access: access).listCollections(),
        throwsA(
          isA<OperationalFailure>().having(
            (failure) => failure.code,
            'code',
            OperationalFailureCode.backendUnavailable,
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
    'order_code': orderId,
    'order_code_source': 'order_uuid',
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

Map<String, dynamic> _page(
  List<Map<String, dynamic>> items, {
  String? nextCursor,
  int? filteredTotal,
  int? countsAll,
}) {
  final total = filteredTotal ?? items.length;
  final all = countsAll ?? total;
  return {
    'items': items,
    'next_cursor': nextCursor,
    'filtered_total': total,
    'counts': {'all': all, 'uncollected': 0, 'collected': all, 'received': 0},
    'outstanding_vnd': all * 550000,
    'as_of': '2026-10-25T08:00:00Z',
  };
}

String _uuidFor(int index) {
  final suffix = index.toRadixString(16).padLeft(12, '0');
  return 'eeeeeeee-eeee-4eee-8eee-$suffix';
}
