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

void main() {
  test(
    'real repository calls only P01.1 RPCs and binds item task ID',
    () async {
      final paths = <String>[];
      final client = await fixtureClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        if (request.url.path.endsWith('/read_my_delivery_task_items')) {
          expect(request.body, contains(taskId));
          return jsonResponse(request, [outboundItemDto()]);
        }
        expect(request.url.path, endsWith('/read_my_delivery_tasks'));
        return jsonResponse(request, [currentTaskDto()]);
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
      expect(
        paths.where((p) => p.endsWith('/read_my_delivery_tasks')).length,
        2,
      );
      expect(
        paths.any(
          (p) => p.endsWith('/orders') || p.endsWith('/return_requests'),
        ),
        isFalse,
      );
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
      expect(request.url.path, endsWith('/read_my_delivery_tasks'));
      return jsonResponse(request, [dto]);
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

  test(
    'assignment/scope changes during item loading discard old items',
    () async {
      var taskReads = 0;
      final client = await fixtureClient((request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        if (request.url.path.endsWith('/read_my_delivery_task_items')) {
          return jsonResponse(request, [outboundItemDto()]);
        }
        return jsonResponse(
          request,
          ++taskReads == 1 ? [currentTaskDto()] : [],
        );
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
    },
  );

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

  test('item keyset reads remaining items despite earlier-page removals', () async {
    final all = List.generate(
      201,
      (i) => outboundItemDto()
        ..['item_id'] =
            '44444444-4444-4444-8444-${(i + 1).toRadixString(16).padLeft(12, '0')}',
    );
    var page = 0;
    final client = await fixtureClient((request) async {
      if (request.url.path.endsWith('/profiles')) {
        return jsonResponse(request, [
          {'role': 'shipper'},
        ]);
      }
      if (request.url.path.endsWith('/read_my_delivery_tasks')) {
        return jsonResponse(request, [currentTaskDto()]);
      }
      page++;
      if (page == 1) return jsonResponse(request, all.take(200).toList());
      final cursor = request.url.queryParameters['item_id']!.substring(3);
      return jsonResponse(
        request,
        all
            .skip(150)
            .where((row) => (row['item_id'] as String).compareTo(cursor) > 0)
            .toList(),
      );
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
  });
}
