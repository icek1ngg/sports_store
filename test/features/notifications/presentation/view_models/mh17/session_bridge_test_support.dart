import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_store/core/state/epoch_cache.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/notifications/presentation/view_models/mh17/notification_page_session_bridge.dart';

export 'package:flutter/material.dart';
export 'package:flutter_riverpod/flutter_riverpod.dart';
export 'package:flutter_test/flutter_test.dart';
export 'package:sports_store/core/state/epoch_cache.dart';
export 'package:sports_store/core/state/foundation_providers.dart';
export 'package:sports_store/core/state/session_scope.dart';
export 'package:sports_store/features/notifications/presentation/view_models/mh17/notification_page_session_bridge.dart';

const bridgeOwner = SessionScope(
  userId: '30000000-0000-4000-8000-000000000001',
  role: 'customer',
  generation: 1,
);

final controlledScope = NotifierProvider<ScopeControl, SessionScope>(
  ScopeControl.new,
);

class ScopeControl extends Notifier<SessionScope> {
  @override
  SessionScope build() => bridgeOwner;
  void change(SessionScope value) => state = value;
}

final controlledCache = NotifierProvider<CacheControl, EpochCache>(
  CacheControl.new,
);

class CacheControl extends Notifier<EpochCache> {
  @override
  EpochCache build() => EpochCache(ref.watch(controlledScope));
  void replace(EpochCache value) => state = value;
}

ProviderContainer bridgeContainer() => ProviderContainer(
  overrides: [
    featureSessionScopeProvider.overrideWith(
      (ref) => ref.watch(controlledScope),
    ),
    epochCacheProvider.overrideWith((ref) => ref.watch(controlledCache)),
  ],
);

class BridgeProbe {
  late NotificationPageSessionBridge bridge;
  final events = <String>[];
  String? marker;
  bool disposeImmediately = false;
  int? disposeAtChange;
  int changes = 0;
}

class BridgeHarness extends ConsumerStatefulWidget {
  const BridgeHarness(this.probe, {super.key});
  final BridgeProbe probe;
  @override
  ConsumerState<BridgeHarness> createState() => _HarnessState();
}

class _HarnessState extends ConsumerState<BridgeHarness> {
  @override
  void initState() {
    super.initState();
    final probe = widget.probe;
    probe.bridge = NotificationPageSessionBridge(
      onNamespaceChanged: () {
        probe.marker = null;
        probe.changes++;
        probe.events.add('namespace');
        if (probe.disposeImmediately ||
            probe.changes == probe.disposeAtChange) {
          probe.bridge.dispose();
        }
      },
      onResourceInvalidated: (resource) =>
          probe.events.add('resource:$resource'),
    );
    probe.bridge.attach(ref);
    probe.bridge.attach(ref); // Deliberate duplicate registration attempt.
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(featureSessionScopeProvider);
    final cache = ref.watch(epochCacheProvider);
    widget.probe.bridge.synchronize(scope, cache);
    widget.probe.events.add('render:${widget.probe.marker ?? 'empty'}');
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(widget.probe.marker ?? 'empty'),
    );
  }

  @override
  void dispose() {
    widget.probe.bridge.dispose();
    super.dispose();
  }
}

Widget bridgeHost(ProviderContainer container, BridgeProbe probe) =>
    UncontrolledProviderScope(
      container: container,
      child: BridgeHarness(probe),
    );
