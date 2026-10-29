import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/core/state/read_retry_policy.dart';
import 'package:sports_store/features/orders/presentation/view_models/order_providers.dart';

import 'mh08_preview_environment.dart';
import 'mh08_preview_surface.dart';

/// Active debug harness; one scope outlives both Navigator and modal routes.
class Mh08PreviewApp extends StatefulWidget {
  const Mh08PreviewApp({this.showControls = true, this.environment, super.key});
  final bool showControls;
  final Mh08PreviewEnvironment? environment;

  @override
  State<Mh08PreviewApp> createState() => _Mh08PreviewAppState();
}

class _Mh08PreviewAppState extends State<Mh08PreviewApp> {
  late final _environment = widget.environment ?? Mh08PreviewEnvironment();

  @override
  void dispose() {
    if (widget.environment == null) _environment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProviderScope(
    key: const ValueKey('ui-preview-provider-scope'),
    overrides: [
      featureSessionScopeProvider.overrideWith((ref) => _environment.scope),
      orderRepositoryProvider.overrideWith((ref) => _environment.orders),
      readRetryPolicyProvider.overrideWithValue(
        const ReadRetryPolicy(backoffs: []),
      ),
    ],
    child: Mh08PreviewSurface(
      environment: _environment,
      showControls: widget.showControls,
    ),
  );
}
