import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/data/repositories/supabase_delivery_repository.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';

import '../support/operational_supabase_fixture.dart';
import 'fixtures/delivery_dtos.dart';

Matcher failure(OperationalFailureCode code) =>
    isA<OperationalFailure>().having((e) => e.code, 'code', code);

Map<String, dynamic> detailPayload({
  Map<String, dynamic>? task,
  List<Map<String, dynamic>>? items,
  Object? notes,
  String notesSource = 'unavailable_schema',
  Object asOf = '2026-10-23T03:00:00Z',
}) {
  return {
    'task': task ?? currentTaskDto(),
    'items': items ?? [outboundItemDto()],
    'notes': notes,
    'notes_source': notesSource,
    'as_of': asOf,
  };
}

void main() {
  test(
    'detail repository uses one authorized snapshot RPC and binds task ID',
    () async {
      final paths = <String>[];
      final client = await fixtureClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        if (request.url.path.endsWith('/get_my_delivery_task')) {
          expect(request.body, contains(taskId));
          return jsonResponse(request, detailPayload());
        }
        fail('unexpected endpoint ${request.url.path}');
      });
      final access = OperationalReadAccess(client);
      addTearDown(() async {
        await access.dispose();
        await client.dispose();
      });
      final repo = SupabaseDeliveryRepository(access: access);
      final details = await repo.getTaskDetails(taskId);
      expect(details.items.single.quantity, 2);
      expect(details.task.amountToCollectVnd, 550000);
      expect(details.itemsAvailable, isTrue);
      expect(paths.where((p) => p.endsWith('/get_my_delivery_task')).length, 1);
      expect(
        paths.any(
          (p) =>
              p.endsWith('/read_my_delivery_tasks') ||
              p.endsWith('/read_my_delivery_task_items') ||
              p.endsWith('/orders') ||
              p.endsWith('/return_requests'),
        ),
        isFalse,
      );
      expect(details.notes, isNull);
      expect(details.notesSource.value, 'unavailable_schema');
      expect(details.asOf, DateTime.utc(2026, 10, 23, 3));
      expect(() => details.items.clear(), throwsUnsupportedError);
    },
  );

  test('history and unavailable redelivery never fabricate items', () async {
    var dto = maskedTaskDto(status: 'delivered', scope: 'history');
    final client = await fixtureClient((request) async {
      if (request.url.path.endsWith('/profiles')) {
        return jsonResponse(request, [
          {'role': 'shipper'},
        ]);
      }
      expect(request.url.path, endsWith('/get_my_delivery_task'));
      return jsonResponse(request, detailPayload(task: dto, items: const []));
    });
    final access = OperationalReadAccess(client);
    addTearDown(() async {
      await access.dispose();
      await client.dispose();
    });
    final repo = SupabaseDeliveryRepository(access: access);
    final historical = await repo.getTaskDetails(taskId);
    expect(historical.task.destination, isNull);
    expect(historical.itemsAvailable, isFalse);
    dto = currentTaskDto(
      kind: 'redelivery',
      returnRequest: returnRequestId,
      amount: 0,
      itemSource: 'unavailable_redelivery_plan',
    );
    final redelivery = await repo.getTaskDetails(taskId);
    expect(redelivery.items, isEmpty);
    expect(redelivery.itemsAvailable, isFalse);
    expect(
      redelivery.task.itemSource,
      DeliveryItemSource.unavailableRedeliveryPlan,
    );
  });

  test(
    'empty deep link, invalid ID and malformed data are typed failures',
    () async {
      Object response = <Object>[];
      var taskCalls = 0;
      final client = await fixtureClient((request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        taskCalls++;
        return jsonResponse(request, response);
      });
      final access = OperationalReadAccess(client);
      addTearDown(() async {
        await access.dispose();
        await client.dispose();
      });
      final repo = SupabaseDeliveryRepository(access: access);
      await expectLater(
        repo.getTask('not-a-uuid'),
        throwsA(failure(OperationalFailureCode.invalidData)),
      );
      expect(taskCalls, 0);
      await expectLater(
        repo.getTask(taskId),
        throwsA(failure(OperationalFailureCode.staleAssignment)),
      );
      response = [currentTaskDto()..['amount_to_collect_vnd'] = 1.5];
      await expectLater(
        repo.listTasks(),
        throwsA(failure(OperationalFailureCode.invalidData)),
      );
      response = {'data': []};
      await expectLater(
        repo.listTasks(),
        throwsA(failure(OperationalFailureCode.invalidData)),
      );
    },
  );

  test('server errors never become empty or demo success', () async {
    var code = '42501';
    final client = await fixtureClient((request) async {
      if (request.url.path.endsWith('/profiles')) {
        return jsonResponse(request, [
          {'role': 'shipper'},
        ]);
      }
      return jsonResponse(request, {
        'code': code,
        'message': 'private server payload',
      }, status: 403);
    });
    final access = OperationalReadAccess(client);
    addTearDown(() async {
      await access.dispose();
      await client.dispose();
    });
    final repo = SupabaseDeliveryRepository(access: access);
    for (final entry in {
      '42501': OperationalFailureCode.permissionDenied,
      'PGRST301': OperationalFailureCode.sessionExpired,
      'PGRST202': OperationalFailureCode.backendUnavailable,
    }.entries) {
      code = entry.key;
      await expectLater(repo.listTasks(), throwsA(failure(entry.value)));
    }
  });

  test('missing session and server-owned role gate requests', () async {
    var calls = 0;
    final client = await fixtureClient((request) async {
      calls++;
      expect(request.url.path, endsWith('/profiles'));
      return jsonResponse(request, [
        {'role': 'customer'},
      ]);
    }, userId: null);
    final access = OperationalReadAccess(client);
    addTearDown(() async {
      await access.dispose();
      await client.dispose();
    });
    final repo = SupabaseDeliveryRepository(access: access);
    await expectLater(
      repo.listTasks(),
      throwsA(failure(OperationalFailureCode.sessionExpired)),
    );
    expect(calls, 0);
    await recoverFixtureSession(client, shipperA);
    await expectLater(
      repo.listTasks(),
      throwsA(failure(OperationalFailureCode.permissionDenied)),
    );
    expect(calls, 1); // user_metadata.role=manager in the fixture was ignored.
  });

  test('late account-A data is rejected after A -> B -> A', () async {
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
    final pending = SupabaseDeliveryRepository(access: access).listTasks();
    final assertion = expectLater(
      pending,
      throwsA(failure(OperationalFailureCode.sessionExpired)),
    );
    await entered.future;
    await recoverFixtureSession(client, shipperB);
    await recoverFixtureSession(client, shipperA);
    late.complete(jsonResponse(oldRequest, [currentTaskDto()]));
    await assertion;
  });

  test('detail RPC maps a revoked assignment to staleAssignment', () async {
    final client = await fixtureClient((request) async {
      if (request.url.path.endsWith('/profiles')) {
        return jsonResponse(request, [
          {'role': 'shipper'},
        ]);
      }
      expect(request.url.path, endsWith('/get_my_delivery_task'));
      return jsonResponse(request, {
        'code': 'P0002',
        'message': 'not found or forbidden',
      }, status: 404);
    });
    final access = OperationalReadAccess(client);
    addTearDown(() async {
      await access.dispose();
      await client.dispose();
    });
    await expectLater(
      SupabaseDeliveryRepository(access: access).getTaskDetails(taskId),
      throwsA(failure(OperationalFailureCode.staleAssignment)),
    );
  });

  test(
    'detail missing RPC and transport failure remain typed failures',
    () async {
      var mode = 'missing';
      final client = await fixtureClient((request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        expect(request.url.path, endsWith('/get_my_delivery_task'));
        if (mode == 'network') {
          throw http.ClientException('private endpoint payload');
        }
        return jsonResponse(request, {
          'code': 'PGRST202',
          'message': 'function not found',
        }, status: 404);
      });
      final access = OperationalReadAccess(client);
      addTearDown(() async {
        await access.dispose();
        await client.dispose();
      });
      final repo = SupabaseDeliveryRepository(access: access);
      await expectLater(
        repo.getTaskDetails(taskId),
        throwsA(failure(OperationalFailureCode.backendUnavailable)),
      );
      mode = 'network';
      await expectLater(
        repo.getTaskDetails(taskId),
        throwsA(failure(OperationalFailureCode.network)),
      );
    },
  );

  test('late detail snapshot is rejected after an account switch', () async {
    final entered = Completer<void>();
    final late = Completer<http.Response>();
    late final http.Request oldRequest;
    final client = await fixtureClient((request) async {
      if (request.url.path.endsWith('/profiles')) {
        return jsonResponse(request, [
          {'role': 'shipper'},
        ]);
      }
      expect(request.url.path, endsWith('/get_my_delivery_task'));
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
        .getTaskDetails(taskId);
    final assertion = expectLater(
      pending,
      throwsA(failure(OperationalFailureCode.sessionExpired)),
    );
    await entered.future;
    await recoverFixtureSession(client, shipperB);
    await recoverFixtureSession(client, shipperA);
    late.complete(jsonResponse(oldRequest, detailPayload()));
    await assertion;
  });

  test('network errors are standardized and contain no raw payload', () async {
    final client = await fixtureClient((request) async {
      throw http.ClientException('private token and address');
    });
    final access = OperationalReadAccess(client);
    addTearDown(() async {
      await access.dispose();
      await client.dispose();
    });
    await expectLater(
      SupabaseDeliveryRepository(access: access).listTasks(),
      throwsA(failure(OperationalFailureCode.network)),
    );
    expect(
      mapOperationalFailure(http.ClientException('secret')).toString(),
      isNot(contains('secret')),
    );
  });

  test('paging reads beyond first API cap without duplicate IDs', () async {
    var taskReads = 0;
    final client = await fixtureClient((request) async {
      if (request.url.path.endsWith('/profiles')) {
        return jsonResponse(request, [
          {'role': 'shipper'},
        ]);
      }
      final cursor = request.url.queryParameters['task_id'];
      final offset = cursor == null ? 0 : 200;
      expect(request.url.queryParameters['offset'], isNull);
      if (cursor != null) {
        expect(cursor, 'gt.11111111-1111-4111-8111-0000000000c8');
      }
      taskReads++;
      return jsonResponse(
        request,
        List.generate(offset == 0 ? 200 : 1, (index) {
          final suffix = (offset + index + 1)
              .toRadixString(16)
              .padLeft(12, '0');
          return currentTaskDto(task: '11111111-1111-4111-8111-$suffix');
        }),
      );
    });
    final access = OperationalReadAccess(client);
    addTearDown(() async {
      await access.dispose();
      await client.dispose();
    });
    expect(
      (await SupabaseDeliveryRepository(access: access).listTasks()).length,
      201,
    );
    expect(taskReads, 2);
  });

  test('task keyset does not skip surviving rows after previous-page removals', () async {
    final all = List.generate(
      201,
      (i) => currentTaskDto(
        task:
            '11111111-1111-4111-8111-${(i + 1).toRadixString(16).padLeft(12, '0')}',
      ),
    );
    var page = 0;
    final client = await fixtureClient((request) async {
      if (request.url.path.endsWith('/profiles')) {
        return jsonResponse(request, [
          {'role': 'shipper'},
        ]);
      }
      page++;
      if (page == 1) return jsonResponse(request, all.take(200).toList());
      final surviving = all.skip(150);
      final cursor = request.url.queryParameters['task_id']!.substring(3);
      expect(request.url.queryParameters['offset'], isNull);
      return jsonResponse(
        request,
        surviving
            .where((row) => (row['task_id'] as String).compareTo(cursor) > 0)
            .toList(),
      );
    });
    final access = OperationalReadAccess(client);
    addTearDown(() async {
      await access.dispose();
      await client.dispose();
    });
    final tasks = await SupabaseDeliveryRepository(access: access).listTasks();
    expect(tasks.last.taskId, all.last['task_id']);
    expect(tasks.length, 201);
  });

  test('detail snapshot accepts the complete server item array without paging', () async {
    final all = List.generate(
      201,
      (i) => outboundItemDto()
        ..['item_id'] =
            '44444444-4444-4444-8444-${(i + 1).toRadixString(16).padLeft(12, '0')}',
    );
    var detailCalls = 0;
    final client = await fixtureClient((request) async {
      if (request.url.path.endsWith('/profiles')) {
        return jsonResponse(request, [
          {'role': 'shipper'},
        ]);
      }
      expect(request.url.path, endsWith('/get_my_delivery_task'));
      detailCalls++;
      return jsonResponse(request, detailPayload(items: all));
    });
    final access = OperationalReadAccess(client);
    addTearDown(() async {
      await access.dispose();
      await client.dispose();
    });
    final details = await SupabaseDeliveryRepository(access: access)
        .getTaskDetails(taskId);
    expect(details.items.last.itemId, all.last['item_id']);
    expect(details.items.length, 201);
    expect(detailCalls, 1);
  });
}
