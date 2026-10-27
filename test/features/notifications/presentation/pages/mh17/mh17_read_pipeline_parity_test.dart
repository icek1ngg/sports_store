import 'mh17_modal_integration_support.dart';

import 'package:sports_store/features/notifications/presentation/view_models/mh17/notification_page_read_coordinator.dart';
import 'package:sports_store/features/notifications/presentation/view_models/mh17/notification_page_session_bridge.dart';
import 'package:sports_store/features/notifications/presentation/view_models/notification_interaction_view_model.dart';

void main() {
  testWidgets(
    'required Phase A parity: same-owner cache replacement retains disabled stale rows',
    (tester) async {
      final rig = PageModalRig();
      // Public owner APIs alongside the real Page provide a pre-integration oracle.
      // No duplicate pipeline is installed into production to hide the mismatch.
      final bridge = NotificationPageSessionBridge(
        onNamespaceChanged: () {},
        onResourceInvalidated: (_) {},
      );
      final reads = NotificationPageReadCoordinator(session: bridge);
      final query = NotificationQuery();
      final pending = Completer<NotificationPage>();
      NotificationReadNamespace current() {
        final scope = rig.container.read(featureSessionScopeProvider);
        final cache = rig.container.read(epochCacheProvider);
        return (
          scope: scope,
          cache: cache,
          lease: bridge.captureLease(scope, cache),
        );
      }

      final NotificationReadPorts ports = (
        current: current,
        page: (query) => rig.container
            .read(notificationPageFoundationProvider(query))
            .asData
            ?.value,
        count: () =>
            rig.container.read(unreadCountFoundationProvider).asData?.value,
        refreshPage: (query) => rig.container
            .read(notificationPageFoundationProvider(query).notifier)
            .refresh(),
        refreshCount: () => rig.container
            .read(unreadCountFoundationProvider.notifier)
            .refresh(),
        invalidateInteractions: () =>
            rig.container.invalidate(notificationInteractionViewModelProvider),
      );
      try {
        await rig.mount(tester);
        await rig.open(tester);
        final oldNamespace = current();
        final head = reads.headIntent(oldNamespace)!;
        expect(reads.acceptPage(head, query, ports.page(query)!, ports), true);
        final accepted = reads.items.single;
        expect(accepted.recipientId, contextOwner);
        expect(reads.canInteract(ports, query), true);

        rig.repository.pageHandler = (_) => pending.future;
        rig.container.invalidate(epochCacheProvider);
        await tester.pump();
        rig.modalHidden(tester);
        // The existing approved Page test explicitly requires this stale tile.
        final oldTile = tester.widget<NotificationTile>(
          find.byType(NotificationTile, skipOffstage: false),
        );
        expect(oldTile.notification, same(accepted));
        expect(oldTile.onTap, isNull);
        expect(oldTile.onMarkRead, isNull);
        final live = current();
        expect(live.scope, oldNamespace.scope);
        expect(identical(live.cache, oldNamespace.cache), false);
        expect(live.cache.canRead, true);
        expect(
          reads.synchronize(
            live,
            preserveSameOwnerStaleDisplay: true,
            query: query,
          ),
          true,
        );
        expect(reads.canInteract(ports, query), false);

        // Fails with the protected owner: synchronize arms keepItems:false.
        // Retaining another Page-local list would conceal competing ownership.
        expect(reads.items, [accepted]);
      } finally {
        reads.dispose();
        bridge.dispose();
        if (!pending.isCompleted) {
          pending.complete(contextPage(contextScope, 'B'));
        }
        await tester.pumpAndSettle();
        await rig.cleanup(tester);
      }
    },
  );
}
