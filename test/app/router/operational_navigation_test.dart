import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:sports_store/app/router/app_router.dart';
import 'package:sports_store/app/sports_store_app.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/deliveries/fixtures/delivery_dtos.dart'
    as delivery_fixtures;
import '../../features/support/operational_supabase_fixture.dart';

const _managerId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _customerId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const _codOrderId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';

typedef FixtureDataHandler = Future<http.Response> Function(
  http.Request request,
);

Future<SupabaseClient> _roleClient(
  WidgetTester tester, {
  required String userId,
  required Map<String, String> roles,
  FixtureDataHandler? dataHandler,
}) async {
  final client = await tester.runAsync(
    () => fixtureClient((request) async {
      if (request.url.path.endsWith('/logout')) {
        return jsonResponse(request, {});
      }
      if (request.url.path.endsWith('/profiles')) {
        final profileId = _profileId(request);
        return jsonResponse(request, [
          {'role': roles[profileId]},
        ]);
      }
      if (dataHandler != null) return dataHandler(request);
      return jsonResponse(request, const <Object>[]);
    }, userId: userId),
  );
  return client!;
}

String? _profileId(http.Request request) {
  final filter = request.url.queryParameters['id'];
  if (filter == null) return null;
  return filter.startsWith('eq.') ? filter.substring(3) : filter;
}

Map<String, dynamic> _codRow({
  String order = _codOrderId,
  String shipper = shipperA,
}) {
  return {
    'order_id': order,
    'shipper_id': shipper,
    'status': 'collected',
    'expected_amount_vnd': 550000,
    'collected_amount_vnd': 550000,
    'received_amount_vnd': 0,
    'collected_by': shipper,
    'received_by': null,
    'collected_at': '2026-10-23T10:00:00+07:00',
    'handed_over_at': null,
    'received_at': null,
    'created_at': '2026-10-23T03:00:00Z',
    'updated_at': '2026-10-23T03:00:00Z',
  };
}

Future<GoRouter> _pumpApp(
  WidgetTester tester,
  SupabaseClient client, {
  WidgetBuilder? notificationBuilder,
}) async {
  final overrides = [supabaseClientProvider.overrideWithValue(client)];
  if (notificationBuilder != null) {
    overrides.add(
      notificationRouteBuilderProvider.overrideWithValue(notificationBuilder),
    );
  }
  await tester.pumpWidget(
    ProviderScope(overrides: overrides, child: const SportsStoreApp()),
  );
  await tester.pump();
  final context = tester.element(find.byType(SportsStoreApp));
  return ProviderScope.containerOf(context).read(appRouterProvider);
}

Future<void> _disposeApp(WidgetTester tester, SupabaseClient client) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  await tester.runAsync(client.dispose);
}

Future<void> _recoverForWidget(
  WidgetTester tester,
  SupabaseClient client,
  String userId,
) async {
  await tester.runAsync(() => recoverFixtureSession(client, userId));
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String description,
}) async {
  for (var attempt = 0; attempt < 150; attempt++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for $description');
}

bool _hasKey(String key) => find.byKey(ValueKey(key)).evaluate().isNotEmpty;

void _expectRoot() {
  expect(_hasKey('app-entry'), isTrue);
}

void main() {
  for (final suffix in ['', '/map']) {
    testWidgets(
      'TEST-ONLY MH17 handoff rejects revoked task destination $suffix',
      (tester) async {
        var authorized = true;
        var guardReads = 0;
        final guardRequests = <http.Request>[];
        final target = '/shipper/tasks/${delivery_fixtures.taskId}$suffix';
        final client = await _roleClient(
          tester,
          userId: shipperA,
          roles: {shipperA: 'shipper'},
          dataHandler: (request) async {
            if (request.url.path.endsWith('/read_my_delivery_tasks')) {
              guardReads++;
              guardRequests.add(request);
              return jsonResponse(
                request,
                authorized ? [delivery_fixtures.currentTaskDto()] : [],
              );
            }
            if (request.url.path.endsWith('/get_my_delivery_task')) {
              return jsonResponse(request, {
                'task': delivery_fixtures.currentTaskDto(),
                'items': [],
                'notes': null,
                'notes_source': 'unavailable_schema',
                'as_of': '2026-10-28T03:00:00Z',
              });
            }
            return jsonResponse(request, const <Object>[]);
          },
        );
        addTearDown(() => _disposeApp(tester, client));
        final router = await _pumpApp(
          tester,
          client,
          notificationBuilder: (context) => Scaffold(
            body: Column(
              children: [
                const Text(
                  'TEST-ONLY MH17 handoff; not the notifications screen',
                ),
                FilledButton(
                  key: const ValueKey('fixture-notification-task-link'),
                  onPressed: () => GoRouter.of(context).go(target),
                  child: const Text('Open fixture destination'),
                ),
              ],
            ),
          ),
        );
        router.go('/shipper/tasks/${delivery_fixtures.taskId}');
        await _pumpUntil(
          tester,
          () => _hasText('Nguyễn Văn A'),
          description:
              'authorized cached recipient before notification handoff',
        );
        router.go('/notifications');
        await _pumpUntil(
          tester,
          () => _hasKey('fixture-notification-task-link'),
          description: 'explicit fixture handoff',
        );
        final before = guardReads;
        authorized = false;
        await tester.tap(
          find.byKey(const ValueKey('fixture-notification-task-link')),
        );
        await _pumpUntil(
          tester,
          () =>
              router.state.uri.path == '/' &&
              _hasText('Ứng dụng đang được xây dựng.'),
          description: 'revoked notification destination rejected',
        );
        expect(guardReads, greaterThan(before));
        expect(
          guardRequests.every(
            (request) =>
                (jsonDecode(request.body) as Map)['p_task_id'] ==
                delivery_fixtures.taskId,
          ),
          isTrue,
        );
        expect(router.state.uri.query, isEmpty);
        expect(_hasKey('mh11-outlet'), isFalse);
        expect(_hasKey('mh18-outlet'), isFalse);
        expect(find.text('Nguyễn Văn A'), findsNothing);
      },
    );
  }
  testWidgets('pop rechecks the revealed task and rejects revoked access', (
    tester,
  ) async {
    var allowed = true;
    var reads = 0;
    final client = await _roleClient(
      tester,
      userId: shipperA,
      roles: {shipperA: 'shipper'},
      dataHandler: (request) async {
        if (request.url.path.endsWith('/read_my_delivery_tasks')) {
          reads++;
          return jsonResponse(
            request,
            allowed ? [delivery_fixtures.currentTaskDto()] : [],
          );
        }
        return jsonResponse(request, const <Object>[]);
      },
    );
    addTearDown(() => _disposeApp(tester, client));
    final router = await _pumpApp(tester, client);
    router.go('/shipper/tasks/${delivery_fixtures.taskId}');
    await _pumpUntil(
      tester,
      () => _hasKey('mh11-outlet'),
      description: 'task before pop',
    );
    unawaited(router.push('/notifications'));
    await _pumpUntil(
      tester,
      () => _hasKey('mh17-integration-unavailable'),
      description: 'notifications before pop',
    );
    final before = reads;
    router.pop();
    await _pumpUntil(
      tester,
      () => reads > before && _hasKey('mh11-outlet'),
      description: 'authorized task after pop',
    );
    unawaited(router.push('/notifications'));
    await _pumpUntil(
      tester,
      () => _hasKey('mh17-integration-unavailable'),
      description: 'notifications before revocation',
    );
    allowed = false;
    final beforeRevoke = reads;
    router.pop();
    await _pumpUntil(
      tester,
      () =>
          reads > beforeRevoke &&
          router.state.uri.path == '/' &&
          _hasKey('app-entry'),
      description: 'revoked task after pop',
    );
    expect(_hasKey('mh11-outlet'), isFalse);
  });

  testWidgets('same-user session refresh rechecks server role', (tester) async {
    final roles = {shipperA: 'shipper'};
    final client = await _roleClient(tester, userId: shipperA, roles: roles);
    addTearDown(() => _disposeApp(tester, client));
    final router = await _pumpApp(tester, client);
    router.go('/shipper/tasks');
    await _pumpUntil(
      tester,
      () => _hasKey('mh10-outlet'),
      description: 'initial shipper',
    );
    roles[shipperA] = 'customer';
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SportsStoreApp)),
    );
    container.read(operationalReadAccessProvider).refreshSession();
    await _pumpUntil(
      tester,
      () => router.state.uri.path == '/' && _hasKey('app-entry'),
      description: 'role revoked after refresh',
    );
    expect(_hasKey('mh10-outlet'), isFalse);
  });

  testWidgets('direct shipper account switch tears down protected navigation', (
    tester,
  ) async {
    final client = await _roleClient(
      tester,
      userId: shipperA,
      roles: {shipperA: 'shipper', shipperB: 'shipper'},
    );
    addTearDown(() => _disposeApp(tester, client));
    final router = await _pumpApp(tester, client);
    router.go('/shipper/tasks');
    await _pumpUntil(
      tester,
      () => _hasKey('mh10-outlet'),
      description: 'shipper A',
    );
    await _recoverForWidget(tester, client, shipperB);
    await _pumpUntil(
      tester,
      () => router.state.uri.path == '/' && _hasKey('app-entry'),
      description: 'root after direct switch',
    );
    expect(_hasKey('shipper-navigation'), isFalse);
    router.go('/cod');
    await _pumpUntil(
      tester,
      () => _hasKey('mh12-outlet'),
      description: 'shipper B can explicitly navigate',
    );
  });

  testWidgets('mounts MH10, MH11 and MH18 outlets through the shipper shell', (
    tester,
  ) async {
    final taskRequests = <http.Request>[];
    final client = await _roleClient(
      tester,
      userId: shipperA,
      roles: {shipperA: 'shipper'},
      dataHandler: (request) async {
        if (request.url.path.endsWith('/read_my_delivery_tasks')) {
          taskRequests.add(request);
          return jsonResponse(request, [delivery_fixtures.currentTaskDto()]);
        }
        if (request.url.path.endsWith('/read_my_delivery_task_items')) {
          fail('route guard must not read delivery task items');
        }
        return jsonResponse(request, const <Object>[]);
      },
    );
    addTearDown(() => _disposeApp(tester, client));

    final router = await _pumpApp(tester, client);
    _expectRoot();

    router.go('/shipper/tasks');
    await _pumpUntil(
      tester,
      () => _hasKey('mh10-outlet'),
      description: 'MH10 outlet',
    );
    expect(_hasKey('shipper-navigation'), isTrue);

    router.go('/shipper/tasks/${delivery_fixtures.taskId}');
    await _pumpUntil(
      tester,
      () => _hasKey('mh11-outlet'),
      description: 'MH11 outlet',
    );

    router.go('/shipper/tasks/${delivery_fixtures.taskId}/map');
    await _pumpUntil(
      tester,
      () => _hasKey('mh18-outlet'),
      description: 'MH18 outlet',
    );

    expect(taskRequests, hasLength(2));
    expect(
      taskRequests.every(
        (request) =>
            (jsonDecode(request.body) as Map<String, dynamic>)['p_task_id'] ==
            delivery_fixtures.taskId,
      ),
      isTrue,
    );
    expect(
      taskRequests.every(
        (request) => request.url.path.endsWith('/read_my_delivery_tasks'),
      ),
      isTrue,
    );
  });

  testWidgets('allows terminal detail while denying its map destination', (
    tester,
  ) async {
    Map<String, dynamic> task = delivery_fixtures.currentTaskDto();
    final taskRequests = <http.Request>[];
    final client = await _roleClient(
      tester,
      userId: shipperA,
      roles: {shipperA: 'shipper'},
      dataHandler: (request) async {
        if (request.url.path.endsWith('/read_my_delivery_tasks')) {
          taskRequests.add(request);
          return jsonResponse(request, [task]);
        }
        if (request.url.path.endsWith('/read_my_delivery_task_items')) {
          fail('route guard must not read delivery task items');
        }
        return jsonResponse(request, const <Object>[]);
      },
    );
    addTearDown(() => _disposeApp(tester, client));

    final router = await _pumpApp(tester, client);
    router.go('/shipper/tasks/${delivery_fixtures.taskId}/map');
    await _pumpUntil(
      tester,
      () => _hasKey('mh18-outlet'),
      description: 'current-task MH18 outlet',
    );

    task = delivery_fixtures.maskedTaskDto(
      status: 'delivered',
      scope: 'history',
    );
    router.go('/shipper/tasks/${delivery_fixtures.taskId}');
    await _pumpUntil(
      tester,
      () => _hasKey('mh11-outlet'),
      description: 'masked terminal MH11 outlet',
    );

    router.go('/shipper/tasks/${delivery_fixtures.taskId}/map');
    await _pumpUntil(
      tester,
      () => _hasKey('app-entry'),
      description: 'root after denied historical map',
    );
    expect(_hasKey('mh18-outlet'), isFalse);
    expect(taskRequests.length, greaterThanOrEqualTo(3));
  });

  testWidgets('forwards exact COD order filter and denies an empty result', (
    tester,
  ) async {
    final codRequests = <http.Request>[];
    var returnRows = true;
    final client = await _roleClient(
      tester,
      userId: shipperA,
      roles: {shipperA: 'shipper'},
      dataHandler: (request) async {
        if (request.url.path.endsWith('/rpc/list_cod_collections')) {
          codRequests.add(request);
          return jsonResponse(request, {
            'items': returnRows
                ? [
                    {
                      ..._codRow(),
                      'order_code': _codOrderId,
                      'order_code_source': 'order_uuid',
                    },
                  ]
                : const <Object>[],
            'next_cursor': null,
            'filtered_total': returnRows ? 1 : 0,
            'counts': {
              'all': returnRows ? 1 : 0,
              'uncollected': 0,
              'collected': returnRows ? 1 : 0,
              'received': 0,
            },
            'outstanding_vnd': returnRows ? 550000 : 0,
            'as_of': '2026-10-25T06:00:00Z',
          });
        }
        return jsonResponse(request, const <Object>[]);
      },
    );
    addTearDown(() => _disposeApp(tester, client));

    final router = await _pumpApp(tester, client);
    router.go('/cod?orderId=$_codOrderId');
    await _pumpUntil(
      tester,
      () => _hasKey('mh12-outlet'),
      description: 'filtered MH12 outlet',
    );
    expect(_hasKey('shipper-navigation'), isTrue);
    expect(
      (jsonDecode(codRequests.single.body) as Map)['p_order_id'],
      _codOrderId,
    );
    expect(
      (jsonDecode(codRequests.single.body) as Map)['p_shipper_id'],
      isNull,
    );

    router.go('/');
    await _pumpUntil(
      tester,
      () => router.state.uri.path == '/' && _hasKey('app-entry'),
      description: 'root before unfiltered COD route',
    );
    final filteredRequestCount = codRequests.length;
    router.go('/cod');
    await _pumpUntil(
      tester,
      () => router.state.uri.toString() == '/cod' && _hasKey('mh12-outlet'),
      description: 'unfiltered MH12 outlet',
    );
    // The live shipper UI now queries its list after the guard admits /cod.
    // These extra requests are status-scoped presentation reads, not an
    // unfiltered guard lookup or a bypass of the exact-order check.
    for (final request in codRequests.skip(filteredRequestCount)) {
      final body = jsonDecode(request.body) as Map;
      expect(body['p_statuses'], ['collected']);
      expect(body['p_shipper_id'], shipperA);
      expect(body['p_order_id'], isNull);
    }

    router.go('/');
    await _pumpUntil(
      tester,
      () => router.state.uri.path == '/' && _hasKey('app-entry'),
      description: 'root before unauthorized COD route',
    );
    returnRows = false;
    final unauthorizedRequestCount = codRequests.length;
    router.go('/cod?orderId=$_codOrderId');
    await _pumpUntil(
      tester,
      () =>
          router.state.uri.path == '/' &&
          codRequests.length > unauthorizedRequestCount &&
          _hasKey('app-entry'),
      description: 'root after unauthorized COD order',
    );
    expect(_hasKey('mh12-outlet'), isFalse);
    expect(
      (jsonDecode(codRequests.last.body) as Map)['p_order_id'],
      _codOrderId,
    );
  });

  testWidgets('invalid IDs remain on route without any server request', (
    tester,
  ) async {
    var requests = 0;
    final client = (await tester.runAsync(
      () => fixtureClient((request) async {
        requests++;
        return jsonResponse(request, const <Object>[]);
      }, userId: null),
    ))!;
    addTearDown(() => _disposeApp(tester, client));

    final router = await _pumpApp(tester, client);
    router.go('/shipper/tasks/not-a-uuid');
    await _pumpUntil(
      tester,
      () =>
          router.state.uri.path == '/shipper/tasks/not-a-uuid' &&
          _hasKey('navigation-invalid-id'),
      description: 'invalid task ID status',
    );
    expect(router.state.uri.path, '/shipper/tasks/not-a-uuid');

    router.go('/cod?orderId=not-a-uuid');
    await _pumpUntil(
      tester,
      () =>
          router.state.uri.toString() == '/cod?orderId=not-a-uuid' &&
          _hasKey('navigation-invalid-id'),
      description: 'invalid COD ID status',
    );
    expect(router.state.uri.path, '/cod');

    router.go('/cod?orderId=$_codOrderId&orderId=$_codOrderId');
    await _pumpUntil(
      tester,
      () =>
          router.state.uri.queryParametersAll['orderId']?.length == 2 &&
          _hasKey('navigation-invalid-id'),
      description: 'duplicate COD ID status',
    );
    expect(router.state.uri.path, '/cod');
    expect(requests, 0);
  });

  testWidgets('ignores external redirect query parameters', (tester) async {
    final client = (await tester.runAsync(
      () => fixtureClient(
        (request) async => jsonResponse(request, const <Object>[]),
        userId: null,
      ),
    ))!;
    addTearDown(() => _disposeApp(tester, client));

    final router = await _pumpApp(tester, client);
    router.go('/?from=https://example.invalid/private');
    await _pumpUntil(
      tester,
      () => _hasKey('app-entry'),
      description: 'root with external from query',
    );
    expect(router.state.uri.path, '/');
    expect(router.state.uri.host, isEmpty);

    router.go('/shipper/tasks/not-a-uuid?redirect=//example.invalid');
    await _pumpUntil(
      tester,
      () => _hasKey('navigation-invalid-id'),
      description: 'safe invalid route status',
    );
    expect(router.state.uri.path, '/shipper/tasks/not-a-uuid');
    expect(router.state.uri.host, isEmpty);
  });

  testWidgets('enforces guest, customer and manager role boundaries', (
    tester,
  ) async {
    final guest = (await tester.runAsync(
      () => fixtureClient(
        (request) async => jsonResponse(request, const <Object>[]),
        userId: null,
      ),
    ))!;
    addTearDown(() => _disposeApp(tester, guest));
    var router = await _pumpApp(tester, guest);
    _expectRoot();
    router.go('/shipper/tasks');
    await _pumpUntil(
      tester,
      () => _hasKey('app-entry'),
      description: 'guest task redirect',
    );
    router.go('/cod');
    await _pumpUntil(
      tester,
      () => _hasKey('app-entry'),
      description: 'guest COD redirect',
    );

    await tester.pumpWidget(const SizedBox());
    final customer = await _roleClient(
      tester,
      userId: _customerId,
      roles: {_customerId: 'customer'},
    );
    addTearDown(() => _disposeApp(tester, customer));
    router = await _pumpApp(tester, customer);
    router.go('/shipper/tasks');
    await _pumpUntil(
      tester,
      () => _hasKey('app-entry'),
      description: 'customer task redirect',
    );
    router.go('/cod');
    await _pumpUntil(
      tester,
      () => _hasKey('app-entry'),
      description: 'customer COD redirect',
    );

    await tester.pumpWidget(const SizedBox());
    final manager = await _roleClient(
      tester,
      userId: _managerId,
      roles: {_managerId: 'manager'},
    );
    addTearDown(() => _disposeApp(tester, manager));
    router = await _pumpApp(tester, manager);
    router.go('/cod');
    await _pumpUntil(
      tester,
      () => _hasKey('mh12-outlet'),
      description: 'manager COD outlet',
    );
    expect(_hasKey('shipper-navigation'), isFalse);
    router.go('/shipper/tasks');
    await _pumpUntil(
      tester,
      () => _hasKey('app-entry'),
      description: 'manager task redirect',
    );
    expect(_hasKey('mh10-outlet'), isFalse);
  });

  testWidgets('uses server role instead of forged fixture metadata', (
    tester,
  ) async {
    final client = await _roleClient(
      tester,
      userId: _customerId,
      roles: {_customerId: 'customer'},
    );
    addTearDown(() => _disposeApp(tester, client));

    final router = await _pumpApp(tester, client);
    router.go('/cod');
    await _pumpUntil(
      tester,
      () => _hasKey('app-entry'),
      description: 'forged metadata COD redirect',
    );
    expect(_hasKey('mh12-outlet'), isFalse);
  });

  testWidgets('keeps network failures on route without rendering business UI', (
    tester,
  ) async {
    final client = (await tester.runAsync(
      () => fixtureClient((request) async {
        if (request.url.path.endsWith('/profiles')) {
          throw http.ClientException('private network payload');
        }
        return jsonResponse(request, const <Object>[]);
      }, userId: shipperA),
    ))!;
    addTearDown(() => _disposeApp(tester, client));

    final router = await _pumpApp(tester, client);
    router.go('/shipper/tasks');
    await _pumpUntil(
      tester,
      () => _hasKey('navigation-access-error'),
      description: 'navigation access error',
    );
    expect(router.state.uri.path, '/shipper/tasks');
    expect(_hasKey('mh10-outlet'), isFalse);
    expect(_hasKey('app-entry'), isFalse);
  });

  testWidgets('opens the reserved notification slot by default', (
    tester,
  ) async {
    final client = await _roleClient(
      tester,
      userId: shipperA,
      roles: {shipperA: 'shipper'},
    );
    addTearDown(() => _disposeApp(tester, client));

    final router = await _pumpApp(tester, client);
    router.go('/shipper/tasks');
    await _pumpUntil(
      tester,
      () => _hasKey('mh10-outlet'),
      description: 'shipper tasks before notifications',
    );
    await tester.tap(find.byKey(const ValueKey('open-notifications')));
    await _pumpUntil(
      tester,
      () => _hasKey('mh17-integration-unavailable'),
      description: 'default MH17 slot',
    );
    expect(router.state.uri.path, '/notifications');
  });

  testWidgets('uses the notification builder extension point', (tester) async {
    final client = await _roleClient(
      tester,
      userId: shipperA,
      roles: {shipperA: 'shipper'},
    );
    addTearDown(() => _disposeApp(tester, client));

    final router = await _pumpApp(
      tester,
      client,
      notificationBuilder: (context) => const Center(
        key: ValueKey('notification-fixture'),
        child: Text('Fixture notifications'),
      ),
    );
    router.go('/shipper/tasks');
    await _pumpUntil(
      tester,
      () => _hasKey('mh10-outlet'),
      description: 'shipper tasks before notification fixture',
    );
    await tester.tap(find.byKey(const ValueKey('open-notifications')));
    await _pumpUntil(
      tester,
      () => _hasKey('notification-fixture'),
      description: 'notification fixture',
    );
    expect(_hasKey('mh17-integration-unavailable'), isFalse);
    expect(router.state.uri.path, '/notifications');
  });

  testWidgets('drops late task data after logout and account switch', (
    tester,
  ) async {
    final taskStarted = Completer<void>();
    final lateTask = Completer<http.Response>();
    http.Request? oldTaskRequest;
    final client = (await tester.runAsync(
      () => fixtureClient((request) async {
        if (request.url.path.endsWith('/logout')) {
          return jsonResponse(request, {});
        }
        if (request.url.path.endsWith('/profiles')) {
          final id = _profileId(request);
          return jsonResponse(request, [
            {'role': id == shipperA ? 'shipper' : 'customer'},
          ]);
        }
        if (request.url.path.endsWith('/read_my_delivery_tasks')) {
          oldTaskRequest = request;
          taskStarted.complete();
          return lateTask.future;
        }
        if (request.url.path.endsWith('/read_my_delivery_task_items')) {
          fail('route guard must not read delivery task items');
        }
        return jsonResponse(request, const <Object>[]);
      }, userId: shipperA),
    ))!;
    addTearDown(() async {
      if (!lateTask.isCompleted && oldTaskRequest != null) {
        lateTask.complete(
          jsonResponse(oldTaskRequest!, [delivery_fixtures.currentTaskDto()]),
        );
      }
      await _disposeApp(tester, client);
    });

    final router = await _pumpApp(tester, client);
    router.go('/shipper/tasks/${delivery_fixtures.taskId}');
    await taskStarted.future;

    await tester.runAsync(() => client.auth.signOut(scope: SignOutScope.local));
    await tester.pump();
    await _recoverForWidget(tester, client, _customerId);
    await _pumpUntil(
      tester,
      () => _hasKey('app-entry'),
      description: 'root after logout and account switch',
    );
    expect(_hasKey('mh11-outlet'), isFalse);

    lateTask.complete(
      jsonResponse(oldTaskRequest!, [delivery_fixtures.currentTaskDto()]),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(_hasKey('app-entry'), isTrue);
    expect(_hasKey('mh11-outlet'), isFalse);
    expect(router.state.uri.path, '/');
  });
}
