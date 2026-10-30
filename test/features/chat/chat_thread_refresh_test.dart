import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/chat/domain/models/chat_models.dart';
import 'package:sports_store/features/chat/domain/repositories/chat_repository.dart';
import 'package:sports_store/features/chat/presentation/pages/conversation_detail_screen.dart';
import 'package:sports_store/features/chat/presentation/view_models/chat_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/operational_supabase_fixture.dart';

const _conversation = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

ChatMessage _message(
  int number, {
  String? body,
  String? clientId,
}) => ChatMessage(
  id: '10000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
  conversationId: _conversation,
  senderId: shipperA,
  body: body ?? 'Tin $number',
  clientMessageId: clientId ?? 'client-$number',
  // Consecutive messages deliberately share timestamps to cover UUID tie order.
  createdAt: DateTime.utc(2026, 10, 30).add(Duration(seconds: number ~/ 2)),
);

ChatMessagePage _page(List<int> numbers, {bool hasMore = false}) =>
    ChatMessagePage(messages: numbers.map(_message).toList(), hasMore: hasMore);

class _Repository implements ChatRepository {
  Future<ChatMessagePage> Function(String? before) read = (_) async =>
      _page([]);
  Future<ChatMessage> Function(String body, String key)? write;
  final cursors = <String?>[];
  final sentKeys = <String>[];
  var inboxReads = 0;
  var unread = 5;

  @override
  Future<List<ChatConversation>> getConversations() async {
    inboxReads++;
    return [
      ChatConversation(
        id: _conversation,
        customerId: shipperA,
        customerName: 'Khách hàng',
        lastMessage: 'Tin nhắn',
        lastMessageAt: DateTime.utc(2026, 10, 30),
        lastSenderId: shipperB,
        unreadCount: unread,
      ),
    ];
  }

  @override
  Future<String> ensureCustomerConversation() async => _conversation;

  @override
  Future<ChatMessagePage> getMessages(
    String conversationId, {
    String? beforeMessageId,
  }) {
    expect(conversationId, _conversation);
    cursors.add(beforeMessageId);
    return read(beforeMessageId);
  }

  @override
  Future<ChatMessage> sendMessage(
    String conversationId,
    String body,
    String key,
  ) {
    sentKeys.add(key);
    return write?.call(body, key) ??
        Future.value(_message(99, body: body, clientId: key));
  }
}

Future<void> _until(ProviderContainer container, bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await Future<void>.delayed(Duration.zero);
    await container.pump();
  }
  expect(ready(), isTrue);
}

void main() {
  late SupabaseClient client;
  late _Repository repository;
  late ProviderContainer container;
  final provider = chatThreadProvider(_conversation);

  setUp(() async {
    client = await fixtureClient((request) async => jsonResponse(request, {}));
    repository = _Repository();
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        chatRepositoryProvider.overrideWithValue(repository),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await client.dispose();
  });

  test(
    'opening and refreshing a thread immediately reloads inbox unread count',
    () async {
      container.listen(chatInboxProvider, (_, _) {});
      await container.read(chatInboxProvider.future);
      expect(
        container.read(chatInboxProvider).requireValue.single.unreadCount,
        5,
      );
      repository.read = (_) async {
        repository.unread = 0;
        return _page([1]);
      };
      container.listen(provider, (_, _) {});
      await container.read(provider.future);
      await _until(container, () => repository.inboxReads >= 2);
      await container.read(chatInboxProvider.future);
      expect(
        container.read(chatInboxProvider).requireValue.single.unreadCount,
        0,
      );
      final beforeRefresh = repository.inboxReads;
      await container.read(provider.notifier).refreshLatest();
      await _until(container, () => repository.inboxReads > beforeRefresh);
    },
  );

  test(
    'latest merge keeps loaded older pages, cursor and timestamp tie order',
    () async {
      repository.read = (before) async =>
          before == null ? _page([3, 4], hasMore: true) : _page([1, 2]);
      container.listen(provider, (_, _) {});
      await container.read(provider.future);
      final viewModel = container.read(provider.notifier);
      await viewModel.loadOlder();
      repository.read = (_) async => _page([4, 5], hasMore: true);
      await viewModel.refreshLatest();
      final value = container.read(provider).requireValue;
      expect(value.page.messages.map((m) => m.body), [
        'Tin 1',
        'Tin 2',
        'Tin 3',
        'Tin 4',
        'Tin 5',
      ]);
      expect(value.page.hasMore, isFalse);
      expect(value.refreshing, isFalse);
    },
  );

  test(
    'latest merge fetches intermediate pages when the fresh head has a gap',
    () async {
      repository.read = (_) async => _page([1, 2]);
      container.listen(provider, (_, _) {});
      await container.read(provider.future);
      repository.read = (before) async {
        if (before == null) return _page([7, 8], hasMore: true);
        if (before == _message(7).id) return _page([5, 6], hasMore: true);
        expect(before, _message(5).id);
        return _page([2, 3, 4]);
      };
      await container.read(provider.notifier).refreshLatest();
      expect(
        container.read(provider).requireValue.page.messages.map((m) => m.body),
        List.generate(8, (i) => 'Tin ${i + 1}'),
      );
      expect(repository.cursors, [null, null, _message(7).id, _message(5).id]);
    },
  );

  test(
    'a local send ACK cannot conceal unseen messages before the fresh head',
    () async {
      repository.read = (_) async => _page([1, 2]);
      container.listen(provider, (_, _) {});
      await container.read(provider.future);
      final viewModel = container.read(provider.notifier);
      repository.write = (body, key) async =>
          _message(203, body: body, clientId: key);
      expect(await viewModel.send('Trả lời'), isTrue);
      repository.read = (before) async {
        final end = before == null
            ? 203
            : int.parse(before.split('-').last) - 1;
        final start = (end - 99).clamp(1, end);
        return _page([
          for (var number = start; number <= end; number++) number,
        ], hasMore: start > 1);
      };
      await viewModel.refreshLatest();
      final value = container.read(provider).requireValue;
      expect(
        value.page.messages.map((m) => m.id),
        List.generate(203, (i) => _message(i + 1).id),
      );
      expect(value.page.hasMore, isFalse);
      expect(repository.cursors, [
        null,
        null,
        _message(104).id,
        _message(4).id,
      ]);
    },
  );

  test(
    'a send from an empty snapshot backfills history preceding its ACK',
    () async {
      repository.read = (_) async => _page([]);
      container.listen(provider, (_, _) {});
      await container.read(provider.future);
      final viewModel = container.read(provider.notifier);
      repository.write = (body, key) async =>
          _message(5, body: body, clientId: key);
      expect(await viewModel.send('Trả lời'), isTrue);
      repository.read = (before) async =>
          before == null ? _page([4, 5], hasMore: true) : _page([1, 2, 3]);
      await viewModel.refreshLatest();
      expect(
        container.read(provider).requireValue.page.messages.map((m) => m.id),
        List.generate(5, (i) => _message(i + 1).id),
      );
      expect(repository.cursors, [null, null, _message(4).id]);
    },
  );

  test(
    'refresh serializes send, history and duplicate refresh actions',
    () async {
      repository.read = (_) async => _page([1, 2], hasMore: true);
      container.listen(provider, (_, _) {});
      await container.read(provider.future);
      final pending = Completer<ChatMessagePage>();
      repository.read = (_) => pending.future;
      final viewModel = container.read(provider.notifier);
      final refresh = viewModel.refreshLatest();
      expect(container.read(provider).requireValue.refreshing, isTrue);
      expect(await viewModel.send('Xin chào'), isFalse);
      await viewModel.loadOlder();
      await viewModel.refreshLatest();
      expect(repository.cursors.length, 2);
      expect(repository.sentKeys, isEmpty);
      pending.complete(_page([2, 3]));
      await refresh;
      expect(await viewModel.send('Xin chào'), isTrue);
      expect(
        container.read(provider).requireValue.page.messages.last.body,
        'Xin chào',
      );
      expect(
        container.read(provider).requireValue.page.messages.first.body,
        'Tin 1',
      );
    },
  );

  test(
    'failed refresh retains history and a failed send keeps its retry key',
    () async {
      repository.read = (_) async => _page([1, 2]);
      container.listen(provider, (_, _) {});
      await container.read(provider.future);
      final viewModel = container.read(provider.notifier);
      repository.write = (_, _) =>
          Future.error(const ChatFailure('Mất kết nối'));
      expect(await viewModel.send('Gửi lại'), isFalse);
      repository.read = (_) => Future.error(const ChatFailure('Không thể tải'));
      await viewModel.refreshLatest();
      expect(container.read(provider).requireValue.page.messages.length, 2);
      expect(container.read(provider).requireValue.error, 'Không thể tải');
      repository.write = (body, key) async =>
          _message(3, body: body, clientId: key);
      expect(await viewModel.send('Gửi lại'), isTrue);
      expect(repository.sentKeys.length, 2);
      expect(repository.sentKeys.toSet().length, 1);
    },
  );

  test(
    'permission revocation hides cached history instead of retaining it',
    () async {
      repository.read = (_) async => _page([1, 2]);
      container.listen(provider, (_, _) {});
      await container.read(provider.future);
      repository.read = (_) => Future.error(
        const ChatFailure('Không còn quyền truy cập', accessDenied: true),
      );
      await container.read(provider.notifier).refreshLatest();
      expect(container.read(provider).hasError, isTrue);
      expect(container.read(provider).asData, isNull);
    },
  );

  test(
    'an old account refresh cannot replace the new account thread',
    () async {
      repository.read = (_) async => _page([1]);
      container.listen(provider, (_, _) {});
      await container.read(provider.future);
      final pending = Completer<ChatMessagePage>();
      repository.read = (_) => client.auth.currentUser?.id == shipperB
          ? Future.value(_page([99]))
          : pending.future;
      final refresh = container.read(provider.notifier).refreshLatest();
      await recoverFixtureSession(client, shipperB);
      await _until(
        container,
        () =>
            container.read(provider).asData?.value.page.messages.first.body ==
            'Tin 99',
      );
      pending.complete(_page([2]));
      await refresh;
      expect(
        container.read(provider).requireValue.page.messages.single.body,
        'Tin 99',
      );
    },
  );

  testWidgets('the twenty-second UI poll preserves loaded history', (
    tester,
  ) async {
    // Give the widget its own container; the setUp container remains unused.
    repository.read = (before) async =>
        before == null ? _page([3, 4], hasMore: true) : _page([1, 2]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          chatRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: ConversationDetailScreen(conversationId: _conversation),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xem tin nhắn cũ hơn'));
    await tester.pumpAndSettle();
    expect(find.text('Tin 1'), findsOneWidget);
    repository.read = (_) async => _page([4, 5], hasMore: true);
    await tester.pump(const Duration(seconds: 20));
    await tester.pumpAndSettle();
    expect(find.text('Tin 1'), findsOneWidget);
    expect(find.text('Tin 5'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
