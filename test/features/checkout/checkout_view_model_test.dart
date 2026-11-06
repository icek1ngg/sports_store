import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/cart/domain/models/cart_item.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_providers.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_state.dart';
import 'package:sports_store/features/catalog/domain/models/product.dart';
import 'package:sports_store/features/catalog/domain/models/product_variant.dart';
import 'package:sports_store/features/checkout/data/models/checkout_envelope_dto.dart';
import 'package:sports_store/features/checkout/data/repositories/pending_placement_store.dart';
import 'package:sports_store/features/checkout/domain/models/checkout_failure.dart';
import 'package:sports_store/features/checkout/domain/models/placement_request.dart';
import 'package:sports_store/features/checkout/domain/models/placement_result.dart';
import 'package:sports_store/features/checkout/domain/repositories/checkout_repository.dart';
import 'package:sports_store/features/checkout/presentation/view_models/checkout_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';

const _a = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _b = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _variant = '50000000-0000-4000-8000-000000000001';
const _productId = '40000000-0000-4000-8000-000000000001';

final _product = Product(
  id: _productId,
  categoryId: '30000000-0000-4000-8000-000000000001',
  categoryName: 'Giày',
  name: 'Giày chạy bộ',
  description: null,
  imagePath: null,
  variants: const [
    ProductVariant(
      id: _variant,
      productId: _productId,
      sku: 'RUN40',
      label: 'Cỡ 40',
      attributes: {},
      priceVnd: 690000,
      availableQuantity: 8,
    ),
  ],
);

PlacementRequest _intent() => PlacementRequest(
  requestId: '90000000-0000-4000-8000-000000000001',
  items: [PlacementItem(variantId: _variant, quantity: 2)],
  recipientName: 'Nguyễn Văn A',
  recipientPhone: '0901234567',
  addressDetail: 'Số 1 Tràng Tiền, Hà Nội',
  latitude: 21.0285,
  longitude: 105.8542,
);

PlacementResult _receipt(PlacementRequest request, {String customer = _a}) {
  const orderId = '60000000-0000-4000-8000-000000000001';
  const stamp = '2026-10-26T10:00:00Z';
  return CheckoutEnvelopeDto.decodePlacement({
    'ok': true,
    'error': null,
    'data': {
      'order': {
        'id': orderId,
        'customer_id': customer,
        'request_id': request.requestId,
        'status': 'pending_confirmation',
        'recipient_name': request.recipientName,
        'recipient_phone': request.recipientPhone,
        'address_detail': request.addressDetail,
        'latitude': request.latitude,
        'longitude': request.longitude,
        'subtotal_vnd': 1380000,
        'delivery_fee_vnd': 30000,
        'total_cod_vnd': 1410000,
        'delivery_attempt_count': 0,
        'placed_at': stamp,
        'confirmed_at': null,
        'source': null,
        'confirmed_by': null,
        'delivered_at': null,
        'cancel_reason': null,
        'created_at': stamp,
        'updated_at': stamp,
      },
      'items': [
        {
          'id': '70000000-0000-4000-8000-000000000001',
          'order_id': orderId,
          'product_id': _productId,
          'variant_id': _variant,
          'product_name': 'Giày chạy bộ',
          'variant_label': 'Cỡ 40',
          'attributes': {},
          'unit_price_vnd': 690000,
          'quantity': 2,
          'line_total_vnd': 1380000,
          'created_at': stamp,
        },
      ],
      'event_id': '80000000-0000-4000-8000-000000000001',
      'replayed': false,
    },
  });
}

class _Cart extends CartViewModel {
  @override
  Future<CartState> build() async => CartState(
    items: [
      CartItem(
        variantId: _variant,
        quantity: 2,
        product: _product,
        variant: _product.variants.single,
      ),
    ],
  );
}

class _Repository implements CheckoutRepository {
  Future<PlacementResult> Function(PlacementRequest)? onPlace;
  Future<PlacementLookupResult> Function(String)? onLookup;
  final requests = <PlacementRequest>[];
  final lookups = <String>[];
  @override
  Future<PlacementResult> placeOrder(PlacementRequest request) async {
    requests.add(request);
    return onPlace?.call(request) ?? _receipt(request);
  }

  @override
  Future<PlacementLookupResult> lookupPlacementResult(String requestId) async {
    lookups.add(requestId);
    return onLookup?.call(requestId) ?? const PlacementLookupResult.notFound();
  }
}

class _Store extends InMemoryPendingPlacementStore {
  Completer<void>? writeGate;
  bool rejectWrite = false;
  @override
  Future<void> write(String userId, PlacementRequest request) async {
    if (rejectWrite) throw StateError('device store unavailable');
    if (writeGate != null) await writeGate!.future;
    await super.write(userId, request);
  }
}

class _Harness {
  _Harness(this.repository, this.store) {
    container = ProviderContainer(
      overrides: [
        operationalSessionProvider.overrideWith(
          (ref) => Stream<OperationalSession>.multi((sink) {
            sink.addSync(session);
            final sub = changes.stream.listen(sink.addSync);
            sink.onCancel = sub.cancel;
          }),
        ),
        cartProvider.overrideWith(_Cart.new),
        checkoutRepositoryProvider.overrideWithValue(repository),
        pendingPlacementStoreProvider.overrideWithValue(store),
      ],
    );
    subscription = container.listen(checkoutProvider, (_, _) {});
  }
  final _Repository repository;
  final _Store store;
  final changes = StreamController<OperationalSession>.broadcast(sync: true);
  OperationalSession session = const OperationalSession(
    userId: _a,
    generation: 0,
  );
  late ProviderContainer container;
  late ProviderSubscription subscription;
  CheckoutViewModel get vm => container.read(checkoutProvider.notifier);
  Future<void> ready() async {
    await container.read(checkoutProvider.future);
  }

  Future<bool> submit() => vm.placeOrder(
    recipientName: _intent().recipientName,
    recipientPhone: _intent().recipientPhone,
    addressDetail: _intent().addressDetail,
    latitude: 21.0285,
    longitude: 105.8542,
  );
  Future<void> switchToB() async {
    session = const OperationalSession(userId: _b, generation: 1);
    changes.add(session);
    await Future<void>.delayed(Duration.zero);
    await ready();
  }

  Future<void> close() async {
    subscription.close();
    container.dispose();
    await changes.close();
  }
}

void main() {
  test(
    'double tap while device persistence waits sends exactly one request',
    () async {
      final store = _Store()..writeGate = Completer<void>();
      final h = _Harness(_Repository(), store);
      addTearDown(h.close);
      await h.ready();
      final first = h.submit();
      expect(await h.submit(), isFalse);
      expect(h.repository.requests, isEmpty);
      store.writeGate!.complete();
      expect(await first, isTrue);
      expect(h.repository.requests, hasLength(1));
    },
  );

  test('protected storage failure prevents all network submission', () async {
    final h = _Harness(_Repository(), _Store()..rejectWrite = true);
    addTearDown(h.close);
    await h.ready();
    expect(await h.submit(), isFalse);
    expect(h.repository.requests, isEmpty);
    expect(h.container.read(checkoutProvider).requireValue.isSuccess, isFalse);
  });

  test(
    'timeout survives provider disposal and lookup uses the same request',
    () async {
      final repository = _Repository()
        ..onPlace = (_) async =>
            throw const CheckoutFailure(CheckoutFailureCode.network);
      final store = _Store();
      final first = _Harness(repository, store);
      await first.ready();
      expect(await first.submit(), isFalse);
      final pending = (await store.read(_a))!.request;
      expect(
        first.container.read(checkoutProvider).requireValue.hasPendingPlacement,
        isTrue,
      );
      await first.close();
      repository.onLookup = (_) async =>
          PlacementLookupResult.committed(_receipt(pending));
      final restored = _Harness(repository, store);
      addTearDown(restored.close);
      await restored.ready();
      expect(
        restored.container.read(checkoutProvider).requireValue.isSuccess,
        isTrue,
      );
      expect(repository.lookups.single, pending.requestId);
      expect(repository.requests, hasLength(1));
      expect(await store.read(_a), isNull);
    },
  );

  test(
    'not_found recovery repeats the exact old payload and request ID',
    () async {
      final repository = _Repository()
        ..onPlace = (_) async =>
            throw const CheckoutFailure(CheckoutFailureCode.network);
      final h = _Harness(repository, _Store());
      addTearDown(h.close);
      await h.ready();
      await h.submit();
      final original = repository.requests.single;
      repository.onPlace = (request) async => _receipt(request);
      expect(await h.vm.retryPending(), isTrue);
      expect(repository.requests, hasLength(2));
      expect(repository.requests.last.fingerprint, original.fingerprint);
    },
  );

  test(
    'late account A receipt cannot appear in account B or clear A pending',
    () async {
      final gate = Completer<PlacementResult>();
      final repository = _Repository()..onPlace = (_) => gate.future;
      final h = _Harness(repository, _Store());
      addTearDown(h.close);
      await h.ready();
      final submission = h.submit();
      while (repository.requests.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      final request = repository.requests.single;
      await h.switchToB();
      gate.complete(_receipt(request));
      expect(await submission, isFalse);
      expect(h.container.read(checkoutProvider).requireValue.userId, _b);
      expect(h.container.read(checkoutProvider).requireValue.result, isNull);
      expect(await h.store.read(_a), isNotNull);
      expect(await h.store.read(_b), isNull);
    },
  );

  test(
    'wrong-account recovery receipt keeps pending and shows no success',
    () async {
      final store = _Store();
      await store.write(_a, _intent());
      final repository = _Repository()
        ..onLookup = (_) async =>
            PlacementLookupResult.committed(_receipt(_intent(), customer: _b));
      final h = _Harness(repository, store);
      addTearDown(h.close);
      await h.ready();
      final state = h.container.read(checkoutProvider).requireValue;
      expect(state.isSuccess, isFalse);
      expect(state.hasPendingPlacement, isTrue);
      expect(state.failure?.code, CheckoutFailureCode.invalidData);
      expect(await store.read(_a), isNotNull);
    },
  );

  for (final code in ['idempotency_conflict', 'forbidden_or_unavailable']) {
    test('$code does not discard a possibly committed request', () async {
      final h = _Harness(
        _Repository()
          ..onPlace = (_) async => throw checkoutFailureFromServerCode(code),
        _Store(),
      );
      addTearDown(h.close);
      await h.ready();
      expect(await h.submit(), isFalse);
      expect(
        h.container.read(checkoutProvider).requireValue.hasPendingPlacement,
        isTrue,
      );
      expect(await h.store.read(_a), isNotNull);
    });
  }

  test(
    'definite insufficient stock rejection allows editing and a fresh request',
    () async {
      final h = _Harness(
        _Repository()
          ..onPlace = (_) async =>
              throw checkoutFailureFromServerCode('insufficient_stock'),
        _Store(),
      );
      addTearDown(h.close);
      await h.ready();
      expect(await h.submit(), isFalse);
      expect(
        h.container.read(checkoutProvider).requireValue.hasPendingPlacement,
        isFalse,
      );
      expect(await h.store.read(_a), isNull);
    },
  );
}
