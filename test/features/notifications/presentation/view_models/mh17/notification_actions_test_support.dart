import 'notification_action_fakes.dart';
export 'notification_action_fakes.dart';

final actionScope = NotifierProvider<ActionScope, SessionScope>(
  ActionScope.new,
);

class ActionScope extends Notifier<SessionScope> {
  @override
  SessionScope build() => const SessionScope(
    userId: fixtureCustomerId,
    role: 'customer',
    generation: 1,
  );
  void change(SessionScope value) => state = value;
}

class ActionRig {
  ActionRig({bool hasResolver = true}) {
    container = ProviderContainer(
      overrides: [
        featureSessionScopeProvider.overrideWith(
          (ref) => ref.watch(actionScope),
        ),
        notificationRepositoryProvider.overrideWithValue(repository),
        notificationTargetResolverProvider.overrideWithValue(
          hasResolver ? resolver : null,
        ),
      ],
    );
    session = NotificationPageSessionBridge(
      onNamespaceChanged: () => reads.reset(),
      onResourceInvalidated: (key) =>
          reads.onResourceInvalidated(key, readPorts),
    );
    reads = NotificationPageReadCoordinator(session: session);
    actions = NotificationPageActions(session: session, reads: reads);
    subscription = container.listen(
      notificationInteractionViewModelProvider,
      (_, _) {},
    );
  }
  final repository = ActionRepositoryFake();
  final resolver = ActionResolverFake();
  late final ProviderContainer container;
  late final NotificationPageSessionBridge session;
  late final NotificationPageReadCoordinator reads;
  late final NotificationPageActions actions;
  late final ProviderSubscription<NotificationInteractionState> subscription;
  final pages = <NotificationQuery, ReadSnapshot<NotificationPage>>{};
  final messages = <String>[];
  final contexts = <(String, String)>[];
  final navigations = <NotificationTargetDecision>[];
  Future<bool> Function(NotificationTargetDecision)? onNavigate;
  bool active = true, hasNavigation = true;
  var stateReads = 0, currentReads = 0;
  SessionScope get scope => container.read(featureSessionScopeProvider);
  EpochCache get cache => container.read(epochCacheProvider);
  NotificationReadNamespace get namespace =>
      (scope: scope, cache: cache, lease: session.captureLease(scope, cache));
  NotificationReadPorts get readPorts => (
    current: () {
      currentReads++;
      return namespace;
    },
    page: (query) => pages[query],
    count: () => const ReadSnapshot(data: 41),
    refreshPage: (_) async {},
    refreshCount: () async {},
    invalidateInteractions: () =>
        container.invalidate(notificationInteractionViewModelProvider),
  );
  NotificationActionPorts get ports => (
    isActive: () => active,
    reads: readPorts,
    query: () => reads.headQuery,
    interaction: () =>
        container.read(notificationInteractionViewModelProvider.notifier),
    state: () {
      stateReads++;
      return container.read(notificationInteractionViewModelProvider);
    },
    navigation: () => hasNavigation ? navigate : null,
    message: messages.add,
    context: (_, item) => contexts.add((item.title, item.body)),
  );
  Future<bool> navigate(NotificationTargetDecision decision) {
    navigations.add(decision);
    return onNavigate?.call(decision) ?? Future.value(true);
  }

  NotificationReadNamespace seed(NotificationItem item) {
    final submitted = namespace;
    final ticket = reads.headIntent(submitted)!;
    final page = NotificationPage(
      items: [item],
      nextCursor: null,
      unreadCount: 1,
      asOf: DateTime.utc(2026, 10, 22),
    );
    final query = reads.headQuery;
    cache.accept(
      cache.begin(NotificationSnapshotProjection.resourceKey(query)),
      page,
    );
    cache.accept(cache.begin('notifications/count'), 41);
    final snapshot = pages[query] = ReadSnapshot(data: page);
    expect(reads.acceptPage(ticket, query, snapshot, readPorts), true);
    return submitted;
  }

  void dispose() {
    actions.dispose();
    reads.dispose();
    session.dispose();
    subscription.close();
    container.dispose();
  }
}

Future<void> settleAction() => Future<void>.delayed(Duration.zero);
