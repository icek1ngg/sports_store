import '../../support/fixtures/in_memory_pending_placement_store.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
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

class _UnavailableStorage implements FlutterSecureStorage {
  _UnavailableStorage({this.failure, this.loseWrite = false});
  final Object? failure;
  final bool loseWrite;
  String? value;
  int deletes = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #write) {
      if (failure != null) return Future<void>.error(failure!);
      value = invocation.namedArguments[#value] as String?;
      return Future<void>.value();
    }
    if (invocation.memberName == #read) {
      if (failure != null) return Future<String?>.error(failure!);
      return Future<String?>.value(loseWrite ? null : value);
    }
    if (invocation.memberName == #delete) {
      deletes++;
      value = null;
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

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

  test(
    'missing native plugin is actionable and cannot report a saved request',
    () async {
      final native = _UnavailableStorage(
        failure: MissingPluginException('private details'),
      );
      final store = SecurePendingPlacementStore(storage: native);
      await expectLater(
        store.write(_userId, _request()),
        throwsA(
          isA<CheckoutFailure>()
              .having(
                (e) => e.code,
                'code',
                CheckoutFailureCode.localStorageUnavailable,
              )
              .having(
                (e) => e.definitiveNoCommit,
                'never sent to server',
                isTrue,
              )
              .having(
                (e) => e.userMessage,
                'restart guidance',
                contains('bản cài mới'),
              )
              .having(
                (e) => e.userMessage,
                'private native detail',
                isNot(contains('private details')),
              ),
        ),
      );
      expect(native.deletes, 0);
    },
  );

  test(
    'successful native reply without a readable durable value is rejected',
    () async {
      final native = _UnavailableStorage(loseWrite: true);
      final store = SecurePendingPlacementStore(storage: native);
      await expectLater(
        store.write(_userId, _request()),
        throwsA(
          isA<CheckoutFailure>().having(
            (e) => e.code,
            'code',
            CheckoutFailureCode.localStorageUnavailable,
          ),
        ),
      );
      expect(native.value, isNotNull);
      expect(native.deletes, 0);
    },
  );

  test('native read failure keeps unknown pending data and is not a proven rollback', () async {
    final native = _UnavailableStorage(
      failure: PlatformException(
        code: 'read',
        message: 'private native detail',
      ),
    );
    final store = SecurePendingPlacementStore(storage: native);
    await expectLater(
      store.read(_userId),
      throwsA(
        isA<CheckoutFailure>()
            .having(
              (e) => e.code,
              'code',
              CheckoutFailureCode.localStorageUnavailable,
            )
            .having(
              (e) => e.definitiveNoCommit,
              'could already be committed',
              isFalse,
            )
            .having(
              (e) => e.userMessage,
              'no native detail',
              isNot(contains('private native detail')),
            ),
      ),
    );
    expect(native.deletes, 0);
  });
}
