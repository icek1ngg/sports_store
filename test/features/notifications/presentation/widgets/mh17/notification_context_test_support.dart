import 'notification_context_test_providers.dart';
export 'notification_context_test_providers.dart';

class ContextRig {
  ContextRig() {
    container = ProviderContainer(
      overrides: [
        featureSessionScopeProvider.overrideWith(
          (ref) => ref.watch(contextScopeProvider),
        ),
        notificationRepositoryProvider.overrideWithValue(repository),
      ],
    );
  }
  final repository = ContextRepository();
  final navigator = GlobalKey<NavigatorState>();
  final hostVisible = ValueNotifier(true);
  late final ProviderContainer container;
  NotificationContextHandle? handle;
  bool hostDisposed = false, completed = false;
  NotificationContextHandle create({
    String recipient = contextOwner,
    String title = 'Thông báo riêng A',
    String body = 'Nội dung riêng A',
  }) {
    final scope = container.read(featureSessionScopeProvider);
    final cache = container.read(epochCacheProvider);
    return handle = NotificationContextHandle(
      namespace: (scope: scope, cache: cache, lease: Object()),
      recipientId: recipient,
      query: NotificationQuery(),
      title: title,
      body: body,
    );
  }

  Future<void> mount(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigator,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              padding: const EdgeInsets.only(bottom: 24),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: hostVisible,
              builder: (_, visible, _) => visible
                  ? ContextHost(
                      handle: handle!,
                      onDispose: () => hostDisposed = true,
                      onComplete: () => completed = true,
                    )
                  : const Text('Host removed'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Open context'));
    await tester.pumpAndSettle();
  }

  void change(SessionScope scope) =>
      container.read(contextScopeProvider.notifier).change(scope);
  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    handle?.release();
    container.dispose();
    hostVisible.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

class ContextHost extends StatefulWidget {
  const ContextHost({
    required this.handle,
    required this.onDispose,
    required this.onComplete,
    super.key,
  });
  final NotificationContextHandle handle;
  final VoidCallback onDispose, onComplete;
  @override
  State<ContextHost> createState() => _ContextHostState();
}

class _ContextHostState extends State<ContextHost> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () {
      final handle = widget.handle;
      final complete = widget.onComplete;
      showContextRoute(context, handle).whenComplete(complete);
    },
    child: const Text('Open context'),
  );
}

Future<void> showContextRoute(
  BuildContext context,
  NotificationContextHandle handle,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => Mh17NotificationContextModal(handle: handle),
).whenComplete(handle.release);

void expectPrivateHidden(ContextRig rig) {
  expect(rig.handle!.isRevoked, true);
  expect(find.text('Thông báo riêng A'), findsNothing);
  expect(find.text('Nội dung riêng A'), findsNothing);
  expect(find.byType(Mh17NotificationContextModal), findsOneWidget);
  expect(rig.completed, false); // Hidden, not automatically popped.
}
