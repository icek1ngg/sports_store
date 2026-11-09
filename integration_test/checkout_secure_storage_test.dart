import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sports_store/features/checkout/data/repositories/pending_placement_store.dart';
import 'package:sports_store/features/checkout/domain/models/placement_request.dart';
import 'package:uuid/uuid.dart';

// Native plugin probe only: no Supabase initialization, login or order RPC.
// Run on the isolated emulator created by run_checkout_storage_probe.ps1.
// Each test owns random dummy keys and only clears those keys, never deleteAll.
Future<T> _stage<T>(String stage, Future<T> Function() action) async {
  try {
    final result = await action();
    debugPrint('CHECKOUT_STORAGE_PROBE stage=$stage result=PASS');
    return result;
  } catch (error) {
    final code = error is PlatformException
        ? error.code.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_')
        : 'none';
    final safeCode = code.length > 80 ? code.substring(0, 80) : code;
    // Do not rethrow the native exception: its message/details may contain a
    // storage key or payload. Report only type/code and the fixed stage name.
    final failure =
        'CHECKOUT_STORAGE_PROBE stage=$stage type=${error.runtimeType} code=$safeCode';
    debugPrint(failure);
    throw StateError(failure);
  }
}

PlacementRequest _request() => PlacementRequest(
  requestId: const Uuid().v4(),
  items: [PlacementItem(variantId: const Uuid().v4(), quantity: 1)],
  recipientName: '[TEST] Local storage probe',
  recipientPhone: '0900000000',
  addressDetail: '[TEST] Hanoi local storage fixture',
  latitude: 21.0285,
  longitude: 105.8542,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native default secure storage supports a fresh dummy key', (
    tester,
  ) async {
    const storage = FlutterSecureStorage();
    final key = 'sports_store.probe.${const Uuid().v4()}';
    const value = 'local-native-plugin-probe';
    try {
      await _stage('native_write', () => storage.write(key: key, value: value));
      final restored = await _stage(
        'native_read',
        () => storage.read(key: key),
      );
      expect(
        restored == value,
        isTrue,
        reason: 'Dummy value did not round-trip',
      );
    } finally {
      await _stage('native_clear', () => storage.delete(key: key));
    }
    final cleared = await _stage(
      'native_read_cleared',
      () => storage.read(key: key),
    );
    expect(cleared == null, isTrue);
  });

  testWidgets(
    'production checkout store persists across new instances and isolates users',
    (tester) async {
      final owner = const Uuid().v4();
      final otherOwner = const Uuid().v4();
      final original = _request();
      final replacement = _request();
      final store = SecurePendingPlacementStore();
      try {
        await _stage('checkout_write', () => store.write(owner, original));
        final recovered = await _stage(
          'checkout_new_instance_read',
          () => SecurePendingPlacementStore().read(owner),
        );
        expect(
          recovered?.request.fingerprint == original.fingerprint,
          isTrue,
          reason:
              'A new store instance could not recover the exact dummy request',
        );
        final other = await _stage(
          'checkout_other_user_read',
          () => SecurePendingPlacementStore().read(otherOwner),
        );
        expect(
          other == null,
          isTrue,
          reason: 'Another dummy user saw this request',
        );
        await _stage(
          'checkout_overwrite',
          () => store.write(owner, replacement),
        );
        final updated = await _stage(
          'checkout_new_instance_updated_read',
          () => SecurePendingPlacementStore().read(owner),
        );
        expect(
          updated?.request.fingerprint == replacement.fingerprint,
          isTrue,
          reason: 'Replacement dummy request did not round-trip exactly',
        );
      } finally {
        await _stage('checkout_clear', () => store.clear(owner));
      }
      final cleared = await _stage(
        'checkout_new_instance_cleared_read',
        () => SecurePendingPlacementStore().read(owner),
      );
      expect(cleared == null, isTrue);
    },
  );
}
