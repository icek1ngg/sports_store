import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/core/state/read_retry_policy.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/notifications/data/models/notification_dto.dart';
import 'package:sports_store/features/notifications/presentation/providers/notification_interaction_view_model.dart';
import 'package:sports_store/features/notifications/presentation/providers/notification_providers.dart';

import 'notification_supabase_test_support.dart';

Future<void> settle(ProviderContainer container) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    await Future<void>.delayed(Duration.zero);
    await container.pump();
  }
}

void main() {
  late NotificationSupabaseHarness harness;
  late ProviderContainer container;
  setUp(() async {
    harness = NotificationSupabaseHarness();
    await harness.supplySession();
    container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(harness.client),
        featureSessionScopeProvider.overrideWith((ref) => harness.scope),
        notificationRepositoryProvider.overrideWith(
          (ref) => ref.watch(supabaseNotificationRepositoryProvider),
        ),
        readRetryPolicyProvider.overrideWithValue(
          const ReadRetryPolicy(backoffs: []),
        ),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await harness.dispose();
  });

  test(
    'canonical foundations use opt-in SDK repository without extra authorities',
    () async {
      harness.handle = (request) async => request.method == 'HEAD'
          ? Response('', 200, headers: {'content-range': '*/137'})
          : harness.rows([inboxRow(1)]);
      final page = notificationPageFoundationProvider(NotificationQuery());
      container.listen(page, (_, _) {});
      container.listen(unreadCountFoundationProvider, (_, _) {});
      await settle(container);
      expect(
        container.read(page).requireValue.data!.items.single.id,
        inboxRow(1)['id'],
      );
      expect(
        container.read(unreadCountFoundationProvider).requireValue.data,
        137,
      );
      expect(harness.requests.where((r) => r.method == 'GET'), hasLength(1));
      expect(harness.requests.where((r) => r.method == 'HEAD'), hasLength(1));
    },
  );

  test(
    'canonical read ACK refreshes page and exact count, not local decrement',
    () async {
      var row = inboxRow(1);
      harness.handle = (request) async {
        if (request.method == 'HEAD') {
          return Response(
            '',
            200,
            headers: {
              'content-range': row['read_at'] == null ? '*/137' : '*/120',
            },
          );
        }
        if (request.method == 'PATCH') {
          row = {...row, 'read_at': '2026-10-27T02:00:00Z'};
        }
        return harness.rows([row]);
      };
      final page = notificationPageFoundationProvider(NotificationQuery());
      container.listen(page, (_, _) {});
      container.listen(unreadCountFoundationProvider, (_, _) {});
      await settle(container);
      final success = await container
          .read(notificationInteractionViewModelProvider.notifier)
          .markRead(NotificationDto.fromJson(row).domain);
      await settle(container);
      expect(success, isTrue);
      expect(
        container.read(unreadCountFoundationProvider).requireValue.data,
        120,
      );
      expect(
        container.read(page).requireValue.data!.items.single.readAt,
        DateTime.utc(2026, 10, 27, 2),
      );
    },
  );

  test(
    'account change rejects old SDK response before it reaches new cache',
    () async {
      final pending = Completer<Response>();
      final started = Completer<void>();
      harness.handle = (request) {
        if (request.url.queryParameters['recipient_id'] ==
            'eq.$fixtureCustomerId') {
          started.complete();
          return pending.future;
        }
        return Future.value(
          harness.rows([inboxRow(2, recipient: otherRecipient)]),
        );
      };
      final page = notificationPageFoundationProvider(NotificationQuery());
      container.listen(page, (_, _) {});
      await started.future;
      await harness.supplySession(userId: otherRecipient, generation: 2);
      container.invalidate(featureSessionScopeProvider);
      await settle(container);
      pending.complete(harness.rows([inboxRow(1)]));
      await settle(container);
      final accepted = container.read(page).requireValue.data!;
      expect(accepted.items.single.recipientId, otherRecipient);
      expect(accepted.items.single.id, inboxRow(2)['id']);
    },
  );

  test(
    'pending adapter response after container disposal is safely rejected',
    () async {
      final isolated = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(harness.client),
          featureSessionScopeProvider.overrideWithValue(harness.scope),
        ],
      );
      final pending = Completer<Response>();
      final started = Completer<void>();
      harness.handle = (_) {
        started.complete();
        return pending.future;
      };
      final result = isolated
          .read(supabaseNotificationRepositoryProvider)
          .getUnreadCount();
      final assertion = expectLater(
        result,
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.code,
            'code',
            AppFailure.unauthenticated,
          ),
        ),
      );
      await started.future;
      isolated.dispose();
      pending.complete(Response('', 200, headers: {'content-range': '*/7'}));
      await assertion;
    },
  );

  test(
    'unbound canonical repository remains null and never initializes SDK',
    () {
      final unbound = ProviderContainer();
      expect(unbound.read(notificationRepositoryProvider), isNull);
      expect(
        unbound.read(featureSessionScopeProvider).canReadPrivateData,
        isFalse,
      );
      unbound.dispose();
    },
  );
}
