import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sports_store/app/integration/production_feature_composition.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/notifications/presentation/providers/notification_providers.dart';

import '../../features/notifications/data/notification_supabase_test_support.dart';

void main() {
  test(
    'production Auth projection binds canonical inbox SDK reads and ACK',
    () async {
      final harness = NotificationSupabaseHarness();
      await harness.supplySession();
      var row = inboxRow(1);
      harness.handle = (request) async {
        if (request.url.path.endsWith('/profiles')) {
          return Response(
            jsonEncode([
              {
                'id': harness.scope.userId,
                'role': 'customer',
                'full_name': 'QA fixture',
                'phone': null,
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'HEAD') {
          return Response(
            '',
            200,
            headers: {'content-range': row['read_at'] == null ? '*/1' : '*/0'},
          );
        }
        if (request.method == 'PATCH') {
          row = {...row, 'read_at': '2026-10-27T02:00:00Z'};
        }
        return harness.rows([row]);
      };
      final container = ProviderContainer(
        overrides: [
          ...productionFeatureOverrides,
          supabaseClientProvider.overrideWithValue(harness.client),
        ],
      );
      try {
        container.listen(featureSessionScopeProvider, (_, _) {});
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(Duration.zero);
          await container.pump();
        }
        expect(
          container.read(featureSessionScopeProvider).canReadPrivateData,
          isTrue,
        );
        final repository = container.read(notificationRepositoryProvider)!;
        expect(
          identical(
            repository,
            container.read(supabaseNotificationRepositoryProvider),
          ),
          isTrue,
        );
        expect(
          (await repository.getPage(NotificationQuery())).items,
          hasLength(1),
        );
        expect(await repository.getUnreadCount(), 1);
        final ack = await repository.markRead(row['id']! as String);
        expect(ack.isRead, isTrue);
        await repository.markRead(row['id']! as String);
        expect(
          harness.requests.where((r) => r.method == 'PATCH'),
          hasLength(1),
        );
        expect(await repository.getUnreadCount(), 0);
      } finally {
        container.dispose();
        await harness.dispose();
      }
    },
  );
}
