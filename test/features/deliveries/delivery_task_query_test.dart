import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sports_store/features/deliveries/data/models/delivery_task_page_dto.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/data/repositories/supabase_delivery_repository.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_query.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';

import '../support/operational_supabase_fixture.dart';
import 'fixtures/delivery_dtos.dart';

Matcher _failure(OperationalFailureCode code) =>
    isA<OperationalFailure>().having((error) => error.code, 'code', code);

Map<String, dynamic> _pagePayload({
  List<Map<String, dynamic>>? items,
  String? nextCursor,
  int filteredTotal = 4,
  int waiting = 2,
  int inTransit = 1,
  int completed = 0,
  int ungrouped = 1,
}) {
  return {
    'items': items ?? [currentTaskDto()],
    'next_cursor': nextCursor,
    'filtered_total': filteredTotal,
    'counts': {
      'waiting': waiting,
      'in_transit': inTransit,
      'completed': completed,
      'ungrouped': ungrouped,
    },
    'as_of': '2026-10-23T03:00:00Z',
  };
}

void main() {
  group('DeliveryTaskQuery', () {
    test('normalizes search and keeps the opaque cursor unchanged', () {
      final query = DeliveryTaskQuery(
        kind: DeliveryTaskKind.outbound,
        stateGroup: DeliveryTaskStateGroup.waiting,
        query: '  11111111  ',
        limit: 10,
        cursor: 'opaque.cursor+1',
      );

      expect(query.query, '11111111');
      expect(query.cursor, 'opaque.cursor+1');
      expect(query.toRpcParams(), {
        'p_kind': 'outbound',
        'p_state_group': 'waiting',
        'p_query': '11111111',
        'p_limit': 10,
        'p_cursor': 'opaque.cursor+1',
      });
    });

    test('rejects unsafe bounds before transport', () {
      expect(() => DeliveryTaskQuery(limit: 0), throwsA(isA<ArgumentError>()));
      expect(
        () => DeliveryTaskQuery(limit: 101),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => DeliveryTaskQuery(query: 'x' * 201),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => DeliveryTaskQuery(cursor: ' '),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('DeliveryTaskPageDto', () {
    test('maps full counts independently from the returned page', () {
      final query = DeliveryTaskQuery(
        kind: DeliveryTaskKind.outbound,
        stateGroup: DeliveryTaskStateGroup.waiting,
        limit: 1,
      );
      final dto = DeliveryTaskPageDto.fromJson(
        _pagePayload(filteredTotal: 2, nextCursor: 'next-page'),
        query: query,
      );
      final page = dto.toDomain();

      expect(page.items, hasLength(1));
      expect(page.filteredTotal, 2);
      expect(page.counts.waiting, 2);
      expect(page.counts.inTransit, 1);
      expect(page.counts.completed, 0);
      expect(page.counts.ungrouped, 1);
      expect(page.asOf, DateTime.parse('2026-10-23T03:00:00Z'));
      expect(page.items, isA<List<DeliveryTaskSnapshot>>());
      expect(() => page.items.clear(), throwsUnsupportedError);
    });

    test('requires first-page size and cursor to agree with the total', () {
      final query = DeliveryTaskQuery(limit: 2);
      expect(
        () => DeliveryTaskPageDto.fromJson(
          _pagePayload(
            items: [
              currentTaskDto(),
              currentTaskDto(task: '11111111-1111-4111-8111-111111111112'),
              currentTaskDto(task: '11111111-1111-4111-8111-111111111113'),
            ],
            filteredTotal: 3,
          ),
          query: query,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => DeliveryTaskPageDto.fromJson(
          _pagePayload(filteredTotal: 3),
          query: query,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => DeliveryTaskPageDto.fromJson(
          _pagePayload(filteredTotal: 1, nextCursor: 'too-many'),
          query: query,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => DeliveryTaskPageDto.fromJson(
          _pagePayload(
            items: const [],
            filteredTotal: 1,
            waiting: 1,
            inTransit: 1,
            completed: 1,
            ungrouped: 0,
          ),
          query: query,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('accepts an empty page with a full filtered total', () {
      final query = DeliveryTaskQuery(
        stateGroup: DeliveryTaskStateGroup.completed,
        cursor: 'after-first-page',
      );
      final page = DeliveryTaskPageDto.fromJson(
        _pagePayload(
          items: const [],
          nextCursor: null,
          filteredTotal: 2,
          waiting: 2,
          inTransit: 1,
          completed: 2,
          ungrouped: 1,
        ),
        query: query,
      ).toDomain();

      expect(page.items, isEmpty);
      expect(page.filteredTotal, 2);
      expect(page.counts.total, 6);
    });

    test(
      'rejects malformed counts, duplicate rows and inconsistent totals',
      () {
        expect(
          () => DeliveryTaskPageDto.fromJson(_pagePayload(filteredTotal: 0)),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => DeliveryTaskPageDto.fromJson(
            _pagePayload(
              items: [currentTaskDto(), currentTaskDto()],
              filteredTotal: 4,
            ),
          ),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => DeliveryTaskPageDto.fromJson(_pagePayload(completed: -1)),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => DeliveryTaskPageDto.fromJson(_pagePayload(filteredTotal: 5)),
          throwsA(isA<FormatException>()),
        );
      },
    );
  });

  group('SupabaseDeliveryRepository.queryTasks', () {
    test('forwards normalized filters and maps a server page', () async {
      Map<String, dynamic>? sent;
      final client = await fixtureClient((request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        expect(request.url.path, endsWith('/list_my_delivery_tasks'));
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return jsonResponse(
          request,
          _pagePayload(
            nextCursor: 'next-page',
            filteredTotal: 2,
            waiting: 2,
            inTransit: 1,
            completed: 0,
            ungrouped: 1,
          ),
        );
      });
      final access = OperationalReadAccess(client);
      addTearDown(() async {
        await access.dispose();
        await client.dispose();
      });

      final page = await SupabaseDeliveryRepository(access: access).queryTasks(
        DeliveryTaskQuery(
          kind: DeliveryTaskKind.outbound,
          stateGroup: DeliveryTaskStateGroup.waiting,
          query: ' 11111111 ',
          limit: 1,
          cursor: 'previous-page',
        ),
      );

      expect(sent, {
        'p_kind': 'outbound',
        'p_state_group': 'waiting',
        'p_query': '11111111',
        'p_limit': 1,
        'p_cursor': 'previous-page',
      });
      expect(page.nextCursor, 'next-page');
      expect(page.filteredTotal, 2);
    });

    test('returns an actual empty first page without a fallback row', () async {
      final client = await fixtureClient((request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        expect(request.url.path, endsWith('/list_my_delivery_tasks'));
        return jsonResponse(
          request,
          _pagePayload(
            items: const [],
            nextCursor: null,
            filteredTotal: 0,
            waiting: 0,
            inTransit: 0,
            completed: 0,
            ungrouped: 0,
          ),
        );
      });
      final access = OperationalReadAccess(client);
      addTearDown(() async {
        await access.dispose();
        await client.dispose();
      });

      final page = await SupabaseDeliveryRepository(access: access)
          .queryTasks(DeliveryTaskQuery());
      expect(page.items, isEmpty);
      expect(page.filteredTotal, 0);
      expect(page.nextCursor, isNull);
    });

    test(
      'maps permission, invalid-request and network failures without fallback',
      () async {
        var responseCode = '42501';
        final client = await fixtureClient((request) async {
          if (request.url.path.endsWith('/profiles')) {
            return jsonResponse(request, [
              {'role': 'shipper'},
            ]);
          }
          if (request.url.path.endsWith('/list_my_delivery_tasks')) {
            if (responseCode == 'NETWORK') {
              throw http.ClientException('offline private payload');
            }
            return jsonResponse(request, {
              'code': responseCode,
              'message': 'private payload',
            }, status: 400);
          }
          throw http.ClientException('unexpected offline request');
        });
        final access = OperationalReadAccess(client);
        addTearDown(() async {
          await access.dispose();
          await client.dispose();
        });
        final repo = SupabaseDeliveryRepository(access: access);

        await expectLater(
          repo.queryTasks(DeliveryTaskQuery()),
          throwsA(_failure(OperationalFailureCode.permissionDenied)),
        );
        responseCode = '22023';
        await expectLater(
          repo.queryTasks(DeliveryTaskQuery()),
          throwsA(_failure(OperationalFailureCode.invalidData)),
        );
        responseCode = 'NETWORK';
        await expectLater(
          repo.queryTasks(DeliveryTaskQuery()),
          throwsA(_failure(OperationalFailureCode.network)),
        );
      },
    );

    test('does not publish a late page after the shipper changes', () async {
      final entered = Completer<void>();
      final late = Completer<http.Response>();
      late final http.Request oldRequest;
      final client = await fixtureClient((request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        oldRequest = request;
        entered.complete();
        return late.future;
      });
      final access = OperationalReadAccess(client);
      addTearDown(() async {
        await access.dispose();
        await client.dispose();
      });
      final pending = SupabaseDeliveryRepository(access: access)
          .queryTasks(DeliveryTaskQuery());
      final assertion = expectLater(
        pending,
        throwsA(_failure(OperationalFailureCode.sessionExpired)),
      );
      await entered.future;
      await recoverFixtureSession(client, shipperB);
      late.complete(jsonResponse(oldRequest, _pagePayload()));
      await assertion;
    });
  });
}
