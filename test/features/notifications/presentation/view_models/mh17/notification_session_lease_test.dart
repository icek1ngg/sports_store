import 'session_bridge_test_support.dart';

void main() {
  late NotificationPageSessionBridge bridge;
  late EpochCache cache;
  late int changes;
  setUp(() {
    changes = 0;
    cache = EpochCache(bridgeOwner);
    bridge = NotificationPageSessionBridge(
      onNamespaceChanged: () => changes++,
      onResourceInvalidated: (_) {},
    );
  });
  tearDown(() {
    bridge.dispose();
    cache.dispose();
  });

  test(
    'explicit synchronization requires live namespace, not just lease identity',
    () {
      final lease = bridge.captureLease(bridgeOwner, cache);
      final foreign = EpochCache(const SessionScope.unresolved());
      expect(bridge.isCurrent(lease, bridgeOwner, foreign), false);
      expect(bridge.captureLease(bridgeOwner, foreign), isNull);
      expect(bridge.isCurrent(lease, bridgeOwner, cache), false);
      foreign.dispose();
    },
  );

  test('same-cache block without resources is caught by pre-render synchronization', () {
    final lease = bridge.captureLease(bridgeOwner, cache);
    final before = changes;
    cache.blockSession(); // Empty cache emits no resource event.
    expect(changes, before);
    bridge.synchronize(bridgeOwner, cache);
    expect(changes, before + 1);
    expect(bridge.isCurrent(lease, bridgeOwner, cache), false);
  });

  test('cache disposal without events is caught on live check', () {
    final lease = bridge.captureLease(bridgeOwner, cache);
    cache.dispose();
    expect(bridge.isCurrent(lease, bridgeOwner, cache), false);
    expect(bridge.captureLease(bridgeOwner, cache), isNull);
  });

  test('explicit revocation rotates lease synchronously without owning access recovery', () {
    final lease = bridge.captureLease(bridgeOwner, cache);
    final before = changes;
    bridge.revokeAccess();
    expect(changes, before + 1);
    expect(bridge.isCurrent(lease, bridgeOwner, cache), false);
    // Owner must independently recheck its access latch before using a new lease.
    expect(bridge.captureLease(bridgeOwner, cache), isNotNull);
  });

  test('leases have no payload and cannot cross bridge instances', () {
    final lease = bridge.captureLease(bridgeOwner, cache);
    final other = NotificationPageSessionBridge(
      onNamespaceChanged: () {},
      onResourceInvalidated: (_) {},
    );
    expect(lease.runtimeType, Object);
    expect(other.isCurrent(lease, bridgeOwner, cache), false);
    expect(bridge.isCurrent(Object(), bridgeOwner, cache), false);
    expect(bridge.isCurrent(null, bridgeOwner, cache), false);
    other.dispose();
  });

  test('disposed bridge cannot rebind, revoke or expose an old lease', () {
    final lease = bridge.captureLease(bridgeOwner, cache);
    final before = changes;
    bridge.dispose();
    bridge.synchronize(bridgeOwner, cache);
    bridge.revokeAccess();
    cache.invalidate('late');
    expect(changes, before);
    expect(bridge.isCurrent(lease, bridgeOwner, cache), false);
    expect(bridge.captureLease(bridgeOwner, cache), isNull);
  });
}
