import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/foundation_providers.dart';
import '../../core/state/read_retry_policy.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../features/notifications/presentation/providers/notification_interaction_view_model.dart';
import '../../features/notifications/presentation/providers/notification_providers.dart';
import '../../features/orders/presentation/view_models/order_providers.dart';
import '../localization/app_localization.dart';
import '../router/demo_router.dart';
import '../theme/app_theme.dart';
import 'data/local_demo_store.dart';

String demoAccountLabel(DemoAccount account) => switch (account) {
  DemoAccount.customerA => 'Customer A',
  DemoAccount.managerB => 'Manager B',
  DemoAccount.customerC => 'Customer C',
  DemoAccount.shipper => 'Shipper',
};

/// One in-memory business store and one stable provider container. UI pages and
/// their existing mutation/read coordinators are shared with Live Mode.
class LocalDemoApp extends StatefulWidget {
  const LocalDemoApp({this.store, super.key});
  final LocalDemoStore? store;

  @override
  State<LocalDemoApp> createState() => _LocalDemoAppState();
}

class _LocalDemoAppState extends State<LocalDemoApp> {
  late final LocalDemoStore _store = widget.store ?? LocalDemoStore();
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final GoRouter _router = createDemoRouter(
    store: _store,
    navigatorKey: _navigatorKey,
    shellBuilder: (context, state, child) => _DemoShell(
      store: _store,
      location: state.uri.path,
      onAccount: (account) => _changeSession(context, account: account),
      onReset: () => _changeSession(context, reset: true),
      child: child,
    ),
  );

  void _changeSession(
    BuildContext context, {
    DemoAccount? account,
    bool reset = false,
  }) {
    // Close pageless dialogs/detail routes before changing their namespace.
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    if (reset) {
      _store.reset();
    } else if (account != null && account != _store.account) {
      _store.switchAccount(account);
    } else {
      return;
    }
    final container = ProviderScope.containerOf(context, listen: false);
    container.invalidate(featureSessionScopeProvider);
    _router.go(
      _store.session.role == 'manager' ? '/manager/orders' : '/customer/orders',
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => ProviderScope(
    key: const ValueKey('local-demo-provider-scope'),
    overrides: [
      featureSessionScopeProvider.overrideWith((ref) => _store.session),
      orderRepositoryProvider.overrideWithValue(_store.orders),
      notificationRepositoryProvider.overrideWithValue(_store.notifications),
      pendingOrderCommandStoreProvider.overrideWith((ref) {
        ref.watch(featureSessionScopeProvider);
        return _store.pendingCommands;
      }),
      notificationTargetResolverProvider.overrideWithValue(null),
      readRetryPolicyProvider.overrideWithValue(
        const ReadRetryPolicy(backoffs: []),
      ),
      supabaseClientProvider.overrideWith(
        (ref) => throw StateError('Demo Mode không sử dụng Supabase client.'),
      ),
    ],
    child: MaterialApp.router(
      title: 'Sports Store — DEMO LOCAL',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: AppLocalization.locale,
      supportedLocales: AppLocalization.supportedLocales,
      localizationsDelegates: AppLocalization.delegates,
      routerConfig: _router,
    ),
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }
}

class _DemoShell extends ConsumerWidget {
  const _DemoShell({
    required this.store,
    required this.location,
    required this.onAccount,
    required this.onReset,
    required this.child,
  });
  final LocalDemoStore store;
  final String location;
  final ValueChanged<DemoAccount> onAccount;
  final VoidCallback onReset;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(featureSessionScopeProvider);
    final unread = ref.watch(unreadCountFoundationProvider).asData?.value.data;
    final manager = store.session.role == 'manager';
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        toolbarHeight: 48,
        automaticallyImplyLeading: false,
        backgroundColor: Colors.amber.shade100,
        title: const Text(
          'DEMO LOCAL · OFFLINE',
          style: TextStyle(fontSize: 12),
        ),
        actions: [
          PopupMenuButton<DemoAccount>(
            key: const ValueKey('demo-account-menu'),
            tooltip: 'Chuyển tài khoản demo',
            onSelected: onAccount,
            itemBuilder: (_) => DemoAccount.values
                .map(
                  (account) => PopupMenuItem(
                    value: account,
                    child: Text(demoAccountLabel(account)),
                  ),
                )
                .toList(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Text(
                    demoAccountLabel(store.account),
                    style: const TextStyle(fontSize: 12),
                  ),
                  const Icon(Icons.swap_horiz, size: 18),
                ],
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('demo-reset'),
            tooltip: 'Khởi tạo lại dữ liệu demo',
            onPressed: onReset,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: location.startsWith('/notifications') ? 1 : 0,
        onDestinationSelected: (index) => context.go(
          index == 1
              ? '/notifications'
              : manager
              ? '/manager/orders'
              : '/customer/orders',
        ),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            label: manager ? 'MH08' : 'MH07',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unread != null && unread > 0,
              label: Text(
                '${unread ?? 0}',
                key: const ValueKey('demo-unread-count'),
              ),
              child: const Icon(Icons.notifications_outlined),
            ),
            label: 'MH17',
          ),
        ],
      ),
    );
  }
}
