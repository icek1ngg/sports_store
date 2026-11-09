import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/app/demo/data/local_demo_store.dart';
import 'package:sports_store/app/dev/data/local_chat_repository.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/chat/domain/models/chat_models.dart';
import 'package:sports_store/features/chat/presentation/view_models/chat_providers.dart';

void main() {
  test(
    'customer-manager conversation shares messages and private read markers',
    () async {
      final store = LocalDemoStore();
      final repository = LocalChatRepository(() => store.session);
      final id = await repository.ensureCustomerConversation();
      final ownInbox = await repository.getConversations();
      expect(ownInbox, hasLength(1));
      final sent = await repository.sendMessage(
        id,
        'Tư vấn giúp tôi',
        'request-1',
      );
      expect(
        (await repository.sendMessage(id, 'Tư vấn giúp tôi', 'request-1')).id,
        sent.id,
      );
      await expectLater(
        repository.sendMessage(id, 'Nội dung khác', 'request-1'),
        throwsA(isA<ChatFailure>()),
      );
      store.switchAccount(DemoAccount.managerB);
      final managerInbox = await repository.getConversations();
      expect(managerInbox, hasLength(2));
      expect(managerInbox.firstWhere((t) => t.id == id).unreadCount, 2);
      final page = await repository.getMessages(id);
      expect(page.messages.last.body, 'Tư vấn giúp tôi');
      expect(
        (await repository.getConversations())
            .firstWhere((t) => t.id == id)
            .unreadCount,
        0,
      );
      await repository.sendMessage(id, 'Cửa hàng sẵn sàng hỗ trợ.', 'reply-1');
      store.switchAccount(DemoAccount.customerA);
      expect((await repository.getConversations()).single.unreadCount, 1);
      expect(
        (await repository.getActivity(id))
            .otherSideReadAt(store.session.userId!),
        isNotNull,
      );
      store.switchAccount(DemoAccount.customerC);
      expect((await repository.getConversations()).single.id, isNot(id));
      await expectLater(
        repository.getMessages(id),
        throwsA(
          isA<ChatFailure>().having((e) => e.accessDenied, 'denied', true),
        ),
      );
      await expectLater(
        repository.sendMessage(id, 'foreign', 'foreign'),
        throwsA(isA<ChatFailure>()),
      );
    },
  );

  test(
    'existing chat view model reads and sends with no initialized SDK',
    () async {
      final store = LocalDemoStore();
      final repository = LocalChatRepository(() => store.session);
      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWith(
            (ref) => throw StateError('No SDK in local app'),
          ),
          chatSessionProvider.overrideWith((ref) => Stream.value('local-only')),
          chatViewerIdProvider.overrideWithValue(() => store.session.userId),
          chatEpochProvider.overrideWithValue(() => store.session.generation),
          chatRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final inboxSubscription = container.listen(chatInboxProvider, (_, _) {});
      addTearDown(inboxSubscription.close);
      final inbox = await container.read(chatInboxProvider.future);
      final provider = chatThreadProvider(inbox.single.id);
      final threadSubscription = container.listen(provider, (_, _) {});
      addTearDown(threadSubscription.close);
      await container.read(provider.future);
      expect(
        await container
            .read(provider.notifier)
            .send('Gửi từ giao diện hiện có'),
        true,
      );
      expect(
        container.read(provider).requireValue.page.messages.last.body,
        'Gửi từ giao diện hiện có',
      );
    },
  );
}
