import 'mh17_modal_integration_repository.dart';
export 'mh17_modal_integration_repository.dart';

class PageModalRig {
  PageModalRig() {
    repository = ModalPageRepository(() => scope);
    container = ProviderContainer(
      overrides: [
        featureSessionScopeProvider.overrideWith(
          (ref) => ref.watch(contextScopeProvider),
        ),
        notificationRepositoryProvider.overrideWithValue(repository),
        readRetryPolicyProvider.overrideWithValue(
          const ReadRetryPolicy(backoffs: []),
        ),
      ],
    );
  }
  late final ProviderContainer container;
  late final ModalPageRepository repository;
  final navigator = GlobalKey<NavigatorState>();
  final visible = ValueNotifier(true);
  NavigatorObserver? observer;
  bool pageLocalScope = false;
  SessionScope get scope => container.read(featureSessionScopeProvider);
  void change(SessionScope scope) =>
      container.read(contextScopeProvider.notifier).change(scope);
  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [?observer],
          home: ValueListenableBuilder(
            valueListenable: visible,
            builder: (_, show, _) => show
                ? pageLocalScope
                      ? const ProviderScope(
                          child: NotificationsPage(enablePolling: false),
                        )
                      : const NotificationsPage(enablePolling: false)
                : const Scaffold(body: Text('Host removed')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Thông báo riêng ${repository.label}'));
    await tester.pumpAndSettle();
  }

  NotificationContextHandle handle(WidgetTester tester) => tester
      .widget<Mh17NotificationContextModal>(
        find.byType(Mh17NotificationContextModal),
      )
      .handle;
  Future<void> refresh(WidgetTester tester) async {
    final read = container
        .read(notificationPageFoundationProvider(NotificationQuery()).notifier)
        .refresh();
    await tester.pumpAndSettle();
    await read;
  }

  void hidden(WidgetTester tester) {
    modalHidden(tester);
    expect(find.text('Thông báo riêng A', skipOffstage: false), findsNothing);
    expect(find.text('Nội dung riêng A', skipOffstage: false), findsNothing);
  }

  void modalHidden(WidgetTester tester) {
    expect(handle(tester).isRevoked, true);
    expect(find.byType(Mh17NotificationContextModal), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Mh17NotificationContextModal),
        matching: find.text('Thông báo riêng A'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(Mh17NotificationContextModal),
        matching: find.text('Nội dung riêng A'),
      ),
      findsNothing,
    );
    expect(find.byType(Mh17NotificationContextSheet), findsNothing);
    expect(navigator.currentState!.canPop(), true);
  }

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    visible.dispose();
  }
}

class ContextPushObserver extends NavigatorObserver {
  NotificationContextHandle? handle;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is ModalBottomSheetRoute) {
      final widget = route.builder(navigator!.context);
      if (widget is Mh17NotificationContextModal) handle = widget.handle;
    }
  }
}
