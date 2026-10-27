import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:sports_store/features/cod/data/models/cod_collection_page_dto.dart';
import 'package:sports_store/features/cod/data/repositories/supabase_cod_repository.dart';
import 'package:sports_store/features/cod/domain/models/cod_collection.dart';
import 'package:sports_store/features/cod/domain/models/cod_collection_query.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';

import '../support/operational_supabase_fixture.dart';

const _manager = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _shipper = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _order = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

void main() {
  test('query normalizes status filters and builds a bounded RPC payload', () {
    final query = CodCollectionQuery(
      shipperId: _shipper,
      statuses: const [CodStatus.received, CodStatus.collected],
      limit: 20,
      cursor: 'opaque',
    );
    expect(query.shipperId, _shipper);
    expect(query.statuses, [CodStatus.collected, CodStatus.received]);
    expect(query.toRpcParams(), {
      'p_shipper_id': _shipper,
      'p_order_id': null,
      'p_statuses': ['collected', 'received'],
      'p_limit': 20,
      'p_cursor': 'opaque',
    });
    expect(() => CodCollectionQuery(limit: 0), throwsA(isA<ArgumentError>()));
    expect(
      () => CodCollectionQuery(orderId: 'bad'),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => CodCollectionQuery(cursor: ' opaque '),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('maps counts and outstanding from the complete server snapshot', () {
    final page = CodCollectionPageDto.fromJson({
      'items': [_row()],
      'next_cursor': 'next',
      'filtered_total': 4,
      'counts': {'all': 4, 'uncollected': 1, 'collected': 2, 'received': 1},
      'outstanding_vnd': 550000,
      'as_of': '2026-10-25T08:00:00Z',
    }).toDomain();
    expect(page.items.single.orderCode, _order);
    expect(page.items.single.orderCodeSource, 'order_uuid');
    expect(page.filteredTotal, 4);
    expect(page.counts.collected, 2);
    expect(page.outstandingVnd, 550000);
    expect(page.nextCursor, 'next');
  });

  test('rejects page duplicates, bad counts and page-local outstanding', () {
    final base = {
      'items': [_row()],
      'next_cursor': null,
      'filtered_total': 1,
      'counts': {'all': 1, 'uncollected': 0, 'collected': 1, 'received': 0},
      'outstanding_vnd': 550000,
      'as_of': '2026-10-25T08:00:00Z',
    };
    expect(
      () => CodCollectionPageDto.fromJson({
        ...base,
        'items': [_row(), _row()],
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CodCollectionPageDto.fromJson({
        ...base,
        'counts': {'all': 0, 'uncollected': 0, 'collected': 1, 'received': 0},
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CodCollectionPageDto.fromJson({
        ...base,
        'items': [Map<String, dynamic>.from(_row())..remove('order_code')],
      }, query: CodCollectionQuery(limit: 20)),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CodCollectionPageDto.fromJson({
        ...base,
        'filtered_total': 2,
        'next_cursor': null,
      }, query: CodCollectionQuery(limit: 20)),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CodCollectionPageDto.fromJson({
        ...base,
        'as_of': '2026-02-29T08:00:00Z',
      }),
      throwsA(isA<FormatException>()),
    );
    final received = Map<String, dynamic>.from(_row())
      ..['status'] = 'received'
      ..['received_amount_vnd'] = 550000
      ..['received_by'] = _manager
      ..['received_at'] = '2026-10-25T08:00:00Z';
    final receivedPage = CodCollectionPageDto.fromJson(
      {
        ...base,
        'items': [received],
        'filtered_total': 1,
        'counts': {'all': 2, 'uncollected': 0, 'collected': 1, 'received': 1},
        'outstanding_vnd': 550000,
      },
      query: CodCollectionQuery(statuses: const [CodStatus.received]),
    ).toDomain();
    expect(receivedPage.items.single.status, CodStatus.received);
  });

  test(
    'queryCollections calls only the role-scoped RPC and maps auth errors',
    () async {
      final requests = <http.Request>[];
      final client = await fixtureClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'manager'},
          ]);
        }
        if (request.url.path.endsWith('/rpc/list_cod_collections')) {
          return jsonResponse(request, {
            'items': [_row()],
            'next_cursor': null,
            'filtered_total': 1,
            'counts': {
              'all': 1,
              'uncollected': 0,
              'collected': 1,
              'received': 0,
            },
            'outstanding_vnd': 550000,
            'as_of': '2026-10-25T08:00:00Z',
          });
        }
        return jsonResponse(request, {'error': 'unexpected'}, status: 500);
      }, userId: _manager);
      final access = OperationalReadAccess(client);
      try {
        final page = await SupabaseCodRepository(access: access)
            .queryCollections(
              CodCollectionQuery(
                orderId: _order,
                statuses: const [CodStatus.collected],
              ),
            );
        expect(page.items.single.expectedAmountVnd, 550000);
        final rpc = requests.singleWhere(
          (request) => request.url.path.endsWith('/rpc/list_cod_collections'),
        );
        final body = jsonDecode(rpc.body) as Map<String, dynamic>;
        expect(body['p_order_id'], _order);
        expect(body['p_statuses'], ['collected']);
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

  test('shipper cannot ask RPC for another shipper scope', () async {
    final client = await fixtureClient((request) async {
      if (request.url.path.endsWith('/profiles')) {
        return jsonResponse(request, [
          {'role': 'shipper'},
        ]);
      }
      return jsonResponse(request, {
        'error': 'must not be called',
      }, status: 500);
    }, userId: _shipper);
    final access = OperationalReadAccess(client);
    try {
      await expectLater(
        SupabaseCodRepository(access: access)
            .queryCollections(CodCollectionQuery(shipperId: _manager)),
        throwsA(
          isA<OperationalFailure>().having(
            (failure) => failure.code,
            'code',
            OperationalFailureCode.permissionDenied,
          ),
        ),
      );
    } finally {
      await access.dispose();
      await access.client.dispose();
    }
  });

  test('late RPC response after account switch is rejected', () async {
    final response = Completer<http.Response>();
    final client = await fixtureClient((request) async {
      if (request.url.path.endsWith('/profiles')) {
        return jsonResponse(request, [
          {'role': 'manager'},
        ]);
      }
      return response.future;
    }, userId: _manager);
    final access = OperationalReadAccess(client);
    try {
      final pending = SupabaseCodRepository(access: access)
          .queryCollections(CodCollectionQuery());
      await Future<void>.delayed(Duration.zero);
      await recoverFixtureSession(client, _shipper);
      response.complete(
        jsonResponse(requestForTest(), {
          'items': [_row()],
          'next_cursor': null,
          'filtered_total': 1,
          'counts': {'all': 1, 'uncollected': 0, 'collected': 1, 'received': 0},
          'outstanding_vnd': 550000,
          'as_of': '2026-10-25T08:00:00Z',
        }),
      );
      await expectLater(
        pending,
        throwsA(
          isA<OperationalFailure>().having(
            (failure) => failure.code,
            'code',
            OperationalFailureCode.sessionExpired,
          ),
        ),
      );
    } finally {
      await access.dispose();
      await access.client.dispose();
    }
  });

  test('listCollections rejects an account switch between RPC pages', () async {
    final second = Completer<http.Response>();
    var rpcCalls = 0;
    final client = await fixtureClient((request) async {
      if (request.url.path.endsWith('/profiles')) {
        return jsonResponse(request, [
          {'role': 'manager'},
        ]);
      }
      rpcCalls++;
      if (rpcCalls == 1) {
        return jsonResponse(
          request,
          _page(
            List<Map<String, dynamic>>.generate(
              100,
              (index) => _row(orderId: _uuidFor(100 - index)),
            ),
            nextCursor: 'next-page',
            filteredTotal: 101,
            countsAll: 101,
          ),
        );
      }
      return second.future;
    }, userId: _manager);
    final access = OperationalReadAccess(client);
    try {
      final pending = SupabaseCodRepository(access: access).listCollections();
      for (var attempt = 0; attempt < 50 && rpcCalls < 2; attempt++) {
        await Future<void>.delayed(Duration.zero);
      }
      await recoverFixtureSession(client, _shipper);
      second.complete(
        jsonResponse(
          requestForTest(),
          _page(
            [_row(orderId: _uuidFor(1))],
            filteredTotal: 101,
            countsAll: 101,
          ),
        ),
      );
      await expectLater(
        pending,
        throwsA(
          isA<OperationalFailure>().having(
            (failure) => failure.code,
            'code',
            OperationalFailureCode.sessionExpired,
          ),
        ),
      );
    } finally {
      await access.dispose();
      await access.client.dispose();
    }
  });
}

http.Request requestForTest() => http.Request(
  'POST',
  Uri.parse('https://test-fixture.invalid/rpc/list_cod_collections'),
);

Map<String, dynamic> _row({String orderId = _order}) => {
  'order_id': orderId,
  'order_code': orderId,
  'order_code_source': 'order_uuid',
  'shipper_id': _shipper,
  'status': 'collected',
  'expected_amount_vnd': 550000,
  'collected_amount_vnd': 550000,
  'received_amount_vnd': 0,
  'collected_by': _shipper,
  'received_by': null,
  'collected_at': '2026-10-25T07:00:00Z',
  'handed_over_at': null,
  'received_at': null,
  'created_at': '2026-10-25T06:00:00Z',
  'updated_at': '2026-10-25T07:00:00Z',
};

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

String _uuidFor(int index) =>
    'eeeeeeee-eeee-4eee-8eee-${index.toRadixString(16).padLeft(12, '0')}';
