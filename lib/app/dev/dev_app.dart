import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/maps/map_display_adapter.dart';
import '../../core/maps/map_location.dart';
import '../../core/maps/map_providers.dart';
import '../../core/state/foundation_providers.dart';
import '../../core/state/read_retry_policy.dart';
import '../../core/state/session_scope.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../features/auth/presentation/view_models/auth_providers.dart';
import '../../features/cart/presentation/view_models/cart_providers.dart';
import '../../features/catalog/presentation/view_models/product_management_view_model.dart';
import '../../features/chat/presentation/view_models/chat_providers.dart';
import '../../features/checkout/presentation/view_models/checkout_providers.dart';
import '../../features/cod/presentation/view_models/cod_providers.dart';
import '../../features/deliveries/data/repositories/operational_providers.dart';
import '../../features/deliveries/data/repositories/operational_read_access.dart';
import '../../features/deliveries/presentation/view_models/delivery_providers.dart';
import '../../features/deliveries/presentation/view_models/outbound_action_providers.dart';
import '../../features/deliveries/presentation/view_models/outbound_completion_providers.dart';
import '../../features/deliveries/presentation/view_models/outbound_failure_providers.dart';
import '../../features/deliveries/presentation/view_models/outbound_retry_providers.dart';
import '../../features/deliveries/presentation/view_models/return_pickup_providers.dart';
import '../../features/deliveries/presentation/view_models/redelivery_providers.dart';
import '../../features/deliveries/presentation/view_models/delivery_reporting_providers.dart';
import '../../features/notifications/presentation/providers/notification_providers.dart';
import '../../features/notifications/presentation/providers/notification_interaction_view_model.dart';
import '../../features/orders/presentation/view_models/order_providers.dart';
import '../../features/returns/presentation/view_models/return_request_providers.dart';
import '../../features/returns/presentation/view_models/return_tracking_view_model.dart';
import '../../features/returns/presentation/view_models/manager_return_view_models.dart';
import '../demo/data/local_demo_store.dart';
import '../localization/app_localization.dart';
import '../theme/app_theme.dart';
import 'data/local_auth_repository.dart';
import 'data/local_chat_repository.dart';
import 'data/local_commerce_store.dart';
import 'data/local_operations.dart';
import 'dev_router.dart';

/// Full team application with device-only adapters. Production uses main.dart.
class FullDevApp extends StatefulWidget {
  const FullDevApp({this.store, super.key});
  final LocalDemoStore? store;
  @override
  State<FullDevApp> createState() => _FullDevAppState();
}

class _FullDevAppState extends State<FullDevApp> {
  late final LocalDemoStore store = (widget.store ?? LocalDemoStore())
    ..enableLocalReturns = true;
  late final LocalAuthRepository auth = LocalAuthRepository(store);
  late final LocalCommerceStore commerce = LocalCommerceStore(store);
  late final LocalOperations operations = LocalOperations(store);
  late final LocalReturns returns = LocalReturns(store);
  late final LocalChatRepository chat = LocalChatRepository(
    () => store.session,
  );
  int resets = 0;
  void reset() {
    store.reset();
    commerce.reset();
    returns.reset();
    chat.reset();
    setState(() => resets++);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: auth,
    builder: (context, _) => _DevSessionHost(
      key: ValueKey('${auth.epoch}:$resets'),
      store: store,
      auth: auth,
      commerce: commerce,
      operations: operations,
      returns: returns,
      chat: chat,
      reset: reset,
    ),
  );
  @override
  void dispose() {
    auth.dispose();
    super.dispose();
  }
}

/// Discard the previous account's entire navigator/provider tree on logout.
/// Business repositories remain above this boundary, retaining shared RAM data.
class _DevSessionHost extends StatefulWidget {
  const _DevSessionHost({
    required this.store,
    required this.auth,
    required this.commerce,
    required this.operations,
    required this.returns,
    required this.chat,
    required this.reset,
    super.key,
  });
  final LocalDemoStore store;
  final LocalAuthRepository auth;
  final LocalCommerceStore commerce;
  final LocalOperations operations;
  final LocalReturns returns;
  final LocalChatRepository chat;
  final VoidCallback reset;
  @override
  State<_DevSessionHost> createState() => _DevSessionHostState();
}

class _DevSessionHostState extends State<_DevSessionHost> {
  late final GoRouter router = createDevRouter(
    auth: widget.auth,
    store: widget.store,
    reset: widget.reset,
  );
  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final auth = widget.auth;
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        featureSessionScopeProvider.overrideWith(
          (ref) => auth.currentSession.signedIn
              ? store.session
              : const SessionScope.unresolved(),
        ),
        operationalSessionProvider.overrideWith(
          (ref) => Stream.value(
            OperationalSession(
              userId: auth.currentSession.userId,
              generation: store.session.generation,
            ),
          ),
        ),
        orderRepositoryProvider.overrideWithValue(store.orders),
        pendingOrderCommandStoreProvider.overrideWith(
          (ref) => store.pendingCommands,
        ),
        notificationRepositoryProvider.overrideWithValue(store.notifications),
        notificationTargetResolverProvider.overrideWithValue(
          store.targetResolver,
        ),
        catalogRepositoryProvider.overrideWithValue(widget.commerce.catalog),
        cartRepositoryProvider.overrideWithValue(widget.commerce.cart),
        checkoutRepositoryProvider.overrideWithValue(widget.commerce.checkout),
        pendingPlacementStoreProvider.overrideWithValue(
          widget.commerce.pendingPlacements,
        ),
        checkoutMapTilesEnabledProvider.overrideWithValue(false),
        catalogIdentityProvider.overrideWith(
          (ref) => Stream.value(auth.currentSession.accessToken),
        ),
        catalogSessionIdentityProvider.overrideWithValue(
          () => store.session.generation,
        ),
        productImageRepositoryProvider.overrideWithValue(widget.commerce),
        chatRepositoryProvider.overrideWithValue(widget.chat),
        chatSessionProvider.overrideWith(
          (ref) => Stream.value(auth.currentSession.accessToken),
        ),
        chatViewerIdProvider.overrideWithValue(
          () => auth.currentSession.userId,
        ),
        chatEpochProvider.overrideWithValue(() => store.session.generation),
        deliveryRepositoryProvider.overrideWithValue(widget.operations),
        codRepositoryProvider.overrideWithValue(widget.operations),
        codScreenRoleProvider.overrideWith(
          (ref) => AsyncData(store.session.role!),
        ),
        retryCodScreenRoleProvider.overrideWithValue(() {}),
        codReceiptRepositoryProvider.overrideWithValue(
          const LocalUnavailableCodReceipt(),
        ),
        outboundTaskCommandRepositoryProvider.overrideWithValue(
          const LocalUnavailableOutbound(),
        ),
        outboundCompletionRepositoryProvider.overrideWithValue(
          const LocalUnavailableCompletion(),
        ),
        outboundFailureRepositoryProvider.overrideWithValue(
          const LocalUnavailableFailure(),
        ),
        outboundRetryRepositoryProvider.overrideWithValue(
          const LocalUnavailableRetry(),
        ),
        returnPickupRepositoryProvider.overrideWithValue(
          const LocalUnavailablePickup(),
        ),
        redeliveryRepositoryProvider.overrideWithValue(
          const LocalUnavailableRedelivery(),
        ),
        deliveryReportingRepositoryProvider.overrideWithValue(
          const LocalUnavailableReporting(),
        ),
        returnRequestRepositoryProvider.overrideWithValue(
          widget.returns.requests,
        ),
        returnTrackingRepositoryProvider.overrideWithValue(
          widget.returns.tracking,
        ),
        managerReturnRepositoryProvider.overrideWithValue(
          widget.returns.manager,
        ),
        mapDisplayAdapterProvider.overrideWithValue(const _OfflineMap()),
        readRetryPolicyProvider.overrideWithValue(
          const ReadRetryPolicy(backoffs: []),
        ),
        supabaseClientProvider.overrideWith(
          (ref) => throw StateError(
            'Local app does not construct a Supabase client.',
          ),
        ),
      ],
      child: MaterialApp.router(
        title: 'Sports Store',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: AppLocalization.locale,
        supportedLocales: AppLocalization.supportedLocales,
        localizationsDelegates: AppLocalization.delegates,
        routerConfig: router,
      ),
    );
  }

  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }
}

class _OfflineMap implements MapDisplayAdapter {
  const _OfflineMap();
  @override
  Widget buildMap({
    Key? key,
    required MapLocation location,
    int recenterToken = 0,
    double height = 320,
    ValueChanged<Object>? onTileError,
  }) => Container(
    key: key,
    height: height,
    width: double.infinity,
    color: const Color(0xffe8eeea),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.location_on, color: Colors.red, size: 44),
        const SizedBox(height: 12),
        Text(
          '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}',
        ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Vị trí đã lưu. Nền bản đồ cần kết nối mạng.',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ),
  );
}
