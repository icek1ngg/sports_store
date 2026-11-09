import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/foundation_providers.dart';
import '../../features/auth/presentation/view_models/auth_providers.dart';
import '../../features/notifications/presentation/providers/notification_providers.dart';
import '../../features/orders/presentation/view_models/order_providers.dart';

/// The only production overrides for the existing feature foundations.
/// Preview continues to supply its own explicitly labelled fixture overrides.
final productionFeatureOverrides = [
  featureSessionScopeProvider.overrideWith(
    (ref) => ref.watch(trustedFeatureSessionProvider),
  ),
  notificationRepositoryProvider.overrideWith(
    (ref) => ref.watch(supabaseNotificationRepositoryProvider),
  ),
  orderRepositoryProvider.overrideWith(
    (ref) => ref.watch(supabaseOrderRepositoryProvider),
  ),
];

class FeatureSessionLifecycle extends ConsumerStatefulWidget {
  const FeatureSessionLifecycle({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<FeatureSessionLifecycle> createState() =>
      _FeatureSessionLifecycleState();
}

class _FeatureSessionLifecycleState
    extends ConsumerState<FeatureSessionLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Existing Auth remains the role authority. Hide private data while the
      // server profile is being revalidated; never reuse a previous AsyncValue.
      ref.invalidate(currentProfileProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Eagerly observe startup/logout/expiry even before feature routes exist.
    ref.watch(featureSessionScopeProvider);
    ref.watch(orderPendingRecoveryProvider);
    return widget.child;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
