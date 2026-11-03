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

// The fixture session user (shipperA id) plays the customer here.
const _me = shipperA;
const _store = shipperB;
const _conversation = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

ChatMessage _msg(int n, {String sender = _store, DateTime? at, String? body}) =>
    ChatMessage(
      id: '20000000-0000-4000-8000-${n.toString().padLeft(12, '0')}',
      conversationId: _conversation,
      senderId: sender,
      body: body ?? 'Tin $n',
      clientMessageId:
          '30000000-0000-4000-8000-${n.toString().padLeft(12, '0')}',
      createdAt: at ?? DateTime.utc(2026, 11, 3, 2).add(Duration(minutes: n)),
    );

/// Server stand-in: [head] is the latest page; reading it is what marks read.
class _Server implements ChatRepository {
  List<ChatMessage> messages = [_msg(1), _msg(2, sender: _me)];
  DateTime? storeReadAt;
  int headReads = 0;
  final sentKeys = <String>[];
  Future<void> Function()? beforeSend;
  ChatFailure? sendFailure;
  ChatFailure? activityFailure;

  @override
  Future<List<ChatConversation>> getConversations() async => [
    ChatConversation(
      id: _conversation,
      customerId: _me,
      customerName: 'Nguyễn Minh Anh',
      lastMessage: messages.lastOrNull?.body,
      lastMessageAt: messages.lastOrNull?.createdAt,
      lastSenderId: messages.lastOrNull?.senderId,
      unreadCount: 0,
    ),
  ];

  @override
  Future<String> ensureCustomerConversation() async => _conversation;

  @override
  Future<ChatMessagePage> getMessages(
    String conversationId, {
    String? beforeMessageId,
  }) async {
    if (beforeMessageId == null) headReads++;
    return ChatMessagePage(messages: [...messages], hasMore: false);
  }

  @override
  Future<ChatActivity> getActivity(String conversationId) async {
    if (activityFailure != null) throw activityFailure!;
    return ChatActivity(
      conversationId: conversationId,
      customerId: _me,
      readAtByUser: {_store: ?storeReadAt},
      latestMessageId: messages.lastOrNull?.id,
      latestMessageAt: messages.lastOrNull?.createdAt,
      latestSenderId: messages.lastOrNull?.senderId,
    );
  }

  @override
  Future<ChatMessage> sendMessage(
    String conversationId,
    String body,
    String clientMessageId,
  ) async {
    sentKeys.add(clientMessageId);
    await beforeSend?.call();
    if (sendFailure != null) {
      final failure = sendFailure!;
      sendFailure = null;
      throw failure;
    }
    final existing = messages.where(
      (m) => m.clientMessageId == clientMessageId,
    );
    if (existing.isNotEmpty) return existing.single; // idempotent replay
    final m = ChatMessage(
      id: '20000000-0000-4000-8000-${(900 + messages.length).toString().padLeft(12, '0')}',
      conversationId: conversationId,
      senderId: _me,
      body: body,
      clientMessageId: clientMessageId,
      createdAt: DateTime.utc(2026, 11, 3, 3),
    );
    messages = [...messages, m];
    return m;
  }
}

void main() {
  late SupabaseClient client;
  late _Server server;

  setUp(() async {
    client = await fixtureClient((request) async => jsonResponse(request, {}));
    server = _Server();
  });
  tearDown(() async => client.dispose());

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          chatRepositoryProvider.overrideWithValue(server),
        ],
        child: const MaterialApp(
          home: ConversationDetailScreen(conversationId: _conversation),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  testWidgets('shows store identity, Hanoi date separators and server time', (
    tester,
  ) async {
    // 17:30 UTC on 30/10 is 00:30 on 31/10 in Hanoi.
    server.messages = [
      _msg(1, at: DateTime.utc(2026, 10, 30, 17, 30), body: 'Cho hỏi đơn hàng'),
      _msg(2, sender: _me, at: DateTime.utc(2026, 10, 30, 17, 45)),
    ];
    await pump(tester);
    expect(find.text('Cửa hàng Sports Store'), findsOneWidget);
    expect(find.text('31/10/2026'), findsOneWidget);
    expect(find.textContaining('00:30'), findsOneWidget);
    expect(find.text('Cửa hàng'), findsOneWidget); // sender of the other side
    expect(find.textContaining('MH20'), findsNothing);
    await finish(tester);
  });

  testWidgets('own latest message shows "Đã xem" only after the store read', (
    tester,
  ) async {
    await pump(tester);
    expect(find.textContaining('Đã gửi'), findsOneWidget);
    server.storeReadAt = server.messages.last.createdAt;
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.textContaining('Đã xem'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a new reply appears within one 3 s check while viewing', (
    tester,
  ) async {
    await pump(tester);
    final readsAfterOpen = server.headReads;
    server.messages = [...server.messages, _msg(3, body: 'Cửa hàng đã nhận')];
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Cửa hàng đã nhận'), findsOneWidget);
    // Loading the new head is the read: it happened while the reply was shown.
    expect(server.headReads, readsAfterOpen + 1);
    await finish(tester);
  });

  testWidgets('no read while scrolled up; "Có tin nhắn mới" loads it', (
    tester,
  ) async {
    server.messages = [for (var i = 1; i <= 40; i++) _msg(i)];
    await pump(tester);
    await tester.drag(
      find.byKey(const ValueKey('mh20-list')),
      const Offset(0, 600),
    );
    await tester.pumpAndSettle();
    final readsBefore = server.headReads;
    server.messages = [...server.messages, _msg(41, body: 'Tin mới nhất')];
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(server.headReads, readsBefore, reason: 'not viewed → not read');
    expect(find.byKey(const ValueKey('mh20-new-below')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mh20-new-below')));
    await tester.pumpAndSettle();
    expect(server.headReads, readsBefore + 1);
    expect(find.text('Tin mới nhất'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('blank text cannot be sent', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const ValueKey('mh20-input')), '   \n ');
    await tester.pump();
    final send = tester.widget<IconButton>(
      find.byKey(const ValueKey('mh20-send')),
    );
    expect(send.onPressed, isNull);
    await finish(tester);
  });

  testWidgets('typing continues while sending; only sent text is cleared', (
    tester,
  ) async {
    final gate = Completer<void>();
    server.beforeSend = () => gate.future;
    await pump(tester);
    final input = find.byKey(const ValueKey('mh20-input'));
    await tester.enterText(input, 'Xin chào');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mh20-send')));
    await tester.pump();
    await tester.enterText(input, 'Xin chào cho hỏi thêm');
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, 'cho hỏi thêm');
    expect(find.text('Xin chào'), findsOneWidget); // the sent bubble
    await finish(tester);
  });

  testWidgets('network failure keeps the draft; retry reuses the same key', (
    tester,
  ) async {
    server.sendFailure = const ChatFailure(
      'Không thể kết nối hội thoại. Vui lòng thử lại.',
    );
    await pump(tester);
    final input = find.byKey(const ValueKey('mh20-input'));
    await tester.enterText(input, 'Đơn của tôi đâu rồi?');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mh20-send')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mh20-send-error')), findsOneWidget);
    expect(
      tester.widget<TextField>(input).controller!.text,
      'Đơn của tôi đâu rồi?',
    );
    await tester.tap(find.byKey(const ValueKey('mh20-retry')));
    await tester.pumpAndSettle();
    expect(server.sentKeys, hasLength(2));
    expect(server.sentKeys.toSet(), hasLength(1));
    expect(find.text('Đơn của tôi đâu rồi?'), findsOneWidget); // one bubble
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    await finish(tester);
  });

  testWidgets('a failed background check keeps history and keeps polling', (
    tester,
  ) async {
    await pump(tester);
    server.activityFailure = const ChatFailure('Không thể kết nối.');
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mh20-connection')), findsOneWidget);
    expect(find.text('Tin 1'), findsOneWidget);
    server.activityFailure = null;
    server.messages = [...server.messages, _msg(3, body: 'Đã có mạng lại')];
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Đã có mạng lại'), findsOneWidget);
    expect(find.byKey(const ValueKey('mh20-connection')), findsNothing);
    await finish(tester);
  });

  testWidgets('lost access removes the history', (tester) async {
    await pump(tester);
    server.activityFailure = const ChatFailure(
      'Bạn không có quyền truy cập hội thoại này.',
      accessDenied: true,
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Tin 1'), findsNothing);
    expect(
      find.text('Bạn không có quyền truy cập hội thoại này.'),
      findsOneWidget,
    );
    await finish(tester);
  });
}
