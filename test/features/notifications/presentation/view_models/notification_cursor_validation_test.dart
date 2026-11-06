import '../pages/mh17/mh17_page_test_support.dart';

Future<void> flushCursorReads(ProviderContainer container) async {
  await Future<void>.delayed(Duration.zero);
  await container.pump();
  await Future<void>.delayed(Duration.zero);
}

void main() {
  late ProviderContainer container;
  late PageNotifications repository;
  late SessionScope liveScope;
  setUp(() async {
    repository = PageNotifications();
    liveScope = pageScope;
    container = ProviderContainer(
      overrides: [
        featureSessionScopeProvider.overrideWith((ref) => liveScope),
        notificationRepositoryProvider.overrideWithValue(repository),
        readRetryPolicyProvider.overrideWithValue(
          const ReadRetryPolicy(backoffs: []),
        ),
      ],
    );
    container.listen(unreadCountFoundationProvider, (_, _) {});
    await flushCursorReads(container);
    repository.countRequests.single.complete(41);
    await flushCursorReads(container);
  });
  tearDown(() => container.dispose());

  final valid = <String, String?>{
    'null': null,
    'one': 'x',
    '2048': List.filled(2048, 'c').join(),
    'opaque whitespace': ' ',
    'UTF16 length2048': List.filled(1024, '😀').join(),
  };
  for (final entry in valid.entries) {
    test('accepts ${entry.key} response cursor unchanged', () async {
      final query = NotificationQuery();
      final provider = notificationPageFoundationProvider(query);
      container.listen(provider, (_, _) {});
      await flushCursorReads(container);
      final response = page([row1], nextCursor: entry.value, unreadCount: 999);
      repository.requests.single.result.complete(response);
      await flushCursorReads(container);
      final state = container.read(provider).requireValue;
      expect(state.isFresh, true);
      expect(state.failure, isNull);
      expect(state.data, same(response));
      expect(state.data!.nextCursor, entry.value);
      expect(
        container
            .read(epochCacheProvider)
            .read<NotificationPage>('notifications/list/all/20/null')!
            .data,
        same(response),
      );
      expect(
        container.read(unreadCountFoundationProvider).requireValue.data,
        41,
      );
    });
  }

  final invalid = <String, String>{
    'empty': '',
    '2049': List.filled(2049, 'c').join(),
    'UTF16 length2049': '${List.filled(1024, '😀').join()}x',
  };
  for (final entry in invalid.entries) {
    test(
      'rejects ${entry.key} response cursor before canonical acceptance',
      () async {
        final provider = notificationPageFoundationProvider(
          NotificationQuery(),
        );
        container.listen(provider, (_, _) {});
        await flushCursorReads(container);
        repository.requests.single.result.complete(
          page([row1], nextCursor: entry.value),
        );
        await flushCursorReads(container);
        final state = container.read(provider).requireValue;
        expect(state.isFresh, false);
        expect(state.data, isNull);
        expect(state.failure!.code, AppFailure.unsupportedData);
        expect(state.failure!.retryable, false);
        expect(
          container
              .read(epochCacheProvider)
              .read<NotificationPage>('notifications/list/all/20/null'),
          isNull,
        );
        expect(
          repository.requests,
          hasLength(1),
        ); // No fake recovery/automatic repository retry.
        expect(
          container.read(unreadCountFoundationProvider).requireValue.data,
          41,
        );
      },
    );
  }

  test('malformed refreshed tail retains last accepted projection and explicit retry stays on tail', () async {
    final provider = notificationPageFoundationProvider(
      NotificationQuery(cursor: 'request-tail'),
    );
    container.listen(provider, (_, _) {});
    await flushCursorReads(container);
    final accepted = page([row1], nextCursor: 'valid-next');
    repository.requests.single.result.complete(accepted);
    await flushCursorReads(container);
    final failed = container.read(provider.notifier).refresh();
    await flushCursorReads(container);
    repository.requests.last.result.complete(page([row2], nextCursor: ''));
    await failed;
    await flushCursorReads(container);
    final state = container.read(provider).requireValue;
    expect(state.data, same(accepted));
    expect(state.stale, true);
    expect(state.isFresh, false);
    expect(state.failure!.code, AppFailure.unsupportedData);
    final cached = container
        .read(epochCacheProvider)
        .read<NotificationPage>('notifications/list/all/20/request-tail')!;
    expect(cached.data, same(accepted));
    expect(cached.stale, true);
    final retry = container.read(provider.notifier).refresh();
    await flushCursorReads(container);
    expect(repository.requests.map((r) => r.query.cursor), [
      'request-tail',
      'request-tail',
      'request-tail',
    ]);
    final recovered = page([row2]);
    repository.requests.last.result.complete(recovered);
    await retry;
    await flushCursorReads(container);
    expect(container.read(provider).requireValue.data, same(recovered));
    expect(container.read(provider).requireValue.failure, isNull);
    expect(container.read(unreadCountFoundationProvider).requireValue.data, 41);
  });

  test('late malformed A response cannot publish failure or private rows into B namespace', () async {
    final provider = notificationPageFoundationProvider(NotificationQuery());
    container.listen(provider, (_, _) {});
    await flushCursorReads(container);
    final old = repository.requests.single.result;
    liveScope = const SessionScope(
      userId: '20000000-0000-4000-8000-000000000099',
      role: 'customer',
      generation: 2,
    );
    container.invalidate(featureSessionScopeProvider);
    await flushCursorReads(container);
    final ownB = NotificationDto.fromJson({
      ...row1.toMap(),
      'recipient_id': liveScope.userId,
      'title': 'Nội dung B',
    }).domain;
    final acceptedB = page([ownB]);
    repository.requests.last.result.complete(acceptedB);
    repository.countRequests.last.complete(3);
    await flushCursorReads(container);
    old.complete(page([row1], nextCursor: ''));
    await flushCursorReads(container);
    expect(container.read(provider).requireValue.isFresh, true);
    expect(container.read(provider).requireValue.data, same(acceptedB));
    expect(container.read(provider).requireValue.failure, isNull);
    expect(container.read(unreadCountFoundationProvider).requireValue.data, 3);
  });
}
