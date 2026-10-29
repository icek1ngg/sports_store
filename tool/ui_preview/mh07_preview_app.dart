// Debug-only UI harness. It reuses the feature contracts without initializing
// Auth or Supabase and never changes the production entrypoint.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/core/state/read_retry_policy.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/orders/presentation/pages/customer_orders_page.dart';
import 'package:sports_store/features/orders/presentation/view_models/order_providers.dart';

import '../../test/fixtures/order_notification_fixtures.dart';
import 'mh07_preview_data.dart';

export 'mh07_preview_data.dart' show PreviewScenario, PreviewOrderRepository;

/// The provider scope is intentionally stable for the lifetime of the
/// preview. The navigator and its dialog routes are descendants of this
/// scope, so changing a scenario cannot dispose a scope while a route is live.
class UiPreviewApp extends StatefulWidget {
  const UiPreviewApp({this.showControls = true, super.key});

  final bool showControls;

  @override
  State<UiPreviewApp> createState() => _UiPreviewAppState();
}

class _UiPreviewAppState extends State<UiPreviewApp> {
  late final _PreviewEnvironment _environment;

  @override
  void initState() {
    super.initState();
    _environment = _PreviewEnvironment();
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      // Do not key this scope by screen/scenario. Its container owns the
      // Navigator's provider graph and must outlive modal routes.
      key: const ValueKey('ui-preview-provider-scope'),
      overrides: [
        featureSessionScopeProvider.overrideWith((ref) => _environment.scope),
        orderRepositoryProvider.overrideWith((ref) => _environment.orders),
        readRetryPolicyProvider.overrideWithValue(
          const ReadRetryPolicy(backoffs: []),
        ),
      ],
      child: _UiPreviewSurface(
        environment: _environment,
        showControls: widget.showControls,
      ),
    );
  }
}

class _PreviewEnvironment {
  _PreviewEnvironment()
    : orders = PreviewOrderRepository(),
      scope = const SessionScope(
        userId: fixtureCustomerId,
        role: 'customer',
        generation: 1,
      );

  final PreviewOrderRepository orders;
  SessionScope scope;
  int _generation = 1;

  void select({required String screen, required PreviewScenario scenario}) {
    orders.setScenario(scenario);
    _generation++;
    scope = scenario == PreviewScenario.expired
        ? SessionScope(userId: null, role: null, generation: _generation)
        : SessionScope(
            userId: fixtureCustomerId,
            role: 'customer',
            generation: _generation,
          );
  }
}

class _UiPreviewSurface extends StatefulWidget {
  const _UiPreviewSurface({
    required this.environment,
    required this.showControls,
  });

  final _PreviewEnvironment environment;
  final bool showControls;

  @override
  State<_UiPreviewSurface> createState() => _UiPreviewSurfaceState();
}

class _UiPreviewSurfaceState extends State<_UiPreviewSurface> {
  String screen = 'MH07';
  PreviewScenario scenario = PreviewScenario.data;

  void _selectScenario(PreviewScenario value) {
    if (value == scenario) return;
    setState(() => scenario = value);
    _refreshProviderGraph();
  }

  void _refreshProviderGraph() {
    widget.environment.select(screen: screen, scenario: scenario);
    // Invalidating the session provider rebuilds its dependents and gives
    // each foundation notifier a fresh cache namespace. The ProviderScope
    // itself remains mounted above MaterialApp/Navigator.
    ProviderScope.containerOf(
      context,
      listen: false,
    ).invalidate(featureSessionScopeProvider);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sports Store — UI Preview',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Builder(
        builder: (navigatorContext) => Scaffold(
          // The feature Scaffold owns keyboard insets. Applying them twice
          // shrinks MH07's body twice when the demo toolbar is present.
          resizeToAvoidBottomInset: false,
          appBar: widget.showControls ? _buildAppBar() : null,
          body: _buildBody(navigatorContext),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      toolbarHeight: 48,
      title: const Text(
        'DEMO UI · dữ liệu kiểm thử',
        style: TextStyle(fontSize: 12),
      ),
      actions: [
        PopupMenuButton<PreviewScenario>(
          initialValue: scenario,
          tooltip: 'Chọn trạng thái',
          onSelected: _selectScenario,
          itemBuilder: (_) => PreviewScenario.values
              .map(
                (value) => PopupMenuItem(value: value, child: Text(value.name)),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext navigatorContext) => const CustomerOrdersPage(
    enablePolling: false,
    showPreviewNavigation: true,
  );
}
