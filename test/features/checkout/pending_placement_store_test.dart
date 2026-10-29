import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sports_store/features/checkout/data/repositories/pending_placement_store.dart';
import 'package:sports_store/features/checkout/domain/models/checkout_failure.dart';
import 'package:sports_store/features/checkout/domain/models/placement_request.dart';

const _userId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _requestId = '90000000-0000-4000-8000-000000000001';
const _variantId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

PlacementRequest _request() => PlacementRequest(
  requestId: _requestId,
  items: [PlacementItem(variantId: _variantId, quantity: 2)],
  recipientName: 'Nguyễn Văn A',
  recipientPhone: '0901234567',
  addressDetail: 'Số 1 Hà Nội',
  latitude: 21.0285,
  longitude: 105.8542,
);

void main() {
  test('Protected store round-trips only the normalized payload', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = SecurePendingPlacementStore();
    await store.write(_userId, _request());
    final pending = await store.read(_userId);
    expect(pending, isNotNull);
    expect(pending!.request.fingerprint, _request().fingerprint);
    expect(
      await const FlutterSecureStorage().read(
        key: 'sports_store.checkout.pending.$_userId',
      ),
      isNot(contains('token')),
    );
    await store.clear(_userId);
    expect(await store.read(_userId), isNull);
  });

  test('malformed pending value fails closed and stays persisted', () async {
    FlutterSecureStorage.setMockInitialValues({
      'sports_store.checkout.pending.$_userId': '{"request_id":"bad"}',
    });
    final store = SecurePendingPlacementStore();
    await expectLater(
      store.read(_userId),
      throwsA(
        isA<CheckoutFailure>().having(
          (failure) => failure.code,
          'code',
          CheckoutFailureCode.invalidData,
        ),
      ),
    );
    expect(
      await const FlutterSecureStorage().read(
        key: 'sports_store.checkout.pending.$_userId',
      ),
      isNotNull,
    );
  });

  test('in-memory store is account scoped', () async {
    final store = InMemoryPendingPlacementStore();
    await store.write(_userId, _request());
    expect(await store.read('BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB'), isNull);
    expect((await store.read(_userId))!.request.requestId, _requestId);
  });
}
