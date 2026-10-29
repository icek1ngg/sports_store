import 'package:flutter_test/flutter_test.dart';

import 'notification_supabase_test_support.dart';

Matcher fails(String code) =>
    throwsA(isA<AppFailure>().having((error) => error.code, 'code', code));

void main() {
  late NotificationSupabaseHarness harness;
  setUp(() async {
    harness = NotificationSupabaseHarness();
    await harness.supplySession();
  });
  tearDown(() => harness.dispose());

  test(
    'list uses explicit columns, owner, descending keyset and lookahead',
    () async {
      harness.handle = (_) async =>
          harness.rows([inboxRow(3), inboxRow(2), inboxRow(1)]);
      final page = await harness.repository.getPage(
        NotificationQuery(limit: 2),
      );
      expect(page.items.map((item) => item.id), [
        inboxRow(3)['id'],
        inboxRow(2)['id'],
      ]);
      expect(page.unreadCount, isNull);
      expect(page.asOf, isNull);
      final query = harness.requests.single.url.queryParameters;
      expect(query['recipient_id'], 'eq.$fixtureCustomerId');
      expect(query['limit'], '3');
      expect(query['order'], 'created_at.desc.nullslast,id.desc.nullslast');
      expect(query['select']!.split(','), hasLength(9));
      final cursor = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(page.nextCursor!))),
      ) as Map;
      expect(cursor.keys.toSet(), cursorValues().keys.toSet());
      expect(cursor['last_id'], inboxRow(2)['id']);
      harness.handle = (_) async => harness.rows([inboxRow(1)]);
      final tail = await harness.repository.getPage(
        NotificationQuery(limit: 2, cursor: page.nextCursor),
      );
      expect(tail.items.single.id, inboxRow(1)['id']);
      expect(tail.nextCursor, isNull);
      expect(
        harness.requests.last.url.queryParameters['or'],
        contains('id.lt.${inboxRow(2)['id']}'),
      );
    },
  );

  test(
    'unread filter is read_at IS NULL; empty is canonical, not fake count',
    () async {
      final page = await harness.repository.getPage(
        NotificationQuery(filter: NotificationFilter.unread),
      );
      expect(harness.requests.single.url.queryParameters['read_at'], 'is.null');
      expect(page.items, isEmpty);
      expect(page.nextCursor, isNull);
      expect(page.unreadCount, isNull);
    },
  );

  final invalidCursors = <String, Object?>{
    'v': 2,
    'user_id': otherRecipient,
    'filter': 'unread',
    'limit': 3,
    'last_created_at': '2026-10-27T01:00:00',
    'last_id': 'bad),recipient_id.neq.x',
  };
  for (final entry in invalidCursors.entries) {
    test(
      'cursor rejects mismatched/malformed ${entry.key} before HTTP',
      () async {
        final cursor = encodeCursor({
          ...cursorValues(),
          entry.key: entry.value,
        });
        await expectLater(
          harness.repository.getPage(
            NotificationQuery(limit: 2, cursor: cursor),
          ),
          fails(AppFailure.invalidCursor),
        );
        expect(harness.requests, isEmpty);
      },
    );
  }
  for (final cursor in [
    'not-json',
    '[]',
    encodeCursor({...cursorValues(), 'extra': true}),
    encodeCursor({...cursorValues()}..remove('v')),
  ]) {
    test(
      'invalid cursor shape $cursor never becomes head-page success',
      () async {
        await expectLater(
          harness.repository.getPage(
            NotificationQuery(limit: 2, cursor: cursor),
          ),
          fails(AppFailure.invalidCursor),
        );
        expect(harness.requests, isEmpty);
      },
    );
  }

  for (final bad in [
    'foreign',
    'read in unread',
    'duplicate',
    'order',
    'partial',
  ]) {
    test('page rejects $bad server response', () async {
      harness.handle = (_) async => harness.rows(switch (bad) {
        'foreign' => [inboxRow(1, recipient: otherRecipient)],
        'read in unread' => [inboxRow(1, readAt: '2026-10-27T02:00:00Z')],
        'duplicate' => [inboxRow(1), inboxRow(1)],
        'order' => [inboxRow(1), inboxRow(2)],
        _ => [inboxRow(1)..remove('read_at')],
      });
      await expectLater(
        harness.repository.getPage(
          NotificationQuery(
            filter: bad == 'read in unread'
                ? NotificationFilter.unread
                : NotificationFilter.all,
          ),
        ),
        fails(AppFailure.unsupportedData),
      );
    });
  }

  for (final count in [0, 137]) {
    test('exact count $count uses whole own unread inbox HEAD', () async {
      harness.handle = (_) async =>
          Response('', 200, headers: {'content-range': '*/$count'});
      expect(await harness.repository.getUnreadCount(), count);
      final request = harness.requests.single;
      expect(request.method, 'HEAD');
      expect(request.headers['prefer'], contains('count=exact'));
      expect(
        request.url.queryParameters['recipient_id'],
        'eq.$fixtureCustomerId',
      );
      expect(request.url.queryParameters['read_at'], 'is.null');
      expect(request.url.queryParameters.containsKey('limit'), isFalse);
    });
  }

  test('missing count header never becomes zero', () async {
    harness.handle = (_) async => Response('', 200);
    await expectLater(
      harness.repository.getUnreadCount(),
      fails(AppFailure.unsupportedData),
    );
  });

  for (final error in [
    (401, 'PGRST301', AppFailure.unauthenticated),
    (403, '42501', AppFailure.forbiddenOrUnavailable),
    (404, 'PGRST205', AppFailure.externalDependencyUnavailable),
    (500, '500', AppFailure.network),
    (503, 'PGRST000', AppFailure.network),
    (504, 'PGRST003', AppFailure.network),
    (400, '22000', AppFailure.unsupportedData),
  ]) {
    test(
      'maps ${error.$1}/${error.$2} safely without synthetic data/retry',
      () async {
        harness.handle = (_) async => Response(
          jsonEncode({'code': error.$2, 'message': 'private transport detail'}),
          error.$1,
        );
        await expectLater(
          harness.repository.getPage(NotificationQuery()),
          fails(error.$3),
        );
        expect(harness.requests, hasLength(1));
      },
    );
  }

  test('markRead uses server row signal and only canonical ACK; repeated read no extra PATCH', () async {
    var row = inboxRow(1);
    harness.handle = (request) async {
      if (request.method == 'PATCH') {
        expect(jsonDecode(request.body), {
          'read_at': '2026-10-27T01:00:00.000Z',
        });
        expect(request.url.queryParameters['id'], 'eq.${row['id']}');
        expect(
          request.url.queryParameters['recipient_id'],
          'eq.$fixtureCustomerId',
        );
        expect(request.url.queryParameters['select']!.split(','), hasLength(9));
        row = {...row, 'read_at': '2026-10-27T02:00:00Z'};
      }
      return harness.rows([row]);
    };
    final first = await harness.repository.markRead(row['id']! as String);
    expect(first.readAt, DateTime.utc(2026, 10, 27, 2));
    expect(first.readAt, isNot(first.createdAt));
    final repeated = await harness.repository.markRead(row['id']! as String);
    expect(repeated.readAt, first.readAt);
    expect(harness.requests.where((r) => r.method == 'PATCH'), hasLength(1));
  });

  test('lost PATCH response is recovered by a canonical GET without a second write', () async {
    var row = inboxRow(1);
    harness.handle = (request) async {
      if (request.method == 'PATCH') {
        row = {...row, 'read_at': '2026-10-27T02:00:00Z'};
        throw TimeoutException('Test-only lost acknowledgement');
      }
      return harness.rows([row]);
    };
    await expectLater(
      harness.repository.markRead(row['id']! as String),
      fails(AppFailure.network),
    );
    final recovered = await harness.repository.markRead(row['id']! as String);
    expect(recovered.readAt, DateTime.utc(2026, 10, 27, 2));
    expect(harness.requests.where((r) => r.method == 'PATCH'), hasLength(1));
  });

  test(
    'concurrent read requests accept the same first server timestamp',
    () async {
      var row = inboxRow(1);
      harness.handle = (request) async {
        if (request.method == 'PATCH' && row['read_at'] == null) {
          row = {...row, 'read_at': '2026-10-27T02:00:00Z'};
        }
        return harness.rows([row]);
      };
      final results = await Future.wait([
        harness.repository.markRead(row['id']! as String),
        harness.repository.markRead(row['id']! as String),
      ]);
      expect(
        results.every((item) => item.readAt == DateTime.utc(2026, 10, 27, 2)),
        isTrue,
      );
    },
  );

  for (final phase in ['GET', 'PATCH']) {
    test('zero rows on $phase is unavailable, never success', () async {
      harness.handle = (request) async =>
          harness.rows(request.method == phase ? [] : [inboxRow(1)]);
      await expectLater(
        harness.repository.markRead(inboxRow(1)['id']! as String),
        fails(AppFailure.forbiddenOrUnavailable),
      );
      if (phase == 'GET') expect(harness.requests, hasLength(1));
    });
  }

  for (final malformed in ['id', 'owner', 'unread', 'immutable', 'partial']) {
    test('rejects malformed $malformed read ACK', () async {
      harness.handle = (request) async {
        if (request.method == 'GET') return harness.rows([inboxRow(1)]);
        final ack = inboxRow(1, readAt: '2026-10-27T02:00:00Z');
        switch (malformed) {
          case 'id':
            ack['id'] = inboxRow(2)['id'];
          case 'owner':
            ack['recipient_id'] = otherRecipient;
          case 'unread':
            ack['read_at'] = null;
          case 'immutable':
            ack['title'] = 'Changed';
          case 'partial':
            ack.remove('read_at');
        }
        return harness.rows([ack]);
      };
      await expectLater(
        harness.repository.markRead(inboxRow(1)['id']! as String),
        fails(AppFailure.unsupportedData),
      );
    });
  }

  test('invalid read ID performs no HTTP', () async {
    await expectLater(
      harness.repository.markRead('not-a-uuid'),
      fails(AppFailure.invalidArgument),
    );
    expect(harness.requests, isEmpty);
  });

  for (final operation in ['page', 'count', 'read GET', 'read PATCH']) {
    for (final change in ['account', 'same-user SDK', 'generation']) {
      test('$operation rejects late response after $change change', () async {
        final pending = Completer<Response>();
        final started = Completer<void>();
        harness.handle = (request) {
          if (operation == 'read PATCH' && request.method == 'GET') {
            return Future.value(harness.rows([inboxRow(1)]));
          }
          started.complete();
          return pending.future;
        };
        final result = switch (operation) {
          'page' => harness.repository.getPage(NotificationQuery()),
          'count' => harness.repository.getUnreadCount(),
          _ => harness.repository.markRead(inboxRow(1)['id']! as String),
        };
        final assertion = expectLater(
          result,
          fails(AppFailure.unauthenticated),
        );
        await started.future;
        if (change == 'generation') {
          harness.scope = const SessionScope(
            userId: fixtureCustomerId,
            role: 'customer',
            generation: 2,
          );
        } else {
          await harness.supplySession(
            userId: change == 'account' ? otherRecipient : fixtureCustomerId,
            generation: change == 'account' ? 2 : 1,
            tokenVersion: 1,
          );
        }
        pending.complete(
          operation == 'count'
              ? Response('', 200, headers: {'content-range': '*/9'})
              : harness.rows([
                  inboxRow(
                    1,
                    readAt: operation == 'read PATCH'
                        ? '2026-10-27T02:00:00Z'
                        : null,
                  ),
                ]),
        );
        await assertion;
        if (operation == 'read GET') {
          expect(harness.requests.where((r) => r.method == 'PATCH'), isEmpty);
        }
      });
    }
  }

  for (final denied in [
    'unresolved',
    'role',
    'SDK user',
    'expired',
    'logout',
  ]) {
    test('$denied blocks all requests before HTTP', () async {
      switch (denied) {
        case 'unresolved':
          harness.scope = const SessionScope.unresolved();
        case 'role':
          harness.scope = const SessionScope(
            userId: fixtureCustomerId,
            role: 'admin',
            generation: 1,
          );
        case 'SDK user':
          harness.scope = const SessionScope(
            userId: otherRecipient,
            role: 'customer',
            generation: 1,
          );
        case 'expired':
          harness.client.auth.currentSession!.expiresAt = 1;
        case 'logout':
          harness.scope = const SessionScope(
            userId: null,
            role: null,
            generation: 2,
          );
      }
      await expectLater(
        harness.repository.getUnreadCount(),
        fails(AppFailure.unauthenticated),
      );
      expect(harness.requests, isEmpty);
    });
  }
}
