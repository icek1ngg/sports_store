import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/features/orders/domain/models/order_query.dart';
import 'package:sports_store/features/orders/presentation/pages/customer_orders_page.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_order_details_page.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_orders_page.dart';
import 'package:sports_store/features/orders/presentation/view_models/order_providers.dart';

import 'mh08_manager_repository.dart';
import 'mh08_preview_controls.dart';
import 'mh08_preview_environment.dart';

class Mh08PreviewSurface extends ConsumerStatefulWidget {
  const Mh08PreviewSurface({
    required this.environment,
    required this.showControls,
    super.key,
  });
  final Mh08PreviewEnvironment environment;
  final bool showControls;
  @override
  ConsumerState<Mh08PreviewSurface> createState() => _Mh08PreviewSurfaceState();
}

class _Mh08PreviewSurfaceState extends ConsumerState<Mh08PreviewSurface> {
  final _navigator = GlobalKey<NavigatorState>();
  Timer? _staleTimer;
  Mh08PreviewEnvironment get env => widget.environment;

  @override
  void initState() {
    super.initState();
    env.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    _staleTimer?.cancel();
    ref.invalidate(featureSessionScopeProvider);
    setState(() {});
    if (env.managerActive && env.scenario == Mh08PreviewScenario.stale) {
      final generation = env.generation;
      _staleTimer = Timer(const Duration(milliseconds: 700), () {
        if (!mounted || generation != env.generation) return;
        ref.read(epochCacheProvider).invalidatePrefix('orders/list/');
      });
    }
  }

  @override
  void dispose() {
    env.removeListener(_changed);
    _staleTimer?.cancel();
    super.dispose();
  }

  OrderQuery get _canonicalQuery =>
      env.manager.managerReads
          .where((query) => query.cursor == null)
          .lastOrNull ??
      OrderQuery();

  Future<void> _openOrder(String id) async {
    if (!mounted || !env.managerActive) return;
    final scope = ref.read(featureSessionScopeProvider);
    final query = _canonicalQuery;
    await _navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ManagerOrderDetailsPage(orderId: id, enablePolling: false),
      ),
    );
    if (!mounted ||
        !env.managerActive ||
        scope != ref.read(featureSessionScopeProvider) ||
        !scope.canReadPrivateData ||
        !ref.read(epochCacheProvider).canRead) {
      return;
    }
    await ref.read(orderListFoundationProvider(query).notifier).refresh();
  }

  void _nextPageError() {
    if (!mounted ||
        env.scope.role != 'manager' ||
        !env.scope.canReadPrivateData) {
      return;
    }
    env.manager.failNextPageForDemo();
    unawaited(
      ref.read(orderListFoundationProvider(_canonicalQuery).notifier).refresh(),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Sports Store — UI Preview',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    navigatorKey: _navigator,
    home: Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: widget.showControls
          ? Mh08PreviewControls(
              environment: env,
              onNextPageError: _nextPageError,
            )
          : null,
      body: env.managerActive
          ? ManagerOrdersPage(enablePolling: false, onOpenOrder: _openOrder)
          : const CustomerOrdersPage(
              enablePolling: false,
              showPreviewNavigation: true,
            ),
    ),
  );
}
