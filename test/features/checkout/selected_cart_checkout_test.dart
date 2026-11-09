import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/cart/domain/models/cart_item.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_providers.dart';
import 'package:sports_store/features/cart/presentation/view_models/cart_state.dart';
import 'package:sports_store/features/catalog/domain/models/product.dart';
import 'package:sports_store/features/catalog/domain/models/product_variant.dart';
import 'package:sports_store/features/checkout/data/models/checkout_envelope_dto.dart';

import '../../support/fixtures/in_memory_pending_placement_store.dart';

import 'package:sports_store/features/checkout/domain/models/checkout_failure.dart';
import 'package:sports_store/features/checkout/domain/models/placement_request.dart';
import 'package:sports_store/features/checkout/domain/models/placement_result.dart';
import 'package:sports_store/features/checkout/domain/repositories/checkout_repository.dart';
import 'package:sports_store/features/checkout/presentation/view_models/checkout_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';

const _a = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _variant = '50000000-0000-4000-8000-000000000001';
const _otherVariant = '50000000-0000-4000-8000-000000000002';
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
  _Cart(this.items);
  final List<CartItem> items;
  @override
  Future<CartState> build() async => CartState(items: items);
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
  _Harness(
    this.repository,
    this.store, {
    Set<String>? selectedIds,
    List<CartItem>? items,
  }) {
    container = ProviderContainer(
      overrides: [
        operationalSessionProvider.overrideWith(
          (ref) => Stream<OperationalSession>.multi((sink) {
            sink.addSync(session);
            final sub = changes.stream.listen(sink.addSync);
            sink.onCancel = sub.cancel;
          }),
        ),
        cartProvider.overrideWith(() => _Cart(items ?? _cartItems())),
        selectedCheckoutVariantIdsProvider.overrideWithValue(selectedIds),
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
  Future<void> close() async {
    subscription.close();
    container.dispose();
    await changes.close();
  }
}

List<CartItem> _cartItems({bool unavailableOther = true}) => [
  CartItem(
    variantId: _variant,
    quantity: 2,
    product: _product,
    variant: _product.variants.single,
  ),
  if (unavailableOther) const CartItem(variantId: _otherVariant, quantity: 1),
];

void main() {
  test('selected subset alone is persisted and submitted; unselected unavailable item is ignored', () async {
    final h = _Harness(_Repository(), _Store(), selectedIds: {_variant});
    addTearDown(h.close);
    await h.ready();
    final state = h.container.read(checkoutProvider).requireValue;
    expect(state.items.map((i) => i.variantId), [_variant]);
    expect(state.subtotalVnd, 1380000);
    expect(state.hasUnavailableItems, isFalse);
    expect(state.canSubmit, isTrue);
    expect(await h.submit(), isTrue);
    expect(h.repository.requests.single.items, [
      PlacementItem(variantId: _variant, quantity: 2),
    ]);
  });

  test(
    'legacy null selection keeps all cart rows and blocks unavailable products',
    () async {
      final h = _Harness(_Repository(), _Store());
      addTearDown(h.close);
      await h.ready();
      final state = h.container.read(checkoutProvider).requireValue;
      expect(state.items, hasLength(2));
      expect(state.canSubmit, isFalse);
      expect(await h.submit(), isFalse);
      expect(h.repository.requests, isEmpty);
    },
  );

  for (final ids in <Set<String>>[
    {},
    {''},
    {'unknown'},
    {_variant, 'unknown'},
  ]) {
    test(
      'empty/unknown explicit selection $ids never expands to all cart rows',
      () async {
        final h = _Harness(_Repository(), _Store(), selectedIds: ids);
        addTearDown(h.close);
        await expectLater(
          h.ready(),
          throwsA(
            isA<CheckoutFailure>().having(
              (f) => f.userMessage,
              'message',
              contains('quay lại giỏ hàng'),
            ),
          ),
        );
        expect(await h.submit(), isFalse);
        expect(h.repository.requests, isEmpty);
        expect(await h.store.read(_a), isNull);
      },
    );
  }

  test('selection normalizes UUID case/spacing and deduplicates without dropping invalid IDs', () async {
    final h = _Harness(
      _Repository(),
      _Store(),
      selectedIds: {'  $_variant  ', _variant.toUpperCase()},
    );
    addTearDown(h.close);
    await h.ready();
    expect(h.container.read(checkoutProvider).requireValue.items, hasLength(1));
    expect(await h.submit(), isTrue);
  });

  test('committed pending receipt recovers with an empty consumed cart and stale route selection', () async {
    final store = _Store();
    final intent = _intent();
    await store.write(_a, intent);
    final repository = _Repository()
      ..onLookup = (_) async =>
          PlacementLookupResult.committed(_receipt(intent));
    final h = _Harness(
      repository,
      store,
      selectedIds: {'missing-from-cart'},
      items: [],
    );
    addTearDown(h.close);
    await h.ready();
    final state = h.container.read(checkoutProvider).requireValue;
    expect(state.isSuccess, isTrue);
    expect(state.result!.order.requestId, intent.requestId);
    expect(repository.lookups, [intent.requestId]);
    expect(repository.requests, isEmpty);
    expect(await store.read(_a), isNull);
  });

  test('not_found pending retry keeps old items, quantities and fingerprint despite another selection', () async {
    final intent = _intent();
    final store = _Store();
    await store.write(_a, intent);
    final repository = _Repository();
    final h = _Harness(repository, store, selectedIds: {_otherVariant});
    addTearDown(h.close);
    await h.ready();
    final state = h.container.read(checkoutProvider).requireValue;
    expect(state.recoveryNotFound, isTrue);
    expect(state.items.map((i) => i.variantId), [_variant]);
    expect(state.items.single.quantity, 2);
    expect(state.canSubmit, isFalse);
    expect(await h.submit(), isFalse);
    expect(await h.vm.retryPending(), isTrue);
    expect(repository.requests.single.fingerprint, intent.fingerprint);
  });

  test(
    'empty explicit selection cannot prevent a pending lookup/retry',
    () async {
      final intent = _intent();
      final store = _Store();
      await store.write(_a, intent);
      final h = _Harness(_Repository(), store, selectedIds: {}, items: []);
      addTearDown(h.close);
      await h.ready();
      expect(h.repository.lookups, [intent.requestId]);
      expect(await h.vm.retryPending(), isTrue);
      expect(h.repository.requests.single.fingerprint, intent.fingerprint);
    },
  );

  test(
    'definitive rejection restores this route selection for a new request',
    () async {
      final store = _Store();
      await store.write(_a, _intent());
      final repository = _Repository()
        ..onPlace = (_) async =>
            throw checkoutFailureFromServerCode('insufficient_stock');
      final h = _Harness(repository, store, selectedIds: {_otherVariant});
      addTearDown(h.close);
      await h.ready();
      expect(await h.vm.retryPending(), isFalse);
      final state = h.container.read(checkoutProvider).requireValue;
      expect(state.items.single.variantId, _otherVariant);
      expect(state.hasPendingPlacement, isFalse);
      expect(state.canSubmit, isFalse);
      expect(await h.submit(), isFalse);
      expect(repository.requests, hasLength(1));
      expect(await store.read(_a), isNull);
    },
  );

  test('after a definite pending rejection, a stale selection cannot submit the old recovered items', () async {
    final store = _Store();
    await store.write(_a, _intent());
    final repository = _Repository()
      ..onPlace = (_) async =>
          throw checkoutFailureFromServerCode('insufficient_stock');
    final h = _Harness(repository, store, selectedIds: {});
    addTearDown(h.close);
    await h.ready();
    expect(await h.vm.retryPending(), isFalse);
    expect(h.container.read(checkoutProvider).hasError, isTrue);
    expect(await h.submit(), isFalse);
    expect(repository.requests, hasLength(1));
    expect(await store.read(_a), isNull);
  });
}
